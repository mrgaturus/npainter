// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2024 Cristian Camilo Ruiz <mrgaturus>
#include "image.h"

// ----------------------
// Proxy Streaming Unpack
// ----------------------

void proxy_stream16(image_combine_t* co) {
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

    // Copy Source to Destination
    while (count > 0) {
      xmm0 = _mm_load_si128((__m128i*) src_x);
      xmm1 = _mm_load_si128((__m128i*) src_x + 1);
      xmm2 = _mm_load_si128((__m128i*) src_x + 2);
      xmm3 = _mm_load_si128((__m128i*) src_x + 3);
      xmm4 = _mm_load_si128((__m128i*) src_x + 4);
      xmm5 = _mm_load_si128((__m128i*) src_x + 5);
      xmm6 = _mm_load_si128((__m128i*) src_x + 6);
      xmm7 = _mm_load_si128((__m128i*) src_x + 7);

      // Copy 16 Pixels to Destination
      _mm_stream_si128((__m128i*) dst_x, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 1, xmm1);
      _mm_stream_si128((__m128i*) dst_x + 2, xmm2);
      _mm_stream_si128((__m128i*) dst_x + 3, xmm3);
      _mm_stream_si128((__m128i*) dst_x + 4, xmm4);
      _mm_stream_si128((__m128i*) dst_x + 5, xmm5);
      _mm_stream_si128((__m128i*) dst_x + 6, xmm6);
      _mm_stream_si128((__m128i*) dst_x + 7, xmm7);

      // Step Buffers
      src_x += 128;
      dst_x += 128;
      // Step Pixels
      count -= 16;
    }

    // Step Y Buffers
    dst_y += s_dst;
    src_y += s_src;
  }
}

void proxy_stream8(image_combine_t* co) {
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

    // Copy Source to Destination
    while (count > 0) {
      xmm0 = _mm_load_si128((__m128i*) src_x);
      xmm1 = _mm_load_si128((__m128i*) src_x + 1);
      xmm2 = _mm_load_si128((__m128i*) src_x + 2);
      xmm3 = _mm_load_si128((__m128i*) src_x + 3);

      // Unpack 8 Bit to 16 bit
      xmm7 = _mm_unpackhi_epi8(xmm3, xmm3);
      xmm6 = _mm_unpacklo_epi8(xmm3, xmm3);
      xmm5 = _mm_unpackhi_epi8(xmm2, xmm2);
      xmm4 = _mm_unpacklo_epi8(xmm2, xmm2);
      xmm3 = _mm_unpackhi_epi8(xmm1, xmm1);
      xmm2 = _mm_unpacklo_epi8(xmm1, xmm1);
      xmm1 = _mm_unpackhi_epi8(xmm0, xmm0);
      xmm0 = _mm_unpacklo_epi8(xmm0, xmm0);

      // Copy 16 Pixels to Destination
      _mm_stream_si128((__m128i*) dst_x + 0, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 1, xmm1);
      _mm_stream_si128((__m128i*) dst_x + 2, xmm2);
      _mm_stream_si128((__m128i*) dst_x + 3, xmm3);
      _mm_stream_si128((__m128i*) dst_x + 4, xmm4);
      _mm_stream_si128((__m128i*) dst_x + 5, xmm5);
      _mm_stream_si128((__m128i*) dst_x + 6, xmm6);
      _mm_stream_si128((__m128i*) dst_x + 7, xmm7);

      // Step Buffers
      src_x += 64;
      dst_x += 128;
      // Step Pixels
      count -= 16;
    }

    // Step Y Buffers
    dst_y += s_dst;
    src_y += s_src;
  }
}

void proxy_stream2(image_combine_t* co) {
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
  const __m128i ones = _mm_cmpeq_epi32(xmm0, xmm0);
  const __m128i shuffle0 = _mm_set_epi64x(0x302030203020302, 0x100010001000100);
  const __m128i shuffle1 = _mm_set_epi64x(0x706070607060706, 0x504050405040504);
  const __m128i shuffle2 = _mm_set_epi64x(0xb0a0b0a0b0a0b0a, 0x908090809080908);
  const __m128i shuffle3 = _mm_set_epi64x(0xf0e0f0e0f0e0f0e, 0xd0c0d0c0d0c0d0c);

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    src_x = src_y;
    count = w;

    // Unpack Mask to RGBA
    while (count > 0) {
      __m128i mask = _mm_load_si128((__m128i*) src_x);
      // Unpack Mask to [AAAA, BBBB, CCCC, DDDD]
      xmm0 = _mm_shuffle_epi8(mask, shuffle0);
      xmm1 = _mm_shuffle_epi8(mask, shuffle1);
      xmm2 = _mm_shuffle_epi8(mask, shuffle2);
      xmm3 = _mm_shuffle_epi8(mask, shuffle3);
      xmm0 = _mm_blend_epi16(xmm0, ones, 0x88);
      xmm1 = _mm_blend_epi16(xmm1, ones, 0x88);
      xmm2 = _mm_blend_epi16(xmm2, ones, 0x88);
      xmm3 = _mm_blend_epi16(xmm3, ones, 0x88);

      // Store Pixels to Buffer
      _mm_stream_si128((__m128i*) dst_x + 0, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 1, xmm1);
      _mm_stream_si128((__m128i*) dst_x + 2, xmm2);
      _mm_stream_si128((__m128i*) dst_x + 3, xmm3);

      // Step X Buffers
      src_x += 16;
      dst_x += 64;
      count -= 8;
    }

    // Step Y Buffers
    dst_y += s_dst;
    src_y += s_src;
  }
}

// -----------------------
// Proxy Streaming Uniform
// -----------------------

void proxy_uniform_fill(image_combine_t* co) {
  // Load Buffer Pointers
  unsigned char *dst_x, *dst_y;
  dst_y = co->dst.buffer;

  int w, h, s_src, s_dst;
  // Load Region
  w = co->src.w;
  h = co->src.h;
  // Load Strides
  s_dst = co->dst.stride;

  __m128i xmm0;
  // Uniform Pixel Value
  xmm0 = _mm_loadl_epi64((__m128i*) co->src.buffer);
  xmm0 = _mm_unpacklo_epi64(xmm0, xmm0);

  for (int count, y = 0; y < h; y++) {
    dst_x = dst_y;
    count = w;

    // Copy Source bytes to Destination
    while (count > 0) {
      // Copy 16 Pixels
      _mm_stream_si128((__m128i*) dst_x, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 1, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 2, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 3, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 4, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 5, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 6, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 7, xmm0);

      // Step Buffer
      dst_x += 128;
      count -= 16;
    }

    // Step Y Buffer
    dst_y += s_dst;
  }
}

void proxy_uniform_stream(image_combine_t* co) {
  // Load Buffer Pointers
  unsigned char *src_x, *src_y;
  unsigned char *dst_x, *dst_y;
  src_y = co->src.buffer;
  dst_y = co->dst.buffer;

  // Load Region
  int w = co->src.w;
  int h = co->src.h;
  // Load Strides
  const int s_src = co->src.stride;
  const int s_dst = co->dst.stride;
  const int s_bpp = co->src.bpp;

  // Source Pixel Values
  __m128i xmm0, xmm1, xmm2, xmm3;
  __m128i xmm4, xmm5, xmm6, xmm7;
  // Load First Pixel from Buffer
  __m128i pixel = _mm_load_si128((__m128i*) src_y);
  __m128i check = _mm_cmpeq_epi32(pixel, pixel);
  const __m128i ones = _mm_set1_epi16(1);
  
  // Prepare Mask and Pixel
  switch (s_bpp) {
    case 2: // Mask 16-bit
      pixel = _mm_unpacklo_epi16(pixel, pixel);
      pixel = _mm_unpacklo_epi32(pixel, pixel);
      pixel = _mm_unpacklo_epi64(pixel, pixel);
      // Remove Ones from Fast Operations
      xmm0 = _mm_cmpeq_epi16(pixel, ones);
      pixel = _mm_andnot_si128(xmm0, pixel);
      break;
    case 4: // RGBA 8-bit
      pixel = _mm_unpacklo_epi32(pixel, pixel);
      pixel = _mm_unpacklo_epi64(pixel, pixel);
      break;
    case 8: // RGBA 16-bit
      pixel = _mm_unpacklo_epi64(pixel, pixel);
      xmm0 = _mm_cmpeq_epi16(pixel, ones);
      pixel = _mm_andnot_si128(xmm0, pixel);
      break;
  }

  for (int y = 0; y < h; y++) {
    int count = w * s_bpp;
    src_x = src_y;
    dst_x = dst_y;

    // Check Region Uniform
    while (count > 0) {
      xmm0 = _mm_load_si128((__m128i*) src_x + 0);
      xmm1 = _mm_load_si128((__m128i*) src_x + 1);
      xmm2 = _mm_load_si128((__m128i*) src_x + 2);
      xmm3 = _mm_load_si128((__m128i*) src_x + 3);

      // Remove Ones from Fast Operations
      if (s_bpp != 4) {
        xmm4 = _mm_cmpeq_epi16(xmm0, ones);
        xmm5 = _mm_cmpeq_epi16(xmm1, ones);
        xmm6 = _mm_cmpeq_epi16(xmm2, ones);
        xmm7 = _mm_cmpeq_epi16(xmm3, ones);
        xmm0 = _mm_andnot_si128(xmm4, xmm0);
        xmm1 = _mm_andnot_si128(xmm5, xmm1);
        xmm2 = _mm_andnot_si128(xmm6, xmm2);
        xmm3 = _mm_andnot_si128(xmm7, xmm3);
      }

      // Store Pixels to Destination
      _mm_stream_si128((__m128i*) dst_x + 0, xmm0);
      _mm_stream_si128((__m128i*) dst_x + 1, xmm1);
      _mm_stream_si128((__m128i*) dst_x + 2, xmm2);
      _mm_stream_si128((__m128i*) dst_x + 3, xmm3);

      // Check Match with Pixel
      xmm0 = _mm_cmpeq_epi16(xmm0, pixel);
      xmm1 = _mm_cmpeq_epi16(xmm1, pixel);
      xmm2 = _mm_cmpeq_epi16(xmm2, pixel);
      xmm3 = _mm_cmpeq_epi16(xmm3, pixel);
      // Combine Match with Pixel
      xmm0 = _mm_and_si128(xmm0, xmm1);
      xmm2 = _mm_and_si128(xmm2, xmm3);
      check = _mm_and_si128(check, xmm0);
      check = _mm_and_si128(check, xmm2);

      // Step Buffer
      src_x += 64;
      dst_x += 64;
      count -= 64;
    }

    // Step Y Buffer
    src_y += s_src;
    dst_y += s_dst;
  }

  // Change Buffer to Uniform
  xmm1 = _mm_cmpeq_epi32(check, check);
  if (_mm_testc_si128(check, xmm1) == 1) {
    co->dst.stride = s_bpp;
    co->dst.bpp = s_bpp;

    // Store Pixel Uniform
    if (s_bpp == 4)
      pixel = _mm_unpacklo_epi8(pixel, pixel);
    _mm_store_si128((__m128i*) co->dst.buffer, pixel);
  }
}
