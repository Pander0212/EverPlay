#include <stdlib.h>
#include "EverPlayLzma.h"
#include "Lzma2Dec.h"

static void *everplay_alloc(ISzAllocPtr p, size_t size) { (void) p; return malloc(size); }
static void everplay_free(ISzAllocPtr p, void *address) { (void) p; free(address); }
static const ISzAlloc everplay_allocator = { everplay_alloc, everplay_free };

struct EverPlayLzma {
    int lzma2;
    CLzmaDec lzma;
    CLzma2Dec lzma2_decoder;
};

EverPlayLzma *everplay_lzma1_open(const uint8_t properties[5]) {
    EverPlayLzma *decoder = calloc(1, sizeof *decoder);
    if (!decoder) return NULL;
    LzmaDec_Construct(&decoder->lzma);
    if (LzmaDec_Allocate(&decoder->lzma, properties, LZMA_PROPS_SIZE, &everplay_allocator) != SZ_OK) {
        free(decoder);
        return NULL;
    }
    LzmaDec_Init(&decoder->lzma);
    return decoder;
}

EverPlayLzma *everplay_lzma2_open(uint8_t property) {
    EverPlayLzma *decoder = calloc(1, sizeof *decoder);
    if (!decoder) return NULL;
    decoder->lzma2 = 1;
    Lzma2Dec_CONSTRUCT(&decoder->lzma2_decoder);
    if (Lzma2Dec_Allocate(&decoder->lzma2_decoder, property, &everplay_allocator) != SZ_OK) {
        free(decoder);
        return NULL;
    }
    Lzma2Dec_Init(&decoder->lzma2_decoder);
    return decoder;
}

int everplay_lzma_decode(EverPlayLzma *decoder, const uint8_t *input, size_t *input_size,
                         uint8_t *output, size_t *output_size) {
    ELzmaStatus status;
    SRes result = decoder->lzma2
        ? Lzma2Dec_DecodeToBuf(&decoder->lzma2_decoder, output, output_size, input, input_size, LZMA_FINISH_ANY, &status)
        : LzmaDec_DecodeToBuf(&decoder->lzma, output, output_size, input, input_size, LZMA_FINISH_ANY, &status);
    if (result != SZ_OK) return -1;
    return status == LZMA_STATUS_FINISHED_WITH_MARK ? 1 : 0;
}

void everplay_lzma_close(EverPlayLzma *decoder) {
    if (!decoder) return;
    if (decoder->lzma2) Lzma2Dec_Free(&decoder->lzma2_decoder, &everplay_allocator);
    else LzmaDec_Free(&decoder->lzma, &everplay_allocator);
    free(decoder);
}
