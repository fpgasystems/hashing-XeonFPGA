#include "hash_functions.h"
#include "lookup3.h"
#include "city.h"

uint32_t MultMSB(uint64_t key, uint64_t hash_size)
{
	uint64_t magic = 21742483383879;
	uint64_t temp = (key*magic);
	temp = (temp >> (64 - hash_size)) & 0xFFFFFFFF;
	return (uint32_t)temp;
}

uint32_t MultLSB(uint64_t key, uint64_t hash_size)
{
	uint64_t magic = 21742483383879;
	uint64_t temp = (key*magic);
	temp = temp & ((1 << hash_size)-1);
	return (uint32_t)temp;
}

uint32_t SimpleTab(uint64_t key, uint64_t hash_size, uint32_t** tables)
{
	uint32_t mask = 255;
	uint32_t value[8];
	uint32_t result = 0;

	uint8_t temp;
	int i;
	for(i = 0; i < 8; i++)
	{
		temp = (uint8_t)(mask & (key >> 8*i));
		value[i] = tables[i][temp];
	}
	for(i = 0; i < 8; i++)
	{
		result = result ^ value[i];
	}

	return result;
}

uint32_t Murmur(uint64_t key, uint64_t hash_size)
{
	key ^= key >> 33;
	key *= 0xff51afd7ed558ccd;
	key ^= key >> 33;
	key *= 0xc4ceb9fe1a85ec53;
	key ^= key >> 33;
	//key = key >> (64 - hash_size);
	key = 0xFFFFFFFF & key;
	return (uint32_t)key;
}

uint32_t LookUp3(uint64_t key, uint64_t hash_size)
{
	uint32_t magic = 127;//2147483647;
	uint32_t temp = hashlittle(&key, 8, magic);
	temp = (temp >> (32 - hash_size)) & 0xFFFFFFFF;
	//printf("LookUp3 key: %x%x, hash: %x\n", (uint32_t)(key >> 32), (uint32_t)key, temp);
	return temp;
}

uint32_t City(uint64_t key, uint64_t hash_size)
{
	uint64_t temp = CityHash64((char*)&key, 8);
	uint32_t temp2 = (temp >> (64 - hash_size)) & 0xFFFFFFFF;
	return temp2;
}