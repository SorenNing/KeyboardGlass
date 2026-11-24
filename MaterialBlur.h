#pragma once
#import <UIKit/UIKit.h>
#import "MaterialBlurKernel.h"

// Filter only the cached material image. Never add views or sample App pixels.
static inline UIImage *NGBlurMaterial(UIImage *source, double strength) {
    if (!source || strength<=0 || !isfinite(strength)) return source;
    CGImageRef raw=source.CGImage;
    if (!raw) return source;
    size_t width=CGImageGetWidth(raw), height=CGImageGetHeight(raw), stride=width*4;
    if (!width || !height || width>2048 || height>2048) return source;
    uint8_t *pixels=calloc(height,stride), *support=calloc(height,width);
    if (!pixels || !support) { free(pixels); free(support); return source; }
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(pixels,width,height,8,stride,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) { free(pixels); free(support); return source; }
    CGContextDrawImage(ctx,CGRectMake(0,0,width,height),raw);
    for(size_t y=0;y<height;y++) for(size_t x=0;x<width;x++) support[y*width+x]=pixels[y*stride+x*4+3];
    // At scale 2, maximum sigma is 4pt. Shared cap mapping stays unchanged.
    if (!NGBlurRGBA(pixels,width,height,stride,fmin(1,strength)*4*source.scale)) {
        CGContextRelease(ctx);free(pixels);free(support);return source;
    }
    // Keep the original transparent silhouette. Outside shadows/highlights must
    // not bleed beyond the existing image outline into adjacent keyboard slices.
    for(size_t y=0;y<height;y++) for(size_t x=0;x<width;x++) {
        size_t o=y*stride+x*4;
        if (!support[y*width+x]) memset(pixels+o,0,4);
    }
    CGImageRef filtered=CGBitmapContextCreateImage(ctx);
    UIImage *image=filtered ? [UIImage imageWithCGImage:filtered scale:source.scale orientation:source.imageOrientation] : nil;
    if(filtered) CGImageRelease(filtered);
    CGContextRelease(ctx);free(pixels);free(support);
    return image ? [image resizableImageWithCapInsets:source.capInsets resizingMode:source.resizingMode] : source;
}
