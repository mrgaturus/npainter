// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#include "image.h"

void mipmap_pack8(image_combine_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  unsigned char *src_x, *src_y;
  dst_y = co->dst.buffer;
  src_y = co->src.buffer;

  int w, h, s_src, s_dst;
  // Load Region
  w = co->src.w;
  h = co->src.h;
  // Load Strides
  s_src = co->src.stride;
  s_dst = co->dst.stride;

  // Source Pixel Values
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    count = w;

    // Pack Source to Destination
    while (count > 0) {
      xmm0 = _mm_load_si128((__m128i*) src_x);
      xmm1 = _mm_load_si128((__m128i*) src_x + 1);
      xmm2 = _mm_load_si128((__m128i*) src_x + 2);
      xmm3 = _mm_load_si128((__m128i*) src_x + 3);
      xmm4 = _mm_load_si128((__m128i*) src_x + 4);
      xmm5 = _mm_load_si128((__m128i*) src_x + 5);
      xmm6 = _mm_load_si128((__m128i*) src_x + 6);
      xmm7 = _mm_load_si128((__m128i*) src_x + 7);

      // Downscale to 8 bit
      xmm0 = _mm_srli_epi16(xmm0, 8);
      xmm1 = _mm_srli_epi16(xmm1, 8);
      xmm2 = _mm_srli_epi16(xmm2, 8);
      xmm3 = _mm_srli_epi16(xmm3, 8);
      xmm4 = _mm_srli_epi16(xmm4, 8);
      xmm5 = _mm_srli_epi16(xmm5, 8);
      xmm6 = _mm_srli_epi16(xmm6, 8);
      xmm7 = _mm_srli_epi16(xmm7, 8);
      // Pack to 8 bit Pixels
      xmm0 = _mm_packus_epi16(xmm0, xmm1);
      xmm1 = _mm_packus_epi16(xmm2, xmm3);
      xmm2 = _mm_packus_epi16(xmm4, xmm5);
      xmm3 = _mm_packus_epi16(xmm6, xmm7);

      // Store 16 Pixels to Destination
      _mm_stream_si128((__m128i*) dst_x, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 1, xmm1);
      _mm_stream_si128((__m128i*) dst_x + 2, xmm2);
      _mm_stream_si128((__m128i*) dst_x + 3, xmm3);

      // Step Buffers
      src_x += 128;
      dst_x += 64;
      // Step Pixels
      count -= 16;
    }

    // Step Y Buffers
    dst_y += s_dst;
    src_y += s_src;
  }
}

void mipmap_pack2(image_combine_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  unsigned char *src_x, *src_y;
  dst_y = co->dst.buffer;
  src_y = co->src.buffer;

  int w, h, s_src, s_dst;
  // Load Region
  w = co->src.w;
  h = co->src.h;
  // Load Strides
  s_src = co->src.stride;
  s_dst = co->dst.stride;

  // Source Pixel Values
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;
  const __m128i gray = _mm_set_epi32(0, 3736, 19234, 9798);
  const __m128i ones = _mm_cmpeq_epi32(gray, gray);
  const __m128i zeros = _mm_setzero_si128();

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    count = w;

    // Copy Source to Destination
    while (count > 0) {
      xmm4 = _mm_load_si128((__m128i*) src_x);
      xmm5 = _mm_load_si128((__m128i*) src_x + 1);
      xmm6 = _mm_load_si128((__m128i*) src_x + 2);
      xmm7 = _mm_load_si128((__m128i*) src_x + 3);

      // Unpack 16-bit to 32-bit
      xmm0 = _mm_unpacklo_epi16(xmm4, zeros);
      xmm1 = _mm_unpackhi_epi16(xmm4, zeros);
      xmm2 = _mm_unpacklo_epi16(xmm5, zeros);
      xmm3 = _mm_unpackhi_epi16(xmm5, zeros);
      xmm4 = _mm_unpacklo_epi16(xmm6, zeros);
      xmm5 = _mm_unpackhi_epi16(xmm6, zeros);
      xmm6 = _mm_unpacklo_epi16(xmm7, zeros);
      xmm7 = _mm_unpackhi_epi16(xmm7, zeros);

      // Convert to Grayscale
      xmm0 = _mm_mullo_epi32(xmm0, gray);
      xmm1 = _mm_mullo_epi32(xmm1, gray);
      xmm2 = _mm_mullo_epi32(xmm2, gray);
      xmm3 = _mm_mullo_epi32(xmm3, gray);
      xmm4 = _mm_mullo_epi32(xmm4, gray);
      xmm5 = _mm_mullo_epi32(xmm5, gray);
      xmm6 = _mm_mullo_epi32(xmm6, gray);
      xmm7 = _mm_mullo_epi32(xmm7, gray);
      // Convert to Grayscale: Pack 1
      xmm0 = _mm_hadd_epi32(xmm0, xmm1);
      xmm1 = _mm_hadd_epi32(xmm2, xmm3);
      xmm2 = _mm_hadd_epi32(xmm4, xmm5);
      xmm3 = _mm_hadd_epi32(xmm6, xmm7);
      // Convert to Grayscale: Pack 2
      xmm0 = _mm_hadd_epi32(xmm0, xmm1);
      xmm1 = _mm_hadd_epi32(xmm2, xmm3);
      xmm0 = _mm_srli_epi32(xmm0, 15);
      xmm1 = _mm_srli_epi32(xmm1, 15);
      // Convert to Grayscale: Pack Store
      xmm0 = _mm_packus_epi32(xmm0, xmm1);
      _mm_stream_si128((__m128i*) dst_x, xmm0);

      // Step Buffers
      src_x += 64;
      dst_x += 16;
      // Step Pixels
      count -= 8;
    }

    // Step Y Buffers
    dst_y += s_dst;
    src_y += s_src;
  }
}

// ---------------------
// Mipmap Tile Reduction
// ---------------------

void mipmap_reduce16(image_combine_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  unsigned char *src_x0, *src_x1, *src_y;
  dst_y = co->dst.buffer;
  src_y = co->src.buffer;

  int w, h, s_src, s_dst;
  // Load Region
  w = co->dst.w;
  h = co->dst.h;
  // Load Strides
  s_src = co->src.stride;
  s_dst = co->dst.stride;

  // Source Pixel Values
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    // Source Pixels
    src_x0 = src_y;
    src_x1 = src_y + s_src;
    // Lane Count
    count = w;

    // Copy Source bytes to Destination
    while (count > 0) {
      // Upper Source Pixels
      xmm0 = _mm_load_si128((__m128i*) src_x0);
      xmm1 = _mm_load_si128((__m128i*) src_x0 + 1);
      xmm2 = _mm_load_si128((__m128i*) src_x0 + 2);
      xmm3 = _mm_load_si128((__m128i*) src_x0 + 3);
      // Bottom Source Pixels
      xmm4 = _mm_load_si128((__m128i*) src_x1);
      xmm5 = _mm_load_si128((__m128i*) src_x1 + 1);
      xmm6 = _mm_load_si128((__m128i*) src_x1 + 2);
      xmm7 = _mm_load_si128((__m128i*) src_x1 + 3);

      // Average 8 Pixels Vertically
      xmm0 = _mm_avg_epu16(xmm0, xmm4);
      xmm1 = _mm_avg_epu16(xmm1, xmm5);
      xmm2 = _mm_avg_epu16(xmm2, xmm6);
      xmm3 = _mm_avg_epu16(xmm3, xmm7);
      // Average 4 Pixels Horizontally
      xmm4 = _mm_unpacklo_epi64(xmm0, xmm1);
      xmm5 = _mm_unpacklo_epi64(xmm2, xmm3);
      xmm6 = _mm_unpackhi_epi64(xmm0, xmm1);
      xmm7 = _mm_unpackhi_epi64(xmm2, xmm3);
      xmm0 = _mm_avg_epu16(xmm4, xmm6);
      xmm1 = _mm_avg_epu16(xmm5, xmm7);

      // Store 4 Pixels
      if (__builtin_expect(count >= 4, 1)) {
        _mm_stream_si128((__m128i*) dst_x, xmm0);
        _mm_stream_si128((__m128i*) dst_x + 1, xmm1);

        // Step Buffers
        src_x0 += 64;
        src_x1 += 64;
        dst_x += 32;
        // Step 4 Pixels
        count -= 4;
        continue;
      }

      // Store 2 Pixels
      if (count >= 2) {
        _mm_stream_si128((__m128i*) dst_x, xmm0);
        xmm0 = xmm1;
        // Step 2 Pixels
        dst_x += 16;
        count -= 2;
      }

      // Store 1 Pixel
      if (count == 1) {
        _mm_storel_epi64((__m128i*) dst_x, xmm0);
        // No More Pixels
        count--;
      }
    }

    // Step Y Buffers
    src_y += s_src << 1;
    dst_y += s_dst;
  }
}

void mipmap_reduce8(image_combine_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  unsigned char *src_x0, *src_x1, *src_y;
  dst_y = co->dst.buffer;
  src_y = co->src.buffer;

  int w, h, s_src, s_dst;
  // Load Region
  w = co->dst.w;
  h = co->dst.h;
  // Load Strides
  s_src = co->src.stride;
  s_dst = co->dst.stride;

  // Source Pixel Values
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    // Source Pixels
    src_x0 = src_y;
    src_x1 = src_y + s_src;
    // Lane Count
    count = w;

    // Reduce Source Bytes to Destination
    while (count > 0) {
      // Upper Source Pixels
      xmm0 = _mm_load_si128((__m128i*) src_x0);
      xmm1 = _mm_load_si128((__m128i*) src_x0 + 1);
      xmm2 = _mm_load_si128((__m128i*) src_x0 + 2);
      xmm3 = _mm_load_si128((__m128i*) src_x0 + 3);
      // Bottom Source Pixels
      xmm4 = _mm_load_si128((__m128i*) src_x1);
      xmm5 = _mm_load_si128((__m128i*) src_x1 + 1);
      xmm6 = _mm_load_si128((__m128i*) src_x1 + 2);
      xmm7 = _mm_load_si128((__m128i*) src_x1 + 3);

      // Average 16 Pixels Vertically
      xmm0 = _mm_avg_epu8(xmm0, xmm4);
      xmm1 = _mm_avg_epu8(xmm1, xmm5);
      xmm2 = _mm_avg_epu8(xmm2, xmm6);
      xmm3 = _mm_avg_epu8(xmm3, xmm7);

      // Interleave 8 Pixels Horizontally: Pass 1
      xmm4 = _mm_unpacklo_epi32(xmm0, xmm1); 
      xmm5 = _mm_unpacklo_epi32(xmm2, xmm3);
      xmm6 = _mm_unpackhi_epi32(xmm0, xmm1);
      xmm7 = _mm_unpackhi_epi32(xmm2, xmm3);
      // Interleave 8 Pixels Horizontally: Pass 2
      xmm0 = _mm_unpacklo_epi32(xmm4, xmm6);
      xmm1 = _mm_unpacklo_epi32(xmm5, xmm7);
      xmm2 = _mm_unpackhi_epi32(xmm4, xmm6);
      xmm3 = _mm_unpackhi_epi32(xmm5, xmm7);
      // Average 8 Pixels Horizontally
      xmm0 = _mm_avg_epu8(xmm0, xmm2);
      xmm1 = _mm_avg_epu8(xmm1, xmm3);

      // Store 8 Pixels
      if (__builtin_expect(count >= 8, 1)) {
        _mm_stream_si128((__m128i*) dst_x, xmm0);
        _mm_stream_si128((__m128i*) dst_x + 1, xmm1);

        // Step Buffers
        src_x0 += 64;
        src_x1 += 64;
        dst_x += 32;
        // Step 8 Pixels
        count -= 8;
        continue;
      }

      // Store 4 Pixels
      if (count >= 4) {
        _mm_stream_si128((__m128i*) dst_x, xmm0);
        xmm0 = xmm1;
        // Step 2 Pixels
        dst_x += 16;
        count -= 4;
      }

      // Store 2 Pixels
      if (count >= 2) {
        _mm_storel_epi64((__m128i*) dst_x, xmm0);
        _mm_srli_si128(xmm0, 8);
        // No More Pixels
        dst_x += 8;
        count -= 2;
      }

      // Store 1 Pixel
      if (count == 1) {
        _mm_storeu_si32((__m128i*) dst_x, xmm0);
        count--;
      }
    }

    // Step Y Buffers
    src_y += s_src << 1;
    dst_y += s_dst;
  }
}

void mipmap_reduce2(image_combine_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  unsigned char *src_x0, *src_x1, *src_y;
  dst_y = co->dst.buffer;
  src_y = co->src.buffer;

  int w, h, s_src, s_dst;
  // Load Region
  w = co->dst.w;
  h = co->dst.h;
  // Load Strides
  s_src = co->src.stride;
  s_dst = co->dst.stride;

  // Source Pixel Values
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    // Source Pixels
    src_x0 = src_y;
    src_x1 = src_y + s_src;
    // Lane Count
    count = w;

    // Reduce Source Bytes to Destination
    while (count > 0) {
      // Upper Source Pixels
      xmm0 = _mm_load_si128((__m128i*) src_x0);
      xmm1 = _mm_load_si128((__m128i*) src_x0 + 1);
      xmm2 = _mm_load_si128((__m128i*) src_x0 + 2);
      xmm3 = _mm_load_si128((__m128i*) src_x0 + 3);
      // Bottom Source Pixels
      xmm4 = _mm_load_si128((__m128i*) src_x1);
      xmm5 = _mm_load_si128((__m128i*) src_x1 + 1);
      xmm6 = _mm_load_si128((__m128i*) src_x1 + 2);
      xmm7 = _mm_load_si128((__m128i*) src_x1 + 3);

      // Average 32 Pixels Vertically
      xmm0 = _mm_avg_epu16(xmm0, xmm4);
      xmm1 = _mm_avg_epu16(xmm1, xmm5);
      xmm2 = _mm_avg_epu16(xmm2, xmm6);
      xmm3 = _mm_avg_epu16(xmm3, xmm7);

      // Interleave 16 Pixels Horizontally: Pass 1
      xmm4 = _mm_unpacklo_epi16(xmm0, xmm1);
      xmm5 = _mm_unpacklo_epi16(xmm2, xmm3);
      xmm6 = _mm_unpackhi_epi16(xmm0, xmm1);
      xmm7 = _mm_unpackhi_epi16(xmm2, xmm3);
      // Interleave 16 Pixels Horizontally: Pass 2
      xmm0 = _mm_unpacklo_epi16(xmm4, xmm6);
      xmm1 = _mm_unpacklo_epi16(xmm5, xmm7);
      xmm2 = _mm_unpackhi_epi16(xmm4, xmm6);
      xmm3 = _mm_unpackhi_epi16(xmm5, xmm7);
      // Interleave 16 Pixels Horizontally: Pass 3
      xmm4 = _mm_unpacklo_epi16(xmm0, xmm2);
      xmm5 = _mm_unpacklo_epi16(xmm1, xmm3);
      xmm6 = _mm_unpackhi_epi16(xmm0, xmm2);
      xmm7 = _mm_unpackhi_epi16(xmm1, xmm3);
      // Average 16 Pixels Horizontally
      xmm0 = _mm_avg_epu16(xmm4, xmm6);
      xmm1 = _mm_avg_epu16(xmm5, xmm7);

      // Store 16 Mask Pixels
      if (__builtin_expect(count >= 16, 1)) {
        _mm_stream_si128((__m128i*) dst_x, xmm0);
        _mm_stream_si128((__m128i*) dst_x + 1, xmm1);

        // Step Buffers
        src_x0 += 64;
        src_x1 += 64;
        dst_x += 32;
        // Step 16 Pixels
        count -= 16;
        continue;
      }

      // Store 8 Mask Pixels
      if (count >= 8) {
        _mm_stream_si128((__m128i*) dst_x, xmm0);
        xmm0 = xmm1;
        // Step 2 Pixels
        dst_x += 16;
        count -= 8;
      }

      // Store 4 Mask Pixels
      if (count >= 4) {
        _mm_storel_epi64((__m128i*) dst_x, xmm0);
        _mm_srli_si128(xmm0, 8);
        // Step 4 Pixels
        dst_x += 8;
        count -= 4;
      }

      // Store 2 Mask Pixels
      if (count >= 2) {
        _mm_storeu_si32((__m128i*) dst_x, xmm0);
        _mm_srli_si128(xmm0, 4);
        // Step 2 Pixels
        dst_x += 4;
        count -= 2;
      }

      // Store 1 Mask Pixel
      if (count == 1) {
        _mm_storeu_si16((__m128i*) dst_x, xmm0);
        count--;
      }
    }

    // Step Y Buffers
    src_y += s_src << 1;
    dst_y += s_dst;
  }
}
