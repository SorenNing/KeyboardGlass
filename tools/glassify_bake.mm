// Build host only. Uses the original Glassify Core and Metal shader functions.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <dispatch/dispatch.h>
#include "glassify/glass_inputs.h"
#include "glassify/pack.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>
using namespace glassify;
static void Require(bool ok, const char *message) {
    if (!ok) throw std::runtime_error(message);
}
static id<MTLRenderPipelineState> Pipeline(id<MTLDevice> device, id<MTLLibrary> library,
                                          NSString *fragment, bool blending) {
    MTLRenderPipelineDescriptor *d=[MTLRenderPipelineDescriptor new];
    d.vertexFunction=[library newFunctionWithName:@"gls_fullscreen_vertex"];
    d.fragmentFunction=[library newFunctionWithName:fragment];
    Require(d.vertexFunction && d.fragmentFunction,"Original shader entry missing");
    d.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
    d.colorAttachments[0].blendingEnabled=blending;
    if (blending) {
        d.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorOne;
        d.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
        d.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
        d.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    }
    NSError *error=nil;
    id<MTLRenderPipelineState> p=[device newRenderPipelineStateWithDescriptor:d error:&error];
    if (!p) throw std::runtime_error(std::string("Metal pipeline: ")+error.localizedDescription.UTF8String);
    return p;
}
static void SavePNG(id<MTLBuffer> buffer, size_t width, size_t height, size_t stride, NSString *path) {
    NSData *data=[NSData dataWithBytes:buffer.contents length:stride*height];
    CGDataProviderRef provider=CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image=CGImageCreate(width,height,8,32,stride,color,
        (CGBitmapInfo)(kCGBitmapByteOrder32Little|kCGImageAlphaPremultipliedFirst),provider,nullptr,false,kCGRenderingIntentDefault);
    CGImageDestinationRef destination=CGImageDestinationCreateWithURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:path],CFSTR("public.png"),1,nullptr);
    bool ok=image && destination;
    if (ok) { CGImageDestinationAddImage(destination,image,nullptr);ok=CGImageDestinationFinalize(destination); }
    if (destination) CFRelease(destination);
    if (image) CGImageRelease(image);
    if (color) CGColorSpaceRelease(color);
    if (provider) CGDataProviderRelease(provider);
    Require(ok,"Cannot write unmodified GPU pixels as PNG");
}
static NSDictionary *Bake(id<MTLDevice> device, id<MTLCommandQueue> queue,
                          id<MTLRenderPipelineState> background, id<MTLRenderPipelineState> highlight,
                          bool dark, NSString *directory) {
    const float width=192,height=62,scale=3,radius=31;
    const float neutral=128.f/255.f;
    const float luma=quantizeLuma(neutral);
    // Same stock regular/automatic material as GLSTabBarView's _platter.
    // No field in GlassInputs is overwritten after the original factory.
    GlassInputs inputs=glassInputsFor(GlassStyle::Regular,dark?Appearance::Dark:Appearance::Light,
                                      width,height,luma,Frost::Automatic);
    const float margin=std::ceil(std::max({inputs.marginWidth,2.f*inputs.shadowRadius+8.f,
                         inputs.tint[3]>0?inputs.tintFadeDistance+2.f:0.f}));
    const float pad=margin+16; // Original GLSGlassSurface's surface slack.
    const float surfaceWidth=width+2*pad,surfaceHeight=height+2*pad;
    const NSUInteger pixelWidth=(NSUInteger)std::ceil(surfaceWidth*scale);
    const NSUInteger pixelHeight=(NSUInteger)std::ceil(surfaceHeight*scale);
    const NSUInteger outputWidth=(NSUInteger)(width*scale),outputHeight=(NSUInteger)(height*scale);
    ShapeElement shape={pad+width/2,pad+height/2,width,height,radius,0.5f};
    PackContext context;
    context.ptToPx=scale;context.elements=&shape;context.elementCount=1;
    context.backdropWidth=surfaceWidth;context.backdropHeight=surfaceHeight;
    context.backdropPxPerPt=scale*inputs.backdropScale;
    NSUInteger bw=(NSUInteger)std::ceil(surfaceWidth*context.backdropPxPerPt);
    NSUInteger bh=(NSUInteger)std::ceil(surfaceHeight*context.backdropPxPerPt);
    MTLTextureDescriptor *bd=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:bw height:bh mipmapped:YES];
    bd.mipmapLevelCount=std::min<NSUInteger>(bd.mipmapLevelCount,8);
    bd.storageMode=MTLStorageModeShared;bd.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> backdrop=[device newTextureWithDescriptor:bd];
    Require(backdrop!=nil,"No backdrop texture");
    // A spatially constant input stays identical through the original blur
    // pyramid. Fill each mip with those same bytes; no scene-dependent paint.
    for (NSUInteger level=0;level<bd.mipmapLevelCount;level++) {
        NSUInteger w=std::max<NSUInteger>(bw>>level,1),h=std::max<NSUInteger>(bh>>level,1);
        std::vector<uint32_t> pixels(w*h,0xff808080u);
        [backdrop replaceRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:level withBytes:pixels.data() bytesPerRow:w*4];
    }
    context.backdropMaxLod=(float)(bd.mipmapLevelCount-1);
    GLSGlassUniforms uniforms={};packUniforms(inputs,context,uniforms);
    GlowState glow;glow.dark=dark;glow.edr=0;packGlow(glow,uniforms);
    GLSElement elements[GLS_MAX_ELEMENTS]={};packElements(context,elements);
    MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:pixelWidth height:pixelHeight mipmapped:NO];
    td.storageMode=MTLStorageModePrivate;td.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;
    id<MTLTexture> offscreen=[device newTextureWithDescriptor:td],output=[device newTextureWithDescriptor:td];
    MTLTextureDescriptor *ed=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:1 height:1 mipmapped:NO];
    ed.storageMode=MTLStorageModeShared;ed.usage=MTLTextureUsageShaderRead;
    id<MTLTexture> empty=[device newTextureWithDescriptor:ed];
    const uint32_t zero=0;[empty replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:&zero bytesPerRow:4];
    const NSUInteger stride=(outputWidth*4+255)&~(NSUInteger)255;
    id<MTLBuffer> readback=[device newBufferWithLength:stride*outputHeight options:MTLResourceStorageModeShared];
    Require(offscreen && output && empty && readback,"No output storage");
    id<MTLCommandBuffer> command=[queue commandBuffer];
    Require(command!=nil,"No Metal command buffer");
    const float surface[4]={surfaceWidth,surfaceHeight,0,0};
    auto bind=[&](id<MTLRenderCommandEncoder> e) {
        [e setVertexBytes:surface length:sizeof(surface) atIndex:0];
        [e setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
        [e setFragmentBytes:elements length:sizeof(elements) atIndex:1];
        [e setFragmentTexture:backdrop atIndex:0];
        [e setFragmentTexture:empty atIndex:2];[e setFragmentTexture:empty atIndex:3];[e setFragmentTexture:empty atIndex:4];
    };
    MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture=offscreen;pass.colorAttachments[0].loadAction=MTLLoadActionClear;
    pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0);pass.colorAttachments[0].storeAction=MTLStoreActionStore;
    id<MTLRenderCommandEncoder> e=[command renderCommandEncoderWithDescriptor:pass];
    Require(e!=nil,"No background encoder");bind(e);[e setRenderPipelineState:background];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];
    pass.colorAttachments[0].texture=output;pass.colorAttachments[0].loadAction=MTLLoadActionDontCare;
    e=[command renderCommandEncoderWithDescriptor:pass];Require(e!=nil,"No highlight encoder");
    bind(e);[e setFragmentTexture:offscreen atIndex:1];[e setRenderPipelineState:highlight];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[e endEncoding];
    id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
    Require(blit!=nil,"No readback encoder");
    [blit copyFromTexture:output sourceSlice:0 sourceLevel:0
            sourceOrigin:MTLOriginMake((NSUInteger)(pad*scale),(NSUInteger)(pad*scale),0)
              sourceSize:MTLSizeMake(outputWidth,outputHeight,1) toBuffer:readback
       destinationOffset:0 destinationBytesPerRow:stride destinationBytesPerImage:stride*outputHeight];
    [blit endEncoding];
    dispatch_semaphore_t finished=dispatch_semaphore_create(0);
    [command addCompletedHandler:^(__unused id<MTLCommandBuffer> cb) { dispatch_semaphore_signal(finished); }];
    [command commit];
    Require(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC))==0,"GPU render timed out");
    Require(command.status==MTLCommandBufferStatusCompleted,"GPU render failed");
    const uint8_t *bytes=(const uint8_t *)readback.contents;
    NSUInteger center=(outputHeight/2)*stride+(outputWidth/2)*4;
    Require(bytes[center+3]>=250,"Glassify output center is not a completed opaque scene");
    NSString *name=dark?@"GlassifyRegularDark.png":@"GlassifyRegularLight.png";
    SavePNG(readback,outputWidth,outputHeight,stride,[directory stringByAppendingPathComponent:name]);
    return @{@"file":name,@"appearance":dark?@"Dark":@"Light",@"width":@(outputWidth),@"height":@(outputHeight),
             @"center_bgra":@[@(bytes[center]),@(bytes[center+1]),@(bytes[center+2]),@(bytes[center+3])],
             @"factory_luma":@(luma),@"completed":@YES};
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        try {
            Require(argc==3,"Usage: glassify-bake original.metallib output-directory");
            NSString *libraryPath=[NSString stringWithUTF8String:argv[1]];
            NSString *directory=[NSString stringWithUTF8String:argv[2]];
            NSError *error=nil;
            Require([[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error],"Cannot create output directory");
            id<MTLDevice> device=MTLCreateSystemDefaultDevice();Require(device!=nil,"No native Metal device");
            id<MTLCommandQueue> queue=[device newCommandQueue];Require(queue!=nil,"No Metal command queue");
            id<MTLLibrary> library=[device newLibraryWithURL:[NSURL fileURLWithPath:libraryPath] error:&error];
            if (!library) throw std::runtime_error(std::string("Metal library: ")+error.localizedDescription.UTF8String);
            auto background=Pipeline(device,library,@"gls_glass_background",true);
            auto highlight=Pipeline(device,library,@"gls_glass_highlight_texture",false);
            NSDictionary *light=Bake(device,queue,background,highlight,false,directory);
            NSDictionary *dark=Bake(device,queue,background,highlight,true,directory);
            NSDictionary *receipt=@{
                @"generated_by":@"original Glassify Core factory and two-pass Metal shader",
                @"style":@"Regular",@"frost":@"Automatic",@"tint":@"nil",@"content_vibrancy":@NO,
                @"source_rgb":@[@128,@128,@128],@"source_alpha":@255,@"source_kind":@"fixed neutral scene",
                @"platter_points":@[@192,@62],@"corner_radius_points":@31,@"scale":@3,
                @"original_input_fields_overridden":@NO,@"png_alpha_rewritten":@NO,@"runtime_rendering":@NO,
                @"host_bounds_crop":@YES,@"live_app_blur_or_refraction":@NO,
                @"outputs":@[light,dark]};
            NSData *json=[NSJSONSerialization dataWithJSONObject:receipt options:NSJSONWritingPrettyPrinted error:&error];
            Require(json && [json writeToFile:[directory stringByAppendingPathComponent:@"material.json"] options:NSDataWritingAtomic error:&error],"Cannot write provenance");
            std::puts("Original Glassify Regular: light/dark fixed scenes rendered successfully");
            return 0;
        } catch (const std::exception &error) {
            std::fprintf(stderr,"glassify-bake: %s\n",error.what());return 1;
        }
    }
}
