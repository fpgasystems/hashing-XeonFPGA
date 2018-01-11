#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

uint32_t MultMSB(uint64_t key, uint64_t hash_size);
uint32_t MultLSB(uint64_t key, uint64_t hash_size);
uint32_t SimpleTab(uint64_t key, uint64_t hash_size, uint32_t** tables);
uint32_t Murmur(uint64_t key, uint64_t hash_size);
uint32_t LookUp3(uint64_t key, uint64_t hash_size);
uint32_t City(uint64_t key, uint64_t hash_size);