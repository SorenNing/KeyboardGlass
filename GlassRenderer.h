#import <UIKit/UIKit.h>
#import "GlassPreferences.h"
#import "GlassRaster.h"

static inline NGGlassRasterValues NGRasterValues(NSDictionary *v) {
    double gain=[v[@"BodyBrightness"] doubleValue];
    NGGlassRasterValues p={
        .radius=[v[@"CornerRadius"] doubleValue], .shape=[v[@"CornerShape"] doubleValue],
        .red=NGClamp01([v[@"BodyRed"] doubleValue]*gain),
        .green=NGClamp01([v[@"BodyGreen"] doubleValue]*gain),
        .blue=NGClamp01([v[@"BodyBlue"] doubleValue]*gain),
        .opacity=[v[@"BodyOpacity"] doubleValue], .gradient=[v[@"GradientStrength"] doubleValue],
        .angle=[v[@"GradientAngle"] doubleValue]*M_PI/180,
        .thickness=[v[@"HighlightThickness"] doubleValue], .light=[v[@"HighlightBrightness"] doubleValue],
        .width=[v[@"HighlightWidth"] doubleValue], .softness=[v[@"EdgeSoftness"] doubleValue],
        .inner=[v[@"InnerShadow"] doubleValue], .outer=[v[@"OuterShadow"] doubleValue]
    };
    return p;
}
static inline UIImage *NGDrawGlassImage(NSDictionary *v, BOOL outline) {
    // Keep a 128pt tile but render at 3x with 2x2 subpixel integration. Both
    // consumers use identical sampling/caps and preserve those caps at runtime.
    const double scale=3;
    const size_t side=384, stride=side*4;
    unsigned char *pixels=calloc(side,stride);
    if (!pixels) return nil;
    NGGlassRasterValues p=NGRasterValues(v);
    for(size_t y=0;y<side;y++) for(size_t x=0;x<side;x++) {
        double sum[4]={0,0,0,0};
        for(int j=0;j<2;j++) for(int i=0;i<2;i++) {
            double px=(x+(i+.5)/2)/scale,py=(y+(j+.5)/2)/scale;
            if(outline) {
                double d=NGGlassDistance(px,py,64,p.radius,p.shape);
                double a=NGGlassCoverage(d,p.softness,scale);
                for(int c=0;c<4;c++) sum[c]+=a;
            } else {
                double color[4];NGGlassSample(p,px,py,scale,color);
                for(int c=0;c<4;c++) sum[c]+=color[c];
            }
        }
        for(int c=0;c<4;c++) pixels[y*stride+x*4+c]=(unsigned char)lrint(NGClamp01(sum[c]*.25)*255);
    }
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,side,side,8,stride,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    CGImageRef image=context ? CGBitmapContextCreateImage(context) : NULL;
    UIImage *result=image ? [UIImage imageWithCGImage:image scale:scale orientation:UIImageOrientationUp] : nil;
    if(image) CGImageRelease(image);
    if(context) CGContextRelease(context);
    free(pixels);
    CGFloat cap=round(MAX(28,MIN(56,p.radius+16))*scale)/scale;
    return [result resizableImageWithCapInsets:UIEdgeInsetsMake(cap,cap,cap,cap) resizingMode:UIImageResizingModeStretch];
}
// System-background alpha coverage is geometric and independent of shadow strength.
static inline UIImage *NGDrawOutline(NSDictionary *v) { return NGDrawGlassImage(v,YES); }
static inline UIImage *NGDrawGlass(NSDictionary *v) { return NGDrawGlassImage(v,NO); }
