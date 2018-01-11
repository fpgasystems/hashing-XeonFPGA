#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

uint32_t hashword(
const uint32_t *k,                   /* the key, an array of uint32_t values */
size_t          length,               /* the length of the key, in uint32_ts */
uint32_t        initval);

void hashword2 (
const uint32_t *k,                   /* the key, an array of uint32_t values */
size_t          length,               /* the length of the key, in uint32_ts */
uint32_t       *pc,                      /* IN: seed OUT: primary hash value */
uint32_t       *pb);

uint32_t hashlittle( const void *key, size_t length, uint32_t initval);

void hashlittle2(
  const void *key,       /* the key to hash */
  size_t      length,    /* length of the key */
  uint32_t   *pc,        /* IN: primary initval, OUT: primary hash */
  uint32_t   *pb);

uint32_t hashbig( const void *key, size_t length, uint32_t initval);

void driver1();
void driver2();
void driver3();
void driver4();
void driver5();
