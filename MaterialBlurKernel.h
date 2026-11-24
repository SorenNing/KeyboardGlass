#pragma once
#include <math.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

// In-memory separable Gaussian on premultiplied RGBA. No screen/backdrop capture.
// The caller restores the geometric outline after filtering to prevent spill.
static inline int NGBlurRGBA(uint8_t *pixels, size_t width, size_t height, size_t stride, double sigma) {
    if (!pixels || !width || !height || stride < width*4 || !isfinite(sigma) || sigma<0) return 0;
    if (sigma==0) return 1; // byte-identical zero-strength path
    sigma=fmin(sigma,12);
    int radius=(int)ceil(3*sigma);
    float weights[73]; double total=0;
    for (int i=-radius;i<=radius;i++) { weights[i+radius]=(float)exp(-(i*i)/(2*sigma*sigma)); total+=weights[i+radius]; }
    for (int i=0;i<2*radius+1;i++) weights[i]/=(float)total;
    if (height>SIZE_MAX/stride) return 0;
    uint8_t *scratch=malloc(height*stride);
    if (!scratch) return 0;
    for (size_t y=0;y<height;y++) for(size_t x=0;x<width;x++) for(int c=0;c<4;c++) {
        double sum=0;
        for(int k=-radius;k<=radius;k++) {
            long xx=(long)x+k; xx=xx<0 ? 0 : (xx>=(long)width ? (long)width-1 : xx);
            sum+=pixels[y*stride+(size_t)xx*4+c]*weights[k+radius];
        }
        scratch[y*stride+x*4+c]=(uint8_t)lrint(fmin(255,fmax(0,sum)));
    }
    for (size_t y=0;y<height;y++) for(size_t x=0;x<width;x++) for(int c=0;c<4;c++) {
        double sum=0;
        for(int k=-radius;k<=radius;k++) {
            long yy=(long)y+k; yy=yy<0 ? 0 : (yy>=(long)height ? (long)height-1 : yy);
            sum+=scratch[(size_t)yy*stride+x*4+c]*weights[k+radius];
        }
        pixels[y*stride+x*4+c]=(uint8_t)lrint(fmin(255,fmax(0,sum)));
    }
    free(scratch); return 1;
}
