#ifndef EVERPLAY_LZMA_H
#define EVERPLAY_LZMA_H

#include <stddef.h>
#include <stdint.h>

/* A streaming raw LZMA1 or LZMA2 decoder (as Inno Setup stores them) for Swift. */
typedef struct EverPlayLzma EverPlayLzma;

/* LZMA1 with its 5 property bytes, or LZMA2 with its 1 property byte. NULL on bad properties. */
EverPlayLzma *everplay_lzma1_open(const uint8_t properties[5]);
EverPlayLzma *everplay_lzma2_open(uint8_t property);

/* Decodes from input into output; both sizes are updated to the bytes used.
   Returns 0 to continue, 1 at the end of the stream, -1 on corrupt data. */
int everplay_lzma_decode(EverPlayLzma *decoder, const uint8_t *input, size_t *input_size,
                         uint8_t *output, size_t *output_size);

void everplay_lzma_close(EverPlayLzma *decoder);

#endif
