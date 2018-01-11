#include <aalsdk/AAL.h>
#include <aalsdk/xlRuntime.h>
#include <aalsdk/AALLoggerExtern.h> // Logger

#include <aalsdk/service/ICCIAFU.h>
#include <aalsdk/service/ICCIClient.h>

#include <string.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <math.h>
#include <limits.h>
#include <pthread.h>

#include "FPGAHashJoin.h"

using namespace AAL;

void* join_thread(void* args)
{
  int i;
  struct thread_data* my_args;

  my_args = (struct thread_data*) args;

  printf("Thread %d: baseHistogramR %d\n", my_args->tid, my_args->baseHistogramR);
  printf("Thread %d: baseHistogramS %d\n", my_args->tid, my_args->baseHistogramS);
  printf("Thread %d: basePartitionedR %d\n", my_args->tid, my_args->basePartitionedR);
  printf("Thread %d: basePartitionedS %d\n", my_args->tid, my_args->basePartitionedS);
  printf("Thread %d: num_partitions_to_process %d\n", my_args->tid, my_args->num_partitions_to_process);

  relation_t tmpR, tmpS;
  my_args->result = 0;
  uint32_t histogramOffsetR = my_args->baseHistogramR;
  uint32_t histogramOffsetS = my_args->baseHistogramS;
  uint32_t offsetR = my_args->basePartitionedR;
  uint32_t offsetS = my_args->basePartitionedS;
  for (i = 0; i < my_args->num_partitions_to_process; i++)
  {
    uint32_t partitionSizeR = 8*my_args->app->readFromMemory32('o', i + histogramOffsetR);
    uint32_t partitionSizeS = 8*my_args->app->readFromMemory32('o', i + histogramOffsetS);
    if(partitionSizeR > 0 && partitionSizeS > 0)
    {
      printf("Partition %d\n", i);
      tmpR.numTuples = partitionSizeR;
      tmpR.baseTuples = offsetR;
      tmpS.numTuples = partitionSizeS;
      tmpS.baseTuples = offsetS;
      printf("R num_tuples: %d\n", tmpR.numTuples);
      printf("S num_tuples: %d\n", tmpS.numTuples);

      my_args->result += my_args->app->bucket_chaining_join(&tmpR, &tmpS);
    }
    offsetR += my_args->app->R_partition_size_in_cache_lines*8;
    offsetS += my_args->app->S_partition_size_in_cache_lines*8;
  }
}

///////////////////////////////////////////////////////////////////////////////
///
///  Implementation
///
///////////////////////////////////////////////////////////////////////////////
 FPGAHashJoinApp::FPGAHashJoinApp(RuntimeClient *rtc, int _key_bits, int _R_num_tuples, int _S_num_tuples, int _num_radix_bits, int _page_size_in_cache_lines, int _padding_size_divider, int _is_column_store) :
 m_pAALService(NULL),
 m_runtimeClient(rtc),
 m_AFUService(NULL),
 m_Result(0),
 m_DSMVirt(NULL),
 m_DSMPhys(0),
 m_DSMSize(0)
 {
  key_bits = _key_bits;
  R_num_tuples = _R_num_tuples;
  S_num_tuples = _S_num_tuples;
  num_radix_bits = _num_radix_bits;
  fan_out = (1 << _num_radix_bits);
  page_size_in_cache_lines = _page_size_in_cache_lines;
  is_column_store = _is_column_store;
  
  R_cache_lines = R_num_tuples/8;
  S_cache_lines = S_num_tuples/8;
  
  reserved_cl_for_counting = fan_out/16;

  padding_size_divider = _padding_size_divider;
  R_partition_size_in_cache_lines = R_cache_lines/fan_out;
  if (R_partition_size_in_cache_lines > 64)
    R_partition_size_in_cache_lines += (R_partition_size_in_cache_lines >> padding_size_divider);
  else
    R_partition_size_in_cache_lines += 64;

  S_partition_size_in_cache_lines = S_cache_lines/fan_out;
  if (S_partition_size_in_cache_lines > 64)
    S_partition_size_in_cache_lines += (S_partition_size_in_cache_lines >> padding_size_divider);
  else
    S_partition_size_in_cache_lines += 64;

  int i;
  for (i = 0; i < page_count; i++)
  {
    //csr_src_addr[i] = 0x2000 + 4*i;
    //csr_dst_addr[i] = 0x4000 + 4*i;
    m_InputVirt[i] = NULL;
    m_InputPhys[i] = 0;
    m_InputSize[i] = 0;
    m_OutputVirt[i] = NULL;
    m_OutputPhys[i] = 0;
    m_OutputSize[i] = 0;
  }

  SetSubClassInterface(iidServiceClient, dynamic_cast<IServiceClient *>(this));
  SetInterface(iidCCIClient, dynamic_cast<ICCIClient *>(this));
  m_Sem.Create(0, 1);

  btInt Result = allocateWorkspace();
}

FPGAHashJoinApp::~FPGAHashJoinApp()
{
  int i;

  // Release the Workspaces and wait for all three then Release the Service
  for(i = 0; i < page_count; i++)
  {
    m_AFUService->WorkspaceFree(m_InputVirt[i],  TransactionID(i+1));
    m_Sem.Wait();
  }
  for(i = 0; i < page_count; i++)
  {
    m_AFUService->WorkspaceFree(m_OutputVirt[i],  TransactionID(page_count+i+1));
    m_Sem.Wait();
  }
  m_AFUService->WorkspaceFree(m_DSMVirt, TransactionID(0));
  m_Sem.Wait();
  (dynamic_ptr<IAALService>(iidService, m_pAALService))->Release(TransactionID());
  m_Sem.Wait();

  m_runtimeClient->end();

  m_Sem.Destroy();
}

int FPGAHashJoinApp::writeToMemory32(char inOrOut, uint32_t dat32, uint32_t address32)
{
  int whichPage;
  int addressInPage;
  if (page_size_in_cache_lines == 128)
  {
    whichPage = (address32 >> 11);
    addressInPage = address32 & 0x7FF;
  }
  else if (page_size_in_cache_lines == 65536)
  {
    whichPage = (address32 >> 20);
    addressInPage = address32 & 0xFFFFF;
  }
  else
    return -1;
  
  if (inOrOut == 'i')
  {
    if(m_InputVirt[whichPage] != NULL)
    {
      uint32_t* tempPointer = (uint32_t*)m_InputVirt[whichPage];
      tempPointer[addressInPage] = dat32;
    }
    else
      return -1;
  }
  else if (inOrOut == 'o')
  {
    if(m_OutputVirt[whichPage] != NULL)
    {
      uint32_t* tempPointer = (uint32_t*)m_OutputVirt[whichPage];
      tempPointer[addressInPage] = dat32;
    }
    else
      return -1;
  }
  else
    return -1;

  return 0;
}

uint32_t FPGAHashJoinApp::readFromMemory32(char inOrOut, uint32_t address32)
{
  int whichPage;
  int addressInPage;
  if (page_size_in_cache_lines == 128)
  {
    whichPage = (address32 >> 11);
    addressInPage = address32 & 0x7FF;
  }
  else if (page_size_in_cache_lines == 65536)
  {
    whichPage = (address32 >> 20);
    addressInPage = address32 & 0xFFFFF;
  }
  else
    return -1;

  if (inOrOut == 'i')
  {
    if(m_InputVirt[whichPage] != NULL)
    {
      uint32_t* tempPointer = (uint32_t*)m_InputVirt[whichPage];
      return tempPointer[addressInPage];
    }
    else
      return -1;
  }
  else if (inOrOut == 'o')
  {
    if(m_OutputVirt[whichPage] != NULL)
    {
      uint32_t* tempPointer = (uint32_t*)m_OutputVirt[whichPage];
      return tempPointer[addressInPage];
    }
    else
      return -1;
  }
  else
    return -1;

  return 0;
}

int FPGAHashJoinApp::writeToMemory64(char inOrOut, uint64_t dat64, uint32_t address64)
{
  int whichPage;
  int addressInPage;
  if (page_size_in_cache_lines == 128)
  {
    whichPage = (address64 >> 10);
    addressInPage = address64 & 0x3FF;
  }
  else if (page_size_in_cache_lines == 65536)
  {
    whichPage = (address64 >> 19);
    addressInPage = address64 & 0x7FFFF;
  }
  else
    return -1;

  if (inOrOut == 'i')
  {
    if(m_InputVirt[whichPage] != NULL)
    {
      uint64_t* tempPointer = (uint64_t*)m_InputVirt[whichPage];
      tempPointer[addressInPage] = dat64;
    }
    else
      return -1;
  }
  else if (inOrOut == 'o')
  {
    if(m_OutputVirt[whichPage] != NULL)
    {
      uint64_t* tempPointer = (uint64_t*)m_OutputVirt[whichPage];
      tempPointer[addressInPage] = dat64;
    }
    else
      return -1;
  }
  else
    return -1;

  return 0;
}

uint64_t FPGAHashJoinApp::readFromMemory64(char inOrOut, uint32_t address64)
{
  int whichPage;
  int addressInPage;
  if (page_size_in_cache_lines == 128)
  {
    whichPage = (address64 >> 10);
    addressInPage = address64 & 0x3FF;
  }
  else if (page_size_in_cache_lines == 65536)
  {
    whichPage = (address64 >> 19);
    addressInPage = address64 & 0x7FFFF;
  }
  else
    return -1;

  if (inOrOut == 'i')
  {
    if(m_InputVirt[whichPage] != NULL)
    {
      uint64_t* tempPointer = (uint64_t*)m_InputVirt[whichPage];
      return tempPointer[addressInPage];
    }
    else
      return -1;
  }
  else if (inOrOut == 'o')
  {
    if(m_OutputVirt[whichPage] != NULL)
    {
      uint64_t* tempPointer = (uint64_t*)m_OutputVirt[whichPage];
      return tempPointer[addressInPage];
    }
    else
      return -1;
  }
  else
    return -1;

  return 0;
}

int FPGAHashJoinApp::generate_linear_key_relationCS(int offset_in_cache_lines, int num_tuples)
{
  int i, j;
  
  int offset = offset_in_cache_lines*16;
  for(i = 0; i < num_tuples; i++)
  {
    int i_offset = i + offset;
    writeToMemory32('i', i+1, i_offset); // Key
  }
  for (i = num_tuples - 1; i > 0; i--) // Shuffle
  {
    j = RAND_RANGE(i);
    int i_offset = i + offset;
    int j_offset = j + offset;
    uint32_t tempKey = readFromMemory32('i', i_offset);
    writeToMemory32('i', readFromMemory32('i', j_offset), i_offset);
    writeToMemory32('i', tempKey, j_offset);
  }

  return 0;
}

int FPGAHashJoinApp::generate_linear_key_relationRS(int offset_in_cache_lines, int num_tuples)
{
  int i, j;
  
  int offset = offset_in_cache_lines*8;
  for(i = 0; i < num_tuples; i++)
  {
    int i_offset = i + offset;
    writeToMemory32('i', i+1, 2*i_offset); // Key
    writeToMemory32('i', 0x0FFFFFFF-i, 2*i_offset+1); // Payload
  }
  for (i = num_tuples - 1; i > 0; i--) // Shuffle
  {
    j = RAND_RANGE(i);
    int i_offset = i + offset;
    int j_offset = j + offset;
    uint32_t tempKey = readFromMemory32('i', 2*i_offset);
    uint32_t tempPayload = readFromMemory32('i', 2*i_offset+1);
    writeToMemory32('i', readFromMemory32('i', 2*j_offset), 2*i_offset);
    writeToMemory32('i', readFromMemory32('i', 2*j_offset+1), 2*i_offset+1);
    writeToMemory32('i', tempKey, 2*j_offset);
    writeToMemory32('i', tempPayload, 2*j_offset+1);
  }

  return 0;
}

int FPGAHashJoinApp::generate_random_key_relationCS(int offset_in_cache_lines, int num_tuples)
{
  int i;

  int offset = offset_in_cache_lines*16;
  for(i = 0; i < num_tuples; i++)
  {
    int i_offset = i + offset;
    uint32_t temp;
    temp = (uint32_t)rand();

    writeToMemory32('i', temp, i_offset); // Key
  }
  
  return 0;
}

int FPGAHashJoinApp::generate_random_key_relationRS(int offset_in_cache_lines, int num_tuples)
{
  int i;
 
  int offset = offset_in_cache_lines*8;
  for(i = 0; i < num_tuples; i++)
  {
    int i_offset = i + offset;
    uint32_t temp;
    temp = (uint32_t)rand();

    writeToMemory32('i', temp, 2*i_offset); // Key
    writeToMemory32('i', i+1, 2*i_offset+1);  // Payload
  }

  return 0;
}

int FPGAHashJoinApp::generate_grid_key_relationCS(int offset_in_cache_lines, int num_tuples)
{
  int i, j;

  int offset = offset_in_cache_lines*16;
  uint8_t values[4];
  for (j = 0; j < 4; j++)
  {
    values[j] = 1;
  }
  for (i = 0; i < num_tuples; i++) // Generate
  {
    int i_offset = i + offset;
    uint32_t temp;
    temp = (uint32_t)values[0];
    temp += ((uint32_t)values[1]) << 8;
    temp += ((uint32_t)values[2]) << 16;
    temp += ((uint32_t)values[3]) << 24;
    writeToMemory32('i', temp, i_offset); // Key
    for (j = 0; j < 4; j++)
    {
      values[j] += 1;
      if (values[j] <= 14)
        break;
      else
        values[j] = 1;
    }
  }
  for (i = num_tuples - 1; i > 0; i--) // Shuffle
  {
    j = RAND_RANGE(i);
    int i_offset = i + offset;
    int j_offset = j + offset;
    uint32_t tempKey = readFromMemory32('i', i_offset);
    writeToMemory32('i', readFromMemory32('i', j_offset), i_offset);
    writeToMemory32('i', tempKey, j_offset);
  }

  return 0;
}

int FPGAHashJoinApp::generate_grid_key_relationRS(int offset_in_cache_lines, int num_tuples)
{
  int i, j;

  int offset = offset_in_cache_lines*8;
  uint8_t values[4];
  for (j = 0; j < 4; j++)
  {
    values[j] = 1;
  }
  for (i = 0; i < num_tuples; i++) // Generate
  {
    int i_offset = i + offset;
    uint32_t temp;
    temp = (uint32_t)values[0];
    temp += ((uint32_t)values[1]) << 8;
    temp += ((uint32_t)values[2]) << 16;
    temp += ((uint32_t)values[3]) << 24;
    writeToMemory32('i', temp, 2*i_offset); // Key
    writeToMemory32('i', i+1, 2*i_offset+1);  // Payload
    for (j = 0; j < 4; j++)
    {
      values[j] += 1;
      if (values[j] <= 14)
        break;
      else
        values[j] = 1;
    }
  }
  for (i = num_tuples - 1; i > 0; i--) // Shuffle
  {
    j = RAND_RANGE(i);
    int i_offset = i + offset;
    int j_offset = j + offset;
    uint32_t tempKey = readFromMemory32('i', 2*i_offset);
    uint32_t tempPayload = readFromMemory32('i', 2*i_offset+1);
    writeToMemory32('i', readFromMemory32('i', 2*j_offset), 2*i_offset);
    writeToMemory32('i', readFromMemory32('i', 2*j_offset+1), 2*i_offset+1);
    writeToMemory32('i', tempKey, 2*j_offset);
    writeToMemory32('i', tempPayload, 2*j_offset+1);
  }

  return 0;
}

btInt FPGAHashJoinApp::allocateWorkspace()
{
  int i;

  // Request our AFU.

  // NOTE: This example is bypassing the Resource Manager's configuration record lookup
  //  mechanism.  This code is work around code and subject to change. But it does
  //  illustrate the utility of having different implementations of a service all
  //  readily available and bound at run-time.
  NamedValueSet Manifest;
  NamedValueSet ConfigRecord;

#if defined( HWAFU )                /* Use FPGA hardware */

  ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libHWCCIAFU");
  ConfigRecord.Add(keyRegAFU_ID,"C000C966-0D82-4272-9AEF-FE5F84570612");
  ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_AIA_NAME, "libAASUAIA");

#elif defined ( ASEAFU )         /* Use ASE based RTL simulation */

  ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libASECCIAFU");
  ConfigRecord.Add(AAL_FACTORY_CREATE_SOFTWARE_SERVICE,true);

#else                            /* default is Software Simulator */

  ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libSWSimCCIAFU");
  ConfigRecord.Add(AAL_FACTORY_CREATE_SOFTWARE_SERVICE,true);

#endif
  Manifest.Add(AAL_FACTORY_CREATE_CONFIGRECORD_INCLUDED, ConfigRecord);
  Manifest.Add(AAL_FACTORY_CREATE_SERVICENAME, "FPGAHashJoinApp");
  MSG("Allocating Service");

  m_runtimeClient->getRuntime()->allocService(dynamic_cast<IBase *>(this), Manifest);
  m_Sem.Wait();

  m_AFUService->WorkspaceAllocate(DSM_SIZE, TransactionID(0));
  m_Sem.Wait();

  for(i = 0; i < page_count; i++) // Input
  {
    m_AFUService->WorkspaceAllocate(CL(page_size_in_cache_lines), TransactionID(i+1));
    m_Sem.Wait();
  }
  for(i = 0; i < page_count; i++) // Output
  {
    m_AFUService->WorkspaceAllocate(CL(page_size_in_cache_lines), TransactionID(page_count+i+1));
    m_Sem.Wait();
  }

  MSG("Zeroing allocated pages.");
  for(i = 0; i < page_count*page_size_in_cache_lines*8; i++)
  {
    writeToMemory64('i', 0, i);
    writeToMemory64('o', 0, i);
  }
  
  if (m_Result == 0)
  {
    // Clear the DSM
    memset((void *)m_DSMVirt, 0, m_DSMSize);

    // Set DSM base, high then low
    m_AFUService->CSRWrite64(CSR_AFU_DSM_BASEL, m_DSMPhys);

    // If ASE, give it some time to catch up
    #if defined ( ASEAFU )
    SleepSec(5);
    #endif /* ASE AFU */

    // Assert Device Reset
    m_AFUService->CSRWrite(CSR_CTL, 0);

    // De-assert Device Reset
    m_AFUService->CSRWrite(CSR_CTL, 1);

    m_AFUService->CSRWrite(CSR_ADDR_RESET, 0);

    // Source pages
    m_AFUService->CSRWrite(CSR_SRC_ADDR, 0);
    m_AFUService->CSRWrite(CSR_ADDR_RESET, 1);
    for(i = 0; i < page_count; i++)
    {
      // Set input workspace address
      m_AFUService->CSRWrite(CSR_SRC_ADDR, CACHELINE_ALIGNED_ADDR(m_InputPhys[i]));
    }
    m_AFUService->CSRWrite(CSR_SRC_ADDR, 0);

    // Destination pages
    m_AFUService->CSRWrite(CSR_DST_ADDR, 0);
    m_AFUService->CSRWrite(CSR_ADDR_RESET, 2);
    for(i = 0; i < page_count; i++)
    {
      // Set output workspace address
      m_AFUService->CSRWrite(CSR_DST_ADDR, CACHELINE_ALIGNED_ADDR(m_OutputPhys[i]));
    }
    m_AFUService->CSRWrite(CSR_DST_ADDR, 0);

    m_AFUService->CSRWrite(CSR_ADDR_RESET, 0xFFFFFFFF);

    // Set the test mode
    m_AFUService->CSRWrite(CSR_CFG, padding_size_divider << 24 | /*murmur(0) or modulo(1)*/ 1 << 20 | /*Row Store(0) or Column Store(1)*/ is_column_store << 1);
  }

  return m_Result;
}

btInt FPGAHashJoinApp::partition()
{
  int i;
  
  if(0 == m_Result){

    if(is_column_store) {
      m_Result = generate_linear_key_relationCS(0, R_num_tuples); // Generate R
      m_Result = generate_linear_key_relationCS(R_cache_lines/2, S_num_tuples); // Generate S
    }
    else {
      m_Result = generate_linear_key_relationRS(0, R_num_tuples); // Generate R
      m_Result = generate_linear_key_relationRS(R_cache_lines, S_num_tuples); // Generate S
    }

    
    if(is_column_store) {
      m_AFUService->CSRWrite(CSR_NUM_LINES, R_cache_lines);
    }
    else {
      m_AFUService->CSRWrite(CSR_NUM_LINES, R_cache_lines);
    }
    m_AFUService->CSRWrite(CSR_EXP_NUM_LINES, R_cache_lines);
    m_AFUService->CSRWrite(CSR_READ_OFFSET, 0);
    m_AFUService->CSRWrite(CSR_WRITE_OFFSET, 0);
    m_AFUService->CSRWrite(CSR_RADIX_BITS, num_radix_bits);
    m_AFUService->CSRWrite(CSR_DUMMY_KEY, 0xFFFFFFFF);

    doTransaction();

    // if(is_column_store) {
    //   m_AFUService->CSRWrite(CSR_NUM_LINES, S_cache_lines/2);
    //   m_AFUService->CSRWrite(CSR_READ_OFFSET, R_cache_lines/2);
    // }
    // else {
    //   m_AFUService->CSRWrite(CSR_NUM_LINES, S_cache_lines);
    //   m_AFUService->CSRWrite(CSR_READ_OFFSET, R_cache_lines);
    // }
    // m_AFUService->CSRWrite(CSR_EXP_NUM_LINES, S_cache_lines);
    // m_AFUService->CSRWrite(CSR_WRITE_OFFSET, reserved_cl_for_counting + R_partition_size_in_cache_lines*fan_out);
    // m_AFUService->CSRWrite(CSR_RADIX_BITS, num_radix_bits);
    // m_AFUService->CSRWrite(CSR_DUMMY_KEY, 0xEEEEEEEE);

    // doTransaction();

    MSG("Done Partitioning");
  }

  return m_Result;
}

void FPGAHashJoinApp::doTransaction()
{
  // Assert Device Reset
  m_AFUService->CSRWrite(CSR_CTL, 0);

  // De-assert Device Reset
  m_AFUService->CSRWrite(CSR_CTL, 1);

  volatile bt32bitCSR *StatusAddr = (volatile bt32bitCSR *)(m_DSMVirt  + DSM_STATUS_TEST_COMPLETE);

  // Start the test
  m_AFUService->CSRWrite(CSR_CTL, 3);

  // Wait for test completion
  while( 0 == *StatusAddr )
  {
    SleepMicro(100);
  }
  *StatusAddr = 0;
}

uint32_t FPGAHashJoinApp::join(int num_threads)
{
  int tuples_per_cache_line = 8;
  int reserved_for_counting = fan_out/2;
  int i, j;
  int result;

  uint32_t histogram_countR = 0;
  uint32_t partitioning_countR = 0;
  uint32_t histogram_countS = 0;
  uint32_t partitioning_countS = 0;

  printf("Starting join\n");

  double start = get_time();

  relation_t tmpR, tmpS;
  result = 0;
  uint32_t histogramOffsetR = 0;
  uint32_t histogramOffsetS = 2*(reserved_for_counting + R_partition_size_in_cache_lines*tuples_per_cache_line*fan_out);
  uint32_t offsetR = reserved_for_counting;
  uint32_t offsetS = 2*reserved_for_counting + R_partition_size_in_cache_lines*tuples_per_cache_line*fan_out;
  if (num_threads == 1)
  {
    for(i = 0; i < fan_out; i++ )
    {
      uint32_t partitionSizeR = 8*readFromMemory32('o', i + histogramOffsetR);
      uint32_t partitionSizeS = 8*readFromMemory32('o', i + histogramOffsetS);
      if(partitionSizeR > 0 && partitionSizeS > 0)
      {
        printf("Partition %d\n", i);
        tmpR.numTuples = partitionSizeR;
        tmpR.baseTuples = offsetR;
        tmpS.numTuples = partitionSizeS;
        tmpS.baseTuples = offsetS;
        printf("R num_tuples: %d\n", tmpR.numTuples);
        printf("S num_tuples: %d\n", tmpS.numTuples);

        result += bucket_chaining_join(&tmpR, &tmpS);
        printf("Result: %d\n", result);
      }
      offsetR += R_partition_size_in_cache_lines*tuples_per_cache_line;
      offsetS += S_partition_size_in_cache_lines*tuples_per_cache_line;
    }
  }
  else
  {
    pthread_t threads[num_threads];
    struct thread_data args[num_threads];
    for(i = 0; i < num_threads; i++ )
    {
      args[i].num_partitions_to_process = fan_out/num_threads;
      args[i].baseHistogramR = histogramOffsetR;
      args[i].baseHistogramS = histogramOffsetS;
      args[i].basePartitionedR = offsetR;
      args[i].basePartitionedS = offsetS;
      args[i].app = this;
      pthread_create(&threads[i], NULL, join_thread, (void*)&args[i]);
      
      offsetR += R_partition_size_in_cache_lines*tuples_per_cache_line*args->num_partitions_to_process;
      offsetS += S_partition_size_in_cache_lines*tuples_per_cache_line*args->num_partitions_to_process;
      histogramOffsetR += args->num_partitions_to_process;
      histogramOffsetS += args->num_partitions_to_process;
    }
    for(i = 0; i < num_threads; i++ )
    {
      pthread_join(threads[i], NULL);
      result += args[i].result;
    }
  }
  double difference = get_time() - start;
  printf("Total time for joining: %.10f\n", difference);

  uint64_t countersR = readFromMemory64('o', offsetR - tuples_per_cache_line);
  histogram_countR = (countersR >> 32) & 0xFFFFFFFF;
  partitioning_countR = countersR & 0xFFFFFFFF;
  uint64_t countersS = readFromMemory64('o', offsetS - tuples_per_cache_line);
  histogram_countS = (countersS >> 32) & 0xFFFFFFFF;
  partitioning_countS = countersS & 0xFFFFFFFF;

  printf("Histogram Count R: %d, Partitioning Count R: %d\n", histogram_countR, partitioning_countR);
  printf("Histogram Count S: %d, Partitioning Count S: %d\n", histogram_countS, partitioning_countS);

  printf("Result: %d\n", result);
}

uint32_t FPGAHashJoinApp::bucket_chaining_join(const relation_t * const R, const relation_t * const S)
{
  int * next, * bucket;
  const uint32_t numR = R->numTuples;
  uint32_t N = numR;
  int64_t matches = 0;

  NEXT_POW_2(N);
  /* N <<= 1; */
  const uint32_t MASK = (N-1) << num_radix_bits;

  next   = (int*) malloc(sizeof(int) * numR);
  /* posix_memalign((void**)&next, CACHE_LINE_SIZE, numR * sizeof(int)); */
  bucket = (int*) calloc(N, sizeof(int));

  const uint32_t Rtuples = R->baseTuples;
  for(uint32_t i=0; i < numR; ){
      uint32_t Rkey = (uint32_t)readFromMemory64('o', Rtuples + i) & 0xFFFFFFFF;
      uint32_t idx = HASH_BIT_MODULO(Rkey, MASK, num_radix_bits);
      next[i]      = bucket[idx];
      bucket[idx]  = ++i;     /* we start pos's from 1 instead of 0 */

      /* Enable the following tO avoid the code elimination
         when running probe only for the time break-down experiment */
      /* matches += idx; */
  }

  const uint32_t Stuples = S->baseTuples;
  const uint32_t numS    = S->numTuples;

  /* Disable the following loop for no-probe for the break-down experiments */
  /* PROBE- LOOP */
  for(uint32_t i=0; i < numS; i++ ){
      uint32_t Skey = (uint32_t)readFromMemory64('o', Stuples + i) & 0xFFFFFFFF;
      uint32_t idx = HASH_BIT_MODULO(Skey, MASK, num_radix_bits);

      // if (bucket[idx] == 0)
      //  printf("Did not match S key: %x\n", Stuples[i].key);

      for(int hit = bucket[idx]; hit > 0; hit = next[hit-1]){
          uint32_t Rkey = (uint32_t)readFromMemory64('o', Rtuples + hit-1) & 0xFFFFFFFF;
          if(Skey == Rkey){
              /* TODO: copy to the result buffer, we skip it */
              matches ++;
          }
      }
  }
  /* PROBE-LOOP END  */
  
  /* clean up temp */
  free(bucket);
  free(next);

  return matches;
}

// We must implement the IServiceClient interface (IServiceClient.h):

// <begin IServiceClient interface>
void FPGAHashJoinApp::serviceAllocated(IBase *pServiceBase,
TransactionID const &rTranID)
{
  m_pAALService = pServiceBase;
  ASSERT(NULL != m_pAALService);

  // Documentation says CCIAFU Service publishes ICCIAFU as subclass interface
  m_AFUService = subclass_ptr<ICCIAFU>(pServiceBase);

  ASSERT(NULL != m_AFUService);
  if ( NULL == m_AFUService ) {
    return;
  }

  MSG("Service Allocated");
  m_Sem.Post(1);
}

void FPGAHashJoinApp::serviceAllocateFailed(const IEvent &rEvent)
{
  IExceptionTransactionEvent * pExEvent = dynamic_ptr<IExceptionTransactionEvent>(iidExTranEvent, rEvent);
  ERR("Failed to allocate a Service");
  ERR(pExEvent->Description());
  ++m_Result;                     // Remember the error

  m_Sem.Post(1);
}

void FPGAHashJoinApp::serviceFreed(TransactionID const &rTranID)
{
  MSG("Service Freed");
  // Unblock Main()
  m_Sem.Post(1);
}

// <ICCIClient>
void FPGAHashJoinApp::OnWorkspaceAllocated(TransactionID const &TranID,
btVirtAddr           WkspcVirt,
btPhysAddr           WkspcPhys,
btWSSize             WkspcSize)
{
  AutoLock(this);

  if (TranID.ID() == 0)
  {
    m_DSMVirt = WkspcVirt;
    m_DSMPhys = WkspcPhys;
    m_DSMSize = WkspcSize;
    MSG("Got DSM");
    printf("DSM Virt:%x, Phys:%x, Size:%d\n", m_DSMVirt, m_DSMPhys, m_DSMSize);
    m_Sem.Post(1);
  }
  else if(TranID.ID() >= 1 && TranID.ID() <= page_count)
  {
    int index = TranID.ID()-1;
    m_InputVirt[index] = WkspcVirt;
    m_InputPhys[index] = WkspcPhys;
    m_InputSize[index] = WkspcSize;
    // MSG("Got Input Workspace");
    // printf("Input Virt:%x, Phys:%x, Size:%d\n", m_InputVirt[index], m_InputPhys[index], m_InputSize[index]);
    m_Sem.Post(1);
  }
  else if(TranID.ID() >= page_count+1 && TranID.ID() <= 2*page_count)
  {
    int index = TranID.ID()-(page_count+1);
    m_OutputVirt[index] = WkspcVirt;
    m_OutputPhys[index] = WkspcPhys;
    m_OutputSize[index] = WkspcSize;
    // MSG("Got Output Workspace");
    // printf("Output Virt:%x, Phys:%x, Size:%d\n", m_OutputVirt[index], m_OutputPhys[index], m_OutputSize[index]);
    m_Sem.Post(1);
  }
  else
  {
    ++m_Result;
    ERR("Invalid workspace type: " << TranID.ID());
  }
}

void FPGAHashJoinApp::OnWorkspaceAllocateFailed(const IEvent &rEvent)
{
 IExceptionTransactionEvent * pExEvent = dynamic_ptr<IExceptionTransactionEvent>(iidExTranEvent, rEvent);
 ERR("OnWorkspaceAllocateFailed");
 ERR(pExEvent->Description());

   ++m_Result;                     // Remember the error
   m_Sem.Post(1);
 }

void FPGAHashJoinApp::OnWorkspaceFreed(TransactionID const &TranID)
{
  // MSG("OnWorkspaceFreed");
  m_Sem.Post(1);
}

void FPGAHashJoinApp::OnWorkspaceFreeFailed(const IEvent &rEvent)
{
 IExceptionTransactionEvent * pExEvent = dynamic_ptr<IExceptionTransactionEvent>(iidExTranEvent, rEvent);
 ERR("OnWorkspaceAllocateFailed");
 ERR(pExEvent->Description());
   ++m_Result;                     // Remember the error
   m_Sem.Post(1);
 }


 void FPGAHashJoinApp::serviceEvent(const IEvent &rEvent)
 {
   ERR("unexpected event 0x" << hex << rEvent.SubClassID());
 }
// <end IServiceClient interface>

/// @} group FPGAHashJoin


//=============================================================================
// Name: main
// Description: Entry point to the application
// Inputs: none
// Outputs: none
// Comments: Main initializes the system. The rest of the example is implemented
//           in the objects.
//=============================================================================


int NUM_RADIX_BITS = 4;
int NUM_JOIN_THREADS = 2;

int main(int argc, char *argv[])
{
  RuntimeClient  runtimeClient;
  int key_bits = 32;
  int R_num_tuples = 8192;
  int S_num_tuples = 8192;
  int page_size_in_cache_lines = 65536;
  //int page_size_in_cache_lines = 128;
  int padding_size_divider = 2;
  int is_column_store = 1;

  FPGAHashJoinApp theApp(&runtimeClient, key_bits, R_num_tuples, S_num_tuples, NUM_RADIX_BITS, page_size_in_cache_lines, padding_size_divider, is_column_store);
  if(!runtimeClient.isOK()){
    ERR("Runtime Failed to Start");
    exit(1);
  }

  theApp.partition();

  //theApp.join(NUM_JOIN_THREADS);
  
  int i;
  FILE* f;
  f = fopen("outputMemory.txt", "w");
  for(i = 0; i < theApp.reserved_cl_for_counting*8 + theApp.fan_out*theApp.R_partition_size_in_cache_lines*8; i++)
  {
  	uint64_t temp = theApp.readFromMemory64('o', i);
    uint32_t word1 = (uint32_t)(temp & 0xFFFFFFFF);
    uint32_t word2 = (uint32_t)((temp >> 32) & 0xFFFFFFFF);
    fprintf(f, "%x\t%x\n", word1, word2);
  }
  fclose(f);

  MSG("Done");
  return 0;
}

