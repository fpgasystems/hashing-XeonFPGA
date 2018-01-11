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
#include <iostream>
#include "RuntimeClient.h"
#include "hash_functions.h"

using namespace AAL;

#if 1
# define EVENT_CASE(x) case x : MSG(#x);
#else
# define EVENT_CASE(x) case x :
#endif

#ifndef CL
# define CL(x)                     ((x) * 64)
#endif // CL
#ifndef LOG2_CL
# define LOG2_CL                   6
#endif // LOG2_CL
#ifndef MB
# define MB(x)                     ((x) * 1024 * 1024)
#endif // MB
#define RAND_RANGE(N) ((double)rand() / ((double)RAND_MAX + 1) * (N))
#define HASH_BIT_MODULO(K, MASK, NBITS) (((K) & MASK) >> NBITS)

#define DSM_SIZE           MB(4)
#define CSR_AFU_DSM_BASEH        0x1a04
#define CSR_SRC_ADDR             0x1a20
#define CSR_DST_ADDR             0x1a24
#define CSR_CTL                  0x1a2c
#define CSR_CFG                  0x1a34
#define CSR_CIPUCTL              0x280
#define CSR_NUM_LINES            0x1a28
#define DSM_STATUS_TEST_COMPLETE 0x40
#define CSR_AFU_DSM_BASEL        0x1a00
#define CSR_AFU_DSM_BASEH        0x1a04
#define CSR_DUMMY_KEY			       0x1b00

double get_time()
{
	struct timeval t;
	struct timezone tzp;
	gettimeofday(&t, &tzp);
	return t.tv_sec + t.tv_usec*1e-6;
}

/// @brief   Define our Service client class so that we can receive Service-related notifications from the AAL Runtime.
///          The Service Client contains the application logic.
///
/// When we request an AFU (Service) from AAL, the request will be fulfilled by calling into this interface.
class FPGAHashingApp: public CAASBase, public IServiceClient, public ICCIClient
{
	public:
	FPGAHashingApp(RuntimeClient * rtc, int _key_bits, int _num_keys, int _page_size_in_cache_lines);
	~FPGAHashingApp();

	int writeToMemory32(char inOrOut, uint32_t dat32, uint32_t address32);
	uint32_t readFromMemory32(char inOrOut, uint32_t address32);
	int writeToMemory64(char inOrOut, uint64_t dat64, uint32_t address64);
	uint64_t readFromMemory64(char inOrOut, uint32_t address64);
	int generate_linear_keys(int offset_in_cache_lines, int num);
	int generate_linearoffset_keys(int offset_in_cache_lines, int num);
	int generate_random_keys(int offset_in_cache_lines, int num);
	int generate_grid_keys(int offset_in_cache_lines, int num);
	int generate_gridreversed_keys(int offset_in_cache_lines, int num);

	btInt allocateWorkspace();

	btInt populateTables();    ///< Return 0 if success
	btInt hash(char hash_function);
	btInt swhash(char hash_function);
	void doTransaction();

	// <ICCIClient>
	virtual void OnWorkspaceAllocated(TransactionID const &TranID,
		btVirtAddr WkspcVirt,
		btPhysAddr WkspcPhys,
		btWSSize WkspcSize);

	virtual void OnWorkspaceAllocateFailed(const IEvent &Event);

	virtual void OnWorkspaceFreed(TransactionID const &TranID);

	virtual void OnWorkspaceFreeFailed(const IEvent &Event);
	// </ICCIClient>

	// <begin IServiceClient interface>
	void serviceAllocated(IBase *pServiceBase,
		TransactionID const &rTranID);

	void serviceAllocateFailed(const IEvent &rEvent);

	void serviceFreed(TransactionID const &rTranID);

	void serviceEvent(const IEvent &rEvent);
	// <end IServiceClient interface>

	protected:
	static const int page_count = 8;
	int key_bits;
	int num_keys;
	int page_size_in_cache_lines;
	int num_cache_lines;
	uint32_t* tables[8];

	IBase         *m_pAALService;    // The generic AAL Service interface for the AFU.
	RuntimeClient *m_runtimeClient;
	ICCIAFU       *m_AFUService;
	CSemaphore     m_Sem;            // For synchronizing with the AAL runtime.
	btInt          m_Result;         // Returned result value; 0 if success

	// Workspace info
	//uint16_t csr_src_addr[page_count];
	//uint16_t csr_dst_addr[page_count];
	btVirtAddr     m_DSMVirt;        ///< DSM workspace virtual address.
	btPhysAddr     m_DSMPhys;        ///< DSM workspace physical address.
	btWSSize       m_DSMSize;        ///< DSM workspace size in bytes.
	btVirtAddr     m_InputVirt[page_count];      ///< Input workspace virtual address.
	btPhysAddr     m_InputPhys[page_count];      ///< Input workspace physical address.
	btWSSize       m_InputSize[page_count];      ///< Input workspace size in bytes.
	btVirtAddr     m_OutputVirt[page_count];     ///< Output workspace virtual address.
	btPhysAddr     m_OutputPhys[page_count];     ///< Output workspace physical address.
	btWSSize       m_OutputSize[page_count];     ///< Output workspace size in bytes.
};

///////////////////////////////////////////////////////////////////////////////
///
///  Implementation
///
///////////////////////////////////////////////////////////////////////////////
FPGAHashingApp::FPGAHashingApp(RuntimeClient *rtc, int _key_bits, int _num_keys, int _page_size_in_cache_lines) :
m_pAALService(NULL),
m_runtimeClient(rtc),
m_AFUService(NULL),
m_Result(0),
m_DSMVirt(NULL),
m_DSMPhys(0),
m_DSMSize(0)
{
	int i;

	key_bits = _key_bits;
	num_keys = _num_keys;
	page_size_in_cache_lines = _page_size_in_cache_lines;
	if (key_bits == 32)
	{
		num_cache_lines = num_keys/16;
	}
	else if(key_bits == 64)
	{
		num_cache_lines = num_keys/8;
	}
	for(i = 0; i < 8; i++)
	{
		tables[i] = (uint32_t*)malloc(256*sizeof(uint32_t));
		if(tables[i] == NULL)
		{
			printf("Cannot allocate tables\n");
		}
	}
	
	for (i = 0; i < page_count; i++)
	{
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

FPGAHashingApp::~FPGAHashingApp()
{
	int i;

	for(i = 0; i < 8; i++)
	{
		free(tables[i]);
	}

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

int FPGAHashingApp::writeToMemory32(char inOrOut, uint32_t dat32, uint32_t address32)
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

uint32_t FPGAHashingApp::readFromMemory32(char inOrOut, uint32_t address32)
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

int FPGAHashingApp::writeToMemory64(char inOrOut, uint64_t dat64, uint32_t address64)
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

uint64_t FPGAHashingApp::readFromMemory64(char inOrOut, uint32_t address64)
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

int FPGAHashingApp::generate_linear_keys(int offset_in_cache_lines, int num)
{
  int i, j;
  if (key_bits == 32)
  {
    int offset = offset_in_cache_lines*16;
    for(i = 0; i < num; i++)
    {
      int i_offset = i + offset;
      writeToMemory32('i', i+1, i_offset); // Key
    }
    for (i = num - 1; i > 0; i--) // Shuffle
    {
      j = RAND_RANGE(i);
      int i_offset = i + offset;
      int j_offset = j + offset;
      uint32_t tempKey = readFromMemory32('i', i_offset);
      writeToMemory32('i', readFromMemory32('i', j_offset), i_offset);
      writeToMemory32('i', tempKey, j_offset);
    }
  }
  else if (key_bits == 64)
  {
    int offset = offset_in_cache_lines*8;
    for(i = 0; i < num; i++)
    {
      int i_offset = i + offset;
      writeToMemory64('i', i+1, i_offset); // Key
    }
    for (i = num - 1; i > 0; i--) // Shuffle
    {
      j = RAND_RANGE(i);
      int i_offset = i + offset;
      int j_offset = j + offset;
      uint64_t tempKey = readFromMemory64('i', i_offset);
      writeToMemory64('i', readFromMemory64('i', j_offset), i_offset);
      writeToMemory64('i', tempKey, j_offset);
    }
  }
  else
    return -1;

  return 0;
}

int FPGAHashingApp::generate_linearoffset_keys(int offset_in_cache_lines, int num)
{
  int i, j;
  if (key_bits == 32)
  {
    int offset = offset_in_cache_lines*16;
    for(i = 0; i < num; i++)
    {
      int i_offset = i + offset;
      writeToMemory32('i', (i << 2) + i, i_offset); // Key
    }
    for (i = num - 1; i > 0; i--) // Shuffle
    {
      j = RAND_RANGE(i);
      int i_offset = i + offset;
      int j_offset = j + offset;
      uint32_t tempKey = readFromMemory32('i', i_offset);
      writeToMemory32('i', readFromMemory32('i', j_offset), i_offset);
      writeToMemory32('i', tempKey, j_offset);
    }
  }
  else if (key_bits == 64)
  {
    int offset = offset_in_cache_lines*8;
    for(i = 0; i < num; i++)
    {
      int i_offset = i + offset;
      uint64_t temp = 1;
      temp = temp << 54;
      temp += (i << 4);
      writeToMemory64('i', temp , i_offset); // Key
    }
    for (i = num - 1; i > 0; i--) // Shuffle
    {
      j = RAND_RANGE(i);
      int i_offset = i + offset;
      int j_offset = j + offset;
      uint64_t tempKey = readFromMemory64('i', i_offset);
      writeToMemory64('i', readFromMemory64('i', j_offset), i_offset);
      writeToMemory64('i', tempKey, j_offset);
    }
  }
  else
    return -1;

  return 0;
}

int FPGAHashingApp::generate_random_keys(int offset_in_cache_lines, int num)
{
  int i;
  if (key_bits == 32)
  {
    int offset = offset_in_cache_lines*16;
    for(i = 0; i < num; i++)
    {
      int i_offset = i + offset;
      uint32_t temp;
      temp = (uint32_t)rand();

      writeToMemory32('i', temp, i_offset); // Key
    }
  }
  else if(key_bits == 64)
  {
    int offset = offset_in_cache_lines*8;
    for(i = 0; i < num; i++)
    {
      int i_offset = i + offset;
      uint64_t temp;
      temp = (uint64_t)rand();
      temp += (((uint64_t)rand()) << 32);

      writeToMemory64('i', temp, i_offset); // Key
    }
  }
  else
    return -1;

  return 0;
}

int FPGAHashingApp::generate_grid_keys(int offset_in_cache_lines, int num)
{
  int i, j;

  if(key_bits == 32)
  {
    int offset = offset_in_cache_lines*16;
    uint8_t values[4];
    for (j = 0; j < 4; j++)
    {
      values[j] = 1;
    }
    for (i = 0; i < num; i++) // Generate
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
    for (i = num - 1; i > 0; i--) // Shuffle
    {
      j = RAND_RANGE(i);
      int i_offset = i + offset;
      int j_offset = j + offset;
      uint32_t tempKey = readFromMemory32('i', i_offset);
      writeToMemory32('i', readFromMemory32('i', j_offset), i_offset);
      writeToMemory32('i', tempKey, j_offset);
    }
  }
  else if(key_bits == 64)
  {
    int offset = offset_in_cache_lines*8;
    uint8_t values[8];
    for (j = 0; j < 8; j++)
    {
      values[j] = 1;
    }
    for (i = 0; i < num; i++) // Generate
    {
      int i_offset = i + offset;
      uint64_t temp;
      temp = (uint64_t)values[0];
      temp += ((uint64_t)values[1]) << 8;
      temp += ((uint64_t)values[2]) << 16;
      temp += ((uint64_t)values[3]) << 24;
      temp += ((uint64_t)values[4]) << 32;
      temp += ((uint64_t)values[5]) << 40;
      temp += ((uint64_t)values[6]) << 48;
      temp += ((uint64_t)values[7]) << 56;
      writeToMemory64('i', temp, i_offset); // Key
      for (j = 0; j < 8; j++)
      {
        values[j] += 1;
        if (values[j] <= 14)
          break;
        else
          values[j] = 1;
      }
    }
    for (i = num - 1; i > 0; i--) // Shuffle
    {
      j = RAND_RANGE(i);
      int i_offset = i + offset;
      int j_offset = j + offset;
      uint64_t tempKey = readFromMemory64('i', i_offset);
      writeToMemory64('i', readFromMemory64('i', j_offset), i_offset);
      writeToMemory64('i', tempKey, j_offset);
    }
  }
  else 
    return -1;

  return 0;
}

int FPGAHashingApp::generate_gridreversed_keys(int offset_in_cache_lines, int num)
{
  int i, j;

  if(key_bits == 32)
  {
    int offset = offset_in_cache_lines*16;
    uint8_t values[4];
    for (j = 0; j < 4; j++)
    {
      values[j] = 1;
    }
    for (i = 0; i < num; i++) // Generate
    {
      int i_offset = i + offset;
      uint32_t temp;
      temp = (uint32_t)values[3];
      temp += ((uint32_t)values[2]) << 8;
      temp += ((uint32_t)values[1]) << 16;
      temp += ((uint32_t)values[0]) << 24;
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
    for (i = num - 1; i > 0; i--) // Shuffle
    {
      j = RAND_RANGE(i);
      int i_offset = i + offset;
      int j_offset = j + offset;
      uint32_t tempKey = readFromMemory32('i', i_offset);
      writeToMemory32('i', readFromMemory32('i', j_offset), i_offset);
      writeToMemory32('i', tempKey, j_offset);
    }
  }
  else if(key_bits == 64)
  {
    int offset = offset_in_cache_lines*8;
    uint8_t values[8];
    for (j = 0; j < 8; j++)
    {
      values[j] = 1;
    }
    for (i = 0; i < num; i++) // Generate
    {
      int i_offset = i + offset;
      uint64_t temp;
      temp = (uint64_t)values[7];
      temp += ((uint64_t)values[6]) << 8;
      temp += ((uint64_t)values[5]) << 16;
      temp += ((uint64_t)values[4]) << 24;
      temp += ((uint64_t)values[3]) << 32;
      temp += ((uint64_t)values[2]) << 40;
      temp += ((uint64_t)values[1]) << 48;
      temp += ((uint64_t)values[0]) << 56;
      writeToMemory64('i', temp, i_offset); // Key
      for (j = 0; j < 8; j++)
      {
        values[j] += 1;
        if (values[j] <= 14)
          break;
        else
          values[j] = 1;
      }
    }
    for (i = num - 1; i > 0; i--) // Shuffle
    {
      j = RAND_RANGE(i);
      int i_offset = i + offset;
      int j_offset = j + offset;
      uint64_t tempKey = readFromMemory64('i', i_offset);
      writeToMemory64('i', readFromMemory64('i', j_offset), i_offset);
      writeToMemory64('i', tempKey, j_offset);
    }
  }
  else 
    return -1;

  return 0;
}

btInt FPGAHashingApp::allocateWorkspace()
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
  Manifest.Add(AAL_FACTORY_CREATE_SERVICENAME, "FPGAHashingApp");
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

    // for(i = 0; i < page_count; i++)
    // {
    //   // Set input workspace address
    //   m_AFUService->CSRWrite(CSR_SRC_ADDR, CACHELINE_ALIGNED_ADDR(m_InputPhys[i]));
    //   // Set output workspace address
    //   m_AFUService->CSRWrite(CSR_DST_ADDR, CACHELINE_ALIGNED_ADDR(m_OutputPhys[i]));
    // }

    m_AFUService->CSRWrite(CSR_SRC_ADDR, CACHELINE_ALIGNED_ADDR(m_InputPhys[0]));
    m_AFUService->CSRWrite(CSR_DST_ADDR, CACHELINE_ALIGNED_ADDR(m_OutputPhys[0]));

    // Set the test mode
    m_AFUService->CSRWrite(CSR_CFG, 0);
  }

  return m_Result;
}

btInt FPGAHashingApp::populateTables()
{
	if(0 == m_Result)
	{
		int t, i, j;
		FILE* f;

		f = fopen("random32bit.txt", "r");
		for(i = 0; i < 8; i++)
		{
			for(j = 0; j < 256; j++)
			{
				uint32_t temp;
				fscanf(f, "%x", &temp);
				tables[i][j] = temp;
			}
		}
		fclose(f);
		
		f = fopen("random32bit.txt", "r");
		for(t = 0; t < 2048; t++)
		{
			uint32_t temp;
			uint32_t res = fscanf(f, "%x", &temp);
			for (i = 0; i < 8; i++)
			{
				writeToMemory32('i', temp, 2*i+t*16);
				//uint8_t which_address = t % 256;
				//uint8_t which_table = (t >> 8) & 0x7;
				writeToMemory32('i', t, 2*i+1+t*16);
			}
		}
		fclose(f);

		// Assert Device Reset
		m_AFUService->CSRWrite(CSR_CTL, 0);

		// De-assert Device Reset
		m_AFUService->CSRWrite(CSR_CTL, 1);

		// Set the number of cache lines for the test
	    m_AFUService->CSRWrite(CSR_NUM_LINES, 2048);
	    
	    m_AFUService->CSRWrite(CSR_DUMMY_KEY, 0xEEEEEEEE);
	    
    	doTransaction();

		MSG("Done Populating Tables");

		m_AFUService->CSRWrite(CSR_CTL, 7);
	}

	return m_Result;
}

btInt FPGAHashingApp::hash(char hash_function)
{
	if(0 == m_Result)
	{
		double start = get_time();

		// Set the number of cache lines for the test
    m_AFUService->CSRWrite(CSR_NUM_LINES, num_cache_lines);

    if (hash_function == '1')
			m_AFUService->CSRWrite(CSR_DUMMY_KEY, 0x00000001);
		else if (hash_function == '2')
			m_AFUService->CSRWrite(CSR_DUMMY_KEY, 0x00000002);

		doTransaction();

		double end = get_time();
		double time_difference = end - start;

		printf("Time for HW hashing: %.10f\n", time_difference);

		// int hash_size = 20;
		// int hash_table_size = 1 << hash_size; // hash_size bit hash -> 2^hash_size addresses
		// uint64_t* hash_table = (uint64_t*)malloc(hash_table_size*sizeof(uint64_t));
		// if(hash_table == NULL)
		// {
		// 	printf("Cannot allocate hash_table\n");
		// 	return EXIT_FAILURE;
		// }
		// for(i = 0; i < hash_table_size; i++)
		// {
		// 	hash_table[i] = 0;
		// }

		// uint64_t* keys = (uint64_t*)m_InputVirt;
		// uint64_t* hashes = (uint64_t*)m_OutputVirt;

		// double start, difference;

		// start = get_time();

		// // Start the test
		// m_AFUService->CSRWrite(CSR_CTL, 3);
		// SleepNano(1);

		// for(i = 0; i < cache_lines*8; i++)
		// {
		// 	while(hashes[i] == 0x8080808080808080); // Wait until hash is ready
			
		// 	uint64_t hash = hashes[i];

		// 	if(hash_table[hash] == 0)
		// 	{
		// 		hash_table[hash] = keys[i];
		// 	}
		// 	else
		// 	{
		// 		do
		// 		{
		// 			hash++;
		// 			if(hash == hash_table_size)
		// 				hash = 0;
		// 		}while(hash_table[hash] != 0);
		// 		hash_table[hash] = keys[i];
		// 	}
		// }

		// difference = get_time() - start;
		// printf("Total time: %.10f\n", difference);

		MSG("Done Hashing");

		// Write results to file
		/*f = fopen("results.txt", "w");
		for(i = 0; i < cache_lines; i++)
		{
		int key;
		for(key = 0; key < 8; key++)
		{
		btVirtAddr clSource = m_OutputVirt + i*64 + key*8;
		uint32_t temp;
		temp = *((uint32_t*)clSource);
		fprintf(f, "%x\n", temp);
		}
		}
		fclose(f);*/

		// f = fopen("results.txt", "w");
		// for(i = 0; i < hash_table_size; i++)
		// {
		// 	fprintf(f, "%x\n", hash_table[i]);
		// }
		// fclose(f);

		// Stop the device
		m_AFUService->CSRWrite(CSR_CTL, 7);
	}

	FILE* f;
	int i;

	f = fopen("HWinputMemory.txt", "w");
	for(i = 0; i < num_keys; i++)
	{
		uint64_t temp = readFromMemory64('i', i);
		uint32_t word1 = (uint32_t)(temp & 0xFFFFFFFF);
		uint32_t word2 = (uint32_t)((temp >> 32) & 0xFFFFFFFF);
		fprintf(f, "%x\t%x\n", word1, word2);
	}
	fclose(f);

	f = fopen("HWoutputMemory.txt", "w");
	for(i = 0; i < num_keys; i++)
	{
		uint64_t temp = readFromMemory64('o', i);
		uint32_t word1 = (uint32_t)(temp & 0xFFFFFFFF);
		uint32_t word2 = (uint32_t)((temp >> 32) & 0xFFFFFFFF);
		fprintf(f, "%x\t%x\n", word1, word2);
	}
	fclose(f);

	return m_Result;
}

void FPGAHashingApp::doTransaction()
{
	// Assert Device Reset
	m_AFUService->CSRWrite(CSR_CTL, 0);

	// De-assert Device Reset
	m_AFUService->CSRWrite(CSR_CTL, 1);

	volatile bt32bitCSR *StatusAddr = (volatile bt32bitCSR *)(m_DSMVirt  + DSM_STATUS_TEST_COMPLETE);

	// Start the test
	m_AFUService->CSRWrite(CSR_CTL, 3);

	// Wait for test completion
	while( 0 == *StatusAddr ){
		SleepNano(1);
	}
	*StatusAddr = 0;
}

btInt FPGAHashingApp::swhash(char hash_function)
{
	int i;

	double start = get_time();
	for(i = 0; i < num_keys; i++)
	{
		// Choose a hash function
		uint32_t hash;
		if (hash_function == 'M')
			hash = MultMSB(readFromMemory64('i', i), 32);
		else if (hash_function == 'm')
			hash = MultLSB(readFromMemory64('i', i), 32);
		else if (hash_function == 't')
			hash = SimpleTab(readFromMemory64('i', i), 32, tables);
		else if (hash_function == 'r')
			hash = Murmur(readFromMemory64('i', i), 32);
		else if (hash_function == 'l')
			hash = LookUp3(readFromMemory64('i', i), 32);
		else if (hash_function == 'c')
			hash = City(readFromMemory64('i', i), 32);
		else if (hash_function == 'x')
			hash = HASH_BIT_MODULO(readFromMemory64('i', i), 0xFFFFFFFF, 0);

		//printf("%x\n", hash);
		writeToMemory64('o', (uint64_t)hash, i+num_keys);
	}
	//fclose(f);
	double end = get_time();
	double time_difference = end - start;

	printf("Time for SW hashing: %.10f\n", time_difference);

	FILE* f;

	f = fopen("SWinputMemory.txt", "w");
	for(i = 0; i < num_keys; i++)
	{
		uint64_t temp = readFromMemory64('i', i);
		uint32_t word1 = (uint32_t)(temp & 0xFFFFFFFF);
		uint32_t word2 = (uint32_t)((temp >> 32) & 0xFFFFFFFF);
		fprintf(f, "%x\t%x\n", word2, word1);
	}
	fclose(f);

	f = fopen("SWoutputMemory.txt", "w");
	char matched = 1;
	for(i = 0; i < num_keys; i++)
	{
		uint64_t tempHW = readFromMemory64('o', i);
		uint64_t temp = readFromMemory64('o', i+num_keys);
		if (temp != tempHW)
			matched = 0;
		uint32_t word1 = (uint32_t)(temp & 0xFFFFFFFF);
		uint32_t word2 = (uint32_t)((temp >> 32) & 0xFFFFFFFF);
		fprintf(f, "%x\t%x\n", word2, word1);
	}
	if (matched == 0)
		printf("SW output did not match HW output\n");
	fclose(f);

	int* probes = (int*)calloc(num_keys, sizeof(int));
  double avg_probes = 0.0;
	int hash_bits = 21;
	int hash_table_size = (1 << hash_bits);
	printf("Hash table size: %d\n", hash_table_size);
	uint64_t* hash_table = (uint64_t*)calloc(hash_table_size, sizeof(uint64_t));
	for(i = 0; i < num_keys; i++)
	{
		uint64_t temp = readFromMemory64('o', i+num_keys) & (hash_table_size-1);
    while(1)
    {
      if (hash_table[temp] == 0)
      {
        hash_table[temp] = 1;
        break;
      }
      else
      {
        hash_table[temp]++;
        temp++;
      }
    }
	}
	f = fopen("HashTable.txt", "w");
	for(i = 0; i < hash_table_size; i++)
	{
		fprintf(f, "Slot %d: %x\n", i, hash_table[i]);
		if (hash_table[i] > 0)
    {
			probes[hash_table[i]] += hash_table[i];
      avg_probes += hash_table[i];
    }
	}
	fclose(f);
	f = fopen("Probes.txt", "w");
	//int sum = 0;
	for(i = 0; i < num_keys; i++)
	{
		//sum += collisions[i];
		fprintf(f, "%d\n", probes[i]);
	}
	fclose(f);
  avg_probes = avg_probes/(double)num_keys;
  printf("Avg probes: %.10f\n", avg_probes);

	// int hash_bits = 21;
	// int hash_table_size = (1 << hash_bits);
	// int* next   = (int*) malloc(sizeof(int) * num_keys);
	// int* bucket = (int*) calloc(hash_table_size, sizeof(int));
	// int* chain_length = (int*) calloc(num_keys, sizeof(int));
	// for(i = 0; i < num_keys;)
	// {
	// 	uint64_t temp = readFromMemory64('o', i+num_keys) & (hash_table_size-1);
	// 	next[i] = bucket[temp];
	// 	bucket[temp] = ++i;
	// }
	// f = fopen("Next", "w");
	// for(i = 0; i < num_keys; i++)
	// {
	// 	fprintf(f, "%d\n", next[i]);
	// }
	// fclose(f);
	// f = fopen("Bucket", "w");
	// for(i = 0; i < hash_table_size; i++)
	// {
	// 	fprintf(f, "%d\n", bucket[i]);
	// }
	// fclose(f);
	// uint64_t chain_sum = 0;
 //  uint64_t max_chain = 0;
	// for(i = 0; i < num_keys; i++)
	// {
	// 	int length = 0;
	// 	uint64_t temp = readFromMemory64('o', i+num_keys) & (hash_table_size-1);
	// 	for(int hit = bucket[temp]; hit > 0; hit = next[hit-1])
	// 	{
	// 		length++;
	// 	}
	// 	chain_length[length]++;
	// 	chain_sum += length;
 //    if (length > max_chain)
 //      max_chain = length;
	// }
	// f = fopen("ChainLenght", "w");
	// for(i = 0; i < num_keys; i++)
	// {
	// 	fprintf(f, "%d\n", chain_length[i]);
	// }
	// fclose(f);
	// double avg_chain_length = (double)chain_sum/(double)num_keys;
	// printf("Avarage chain length: %.5f\n", avg_chain_length);
 //  printf("Max chain length: %d\n", max_chain);

	// free(collisions);
	// free(hash_table);
	// free(next);
	// free(bucket);
	// free(chain_length);
}

// We must implement the IServiceClient interface (IServiceClient.h):

// <begin IServiceClient interface>
void FPGAHashingApp::serviceAllocated(IBase *pServiceBase, TransactionID const &rTranID)
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

void FPGAHashingApp::serviceAllocateFailed(const IEvent &rEvent)
{
	IExceptionTransactionEvent * pExEvent = dynamic_ptr<IExceptionTransactionEvent>(iidExTranEvent, rEvent);
	ERR("Failed to allocate a Service");
	ERR(pExEvent->Description());
	++m_Result;                     // Remember the error

	m_Sem.Post(1);
}

void FPGAHashingApp::serviceFreed(TransactionID const &rTranID)
{
	MSG("Service Freed");
	// Unblock Main()
	m_Sem.Post(1);
}

// <ICCIClient>
void FPGAHashingApp::OnWorkspaceAllocated(TransactionID const &TranID,
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
		MSG("Got Input Workspace");
		printf("Input Virt:%x, Phys:%x, Size:%d\n", m_InputVirt[index], m_InputPhys[index], m_InputSize[index]);
		m_Sem.Post(1);
	}
	else if(TranID.ID() >= page_count+1 && TranID.ID() <= 2*page_count)
	{
		int index = TranID.ID()-(page_count+1);
		m_OutputVirt[index] = WkspcVirt;
		m_OutputPhys[index] = WkspcPhys;
		m_OutputSize[index] = WkspcSize;
		MSG("Got Output Workspace");
		printf("Output Virt:%x, Phys:%x, Size:%d\n", m_OutputVirt[index], m_OutputPhys[index], m_OutputSize[index]);
		m_Sem.Post(1);
	}
	else
	{
		++m_Result;
		ERR("Invalid workspace type: " << TranID.ID());
	}
}

void FPGAHashingApp::OnWorkspaceAllocateFailed(const IEvent &rEvent)
{
	IExceptionTransactionEvent * pExEvent = dynamic_ptr<IExceptionTransactionEvent>(iidExTranEvent, rEvent);
	ERR("OnWorkspaceAllocateFailed");
	ERR(pExEvent->Description());

	++m_Result;                     // Remember the error
	m_Sem.Post(1);
}

void FPGAHashingApp::OnWorkspaceFreed(TransactionID const &TranID)
{
	MSG("OnWorkspaceFreed");
	m_Sem.Post(1);
}

void FPGAHashingApp::OnWorkspaceFreeFailed(const IEvent &rEvent)
{
	IExceptionTransactionEvent * pExEvent = dynamic_ptr<IExceptionTransactionEvent>(iidExTranEvent, rEvent);
	ERR("OnWorkspaceAllocateFailed");
	ERR(pExEvent->Description());
	++m_Result;                     // Remember the error
	m_Sem.Post(1);
}


void FPGAHashingApp::serviceEvent(const IEvent &rEvent)
{
	ERR("unexpected event 0x" << hex << rEvent.SubClassID());
}
// <end IServiceClient interface>

/// @} group FPGAHashing

int main(int argc, char *argv[])
{
	// if(argc < 2 || argc > 3)
	// {
	// 	ERR("Provide either: populate tables (p) or key_space (r, l, g) and hash_function (m, t, r, l, h)");
	// 	exit(1);
	// }

	int key_bits = 64;
	int num_keys = 16384;
  int page_size_in_cache_lines = 65536; 
  int Result = 0;

	RuntimeClient  runtimeClient;
	FPGAHashingApp theApp(&runtimeClient, key_bits, num_keys, page_size_in_cache_lines);
	if(!runtimeClient.isOK()){
		ERR("Runtime Failed to Start");
		exit(1);
	}

	while(1)
	{
		std::string input;

		std::cout << "Enter an option:\n";
		std::cin >> input;

		if (input.compare("populate") == 0)
		{
			Result = theApp.populateTables();
			std::cout << "Tabulation tables populated both in SW and HW\n";
		}
		else if (input.compare("random") == 0)
		{
			theApp.generate_random_keys(0, num_keys);
			std::cout << "Random keys generated\n";
		}
		else if (input.compare("linear") == 0)
		{
			theApp.generate_linear_keys(0, num_keys);
			std::cout << "Linear keys generated\n";
		}
		else if (input.compare("linearo") == 0)
		{
			theApp.generate_linearoffset_keys(0, num_keys);
			std::cout << "Offsetted linear keys generated\n";
		}
		else if (input.compare("grid") == 0)
		{
			theApp.generate_grid_keys(0, num_keys);
			std::cout << "Grid keys generated\n";
		}
		else if (input.compare("gridr") == 0)
		{
			theApp.generate_gridreversed_keys(0, num_keys);
			std::cout << "Grid reversed keys generated\n";
		}
		else if (input.compare("swmod") == 0)
		{
			Result = theApp.swhash('x');
			std::cout << "Modulo in SW happened\n";
		}
		else if (input.compare("swmult") == 0)
		{
			Result = theApp.swhash('M');
			std::cout << "MultShiftMSB in SW happened\n";
		}
		else if (input.compare("swlmult") == 0)
		{
			Result = theApp.swhash('m');
			std::cout << "MultShiftLSB in SW happened\n";
		}
		else if(input.compare("swtab") == 0)
		{
			Result = theApp.swhash('t');
			std::cout << "SimpleTab in SW happened\n";
		}
		else if(input.compare("swmur") == 0)
		{
			Result = theApp.swhash('r');
			std::cout << "Murmur in SW happened\n";
		}
		else if(input.compare("swlook") == 0)
		{
			Result = theApp.swhash('l');
			std::cout << "LookUp3 in SW happened\n";
		}
		else if(input.compare("swcity") == 0)
		{
			Result = theApp.swhash('c');
			std::cout << "City in SW happened\n";
		}
		else if(input.compare("hwmur") == 0)
		{
			Result = theApp.hash('1');
			std::cout << "Murmur in HW happened\n";
		}
		else if(input.compare("hwtab") == 0)
		{
			Result = theApp.hash('2');
			std::cout << "SimpleTab in HW happened\n";
		}
		else if(input.compare("exit") == 0)
			break;
	}
	

	MSG("Done");
	return 0;
}