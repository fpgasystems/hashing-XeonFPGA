#include <aalsdk/AAL.h>
#include <aalsdk/xlRuntime.h>
#include <aalsdk/AALLoggerExtern.h> // Logger

#include <aalsdk/service/ICCIAFU.h>
#include <aalsdk/service/ICCIClient.h>

#include "RuntimeClient.h"

// Print/don't print the event ID's entered in the event handlers.
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
#define NEXT_POW_2(V)                           \
    do {                                        \
        V--;                                    \
        V |= V >> 1;                            \
        V |= V >> 2;                            \
        V |= V >> 4;                            \
        V |= V >> 8;                            \
        V |= V >> 16;                           \
        V++;                                    \
    } while(0)
#define HASH_BIT_MODULO(K, MASK, NBITS) (((K) & MASK) >> NBITS)

#define MAX_page_count           2048

#define DSM_SIZE                 MB(4)
#define CSR_AFU_DSM_BASEH        0x1a04
#define CSR_SRC_ADDR             0x1a20
#define CSR_DST_ADDR             0x1a24
#define CSR_CTL                  0x1a2c
#define CSR_CFG                  0x1a34
#define CSR_CIPUCTL              0x280
#define CSR_NUM_LINES            0x1a28
#define CSR_EXP_NUM_LINES        0x1a94
#define DSM_STATUS_TEST_COMPLETE 0x40
#define CSR_AFU_DSM_BASEL        0x1a00
#define CSR_AFU_DSM_BASEH        0x1a04
#define CSR_ADDR_RESET			 0x1a80
#define CSR_READ_OFFSET          0x1a84
#define CSR_WRITE_OFFSET         0x1a88
#define CSR_DUMMY_KEY			 0x1a8c
#define CSR_RADIX_BITS			 0x1a90

double get_time()
{
    struct timeval t;
    gettimeofday(&t, NULL);
    return t.tv_sec + t.tv_usec*1e-6;
}

struct relation_t {
  uint32_t baseTuples;
  uint32_t numTuples;
};

/// @brief   Define our Service client class so that we can receive Service-related notifications from the AAL Runtime.
///          The Service Client contains the application logic.
///
/// When we request an AFU (Service) from AAL, the request will be fulfilled by calling into this interface.
class FPGAHashJoinApp: public CAASBase, public IServiceClient, public ICCIClient
{
public:
    FPGAHashJoinApp(RuntimeClient * rtc, int _key_bits, int _R_num_tuples, int _S_num_tuples, int _num_radix_bits, int _page_size_in_cache_lines, int _padding_size_divider, int _is_column_store);
    ~FPGAHashJoinApp();

    int writeToMemory32(char inOrOut, uint32_t dat32, uint32_t address32);
    uint32_t readFromMemory32(char inOrOut, uint32_t address32);
    int writeToMemory64(char inOrOut, uint64_t dat64, uint32_t address64);
    uint64_t readFromMemory64(char inOrOut, uint32_t address64);

    int generate_linear_key_relationCS(int offset_in_cache_lines, int num_tuples);
    int generate_random_key_relationCS(int offset_in_cache_lines, int num_tuples);
    int generate_grid_key_relationCS(int offset_in_cache_lines, int num_tuples);

    int generate_linear_key_relationRS(int offset_in_cache_lines, int num_tuples);
    int generate_random_key_relationRS(int offset_in_cache_lines, int num_tuples);
    int generate_grid_key_relationRS(int offset_in_cache_lines, int num_tuples);

    btInt allocateWorkspace();
    btInt partition();
    void doTransaction();
    uint32_t join(int num_threads);
    uint32_t bucket_chaining_join(const relation_t * const R, const relation_t * const S);

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

  static const int page_count = 36;
  int key_bits;
  int R_num_tuples;
  int S_num_tuples;
  int num_radix_bits;
  int fan_out;
  int page_size_in_cache_lines;
  int R_cache_lines;
  int S_cache_lines;
  int reserved_cl_for_counting;
  int R_partition_size_in_cache_lines;
  int S_partition_size_in_cache_lines;
  int padding_size_divider;
  int is_column_store;

protected:
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

struct thread_data {
  uint32_t tid;
  uint32_t baseHistogramR;
  uint32_t baseHistogramS;
  uint32_t basePartitionedR;
  uint32_t basePartitionedS;
  uint32_t num_partitions_to_process;
  uint32_t result;
  FPGAHashJoinApp* app; 
};