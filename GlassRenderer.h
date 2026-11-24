#import <UIKit/UIKit.h>
#import "GlassPreferences.h"

// Signed distance to a rounded rectangle with superellipse corners.
// Positive inside. Radius and edge shape do not change the keyboard layout.
static inline double NGGlassDistance(double x, double y, double half, double radius, double exponent) {
    double qx = fabs(x-half)-(half-radius), qy = fabs(y-half)-(half-radius);
    double ax = fmax(qx,0), ay = fmax(qy,0);
    double n = pow(pow(ax,exponent)+pow(ay,exponent),1.0/exponent);
    return radius - n - fmin(fmax(qx,qy),0);
}
static inline void NGOver(double *r, double *g, double *b, double *a,
                   double nr, double ng, double nb, double na) {
    na = fmin(1,fmax(0,na));
    *r = nr*na + *r*(1-na); *g = ng*na + *g*(1-na);
    *b = nb*na + *b*(1-na); *a = na + *a*(1-na);
}
static inline UIImage *NGDrawGlass(NSDictionary *v) {
    const size_t side = 256, stride = side*4;
    unsigned char *pixels = calloc(side,stride);
    if (!pixels) return nil;
    const double scale = 2, half = 64;
    double radius=[v[@"CornerRadius"] doubleValue], shape=[v[@"CornerShape"] doubleValue];
    double opacity=[v[@"BodyOpacity"] doubleValue], gain=[v[@"BodyBrightness"] doubleValue];
    double red=fmin(1,[v[@"BodyRed"] doubleValue]*gain), green=fmin(1,[v[@"BodyGreen"] doubleValue]*gain), blue=fmin(1,[v[@"BodyBlue"] doubleValue]*gain);
    double gradient=[v[@"GradientStrength"] doubleValue], angle=[v[@"GradientAngle"] doubleValue]*M_PI/180;
    double thickness=[v[@"HighlightThickness"] doubleValue], light=[v[@"HighlightBrightness"] doubleValue];
    double width=[v[@"HighlightWidth"] doubleValue], softness=[v[@"EdgeSoftness"] doubleValue];
    double inner=[v[@"InnerShadow"] doubleValue], outer=[v[@"OuterShadow"] doubleValue];
    // Margin reserves pixels for external shadow within the existing clipped backdrop.
    double margin=outer>0 ? 6 : 0;
    for (size_t y=0;y<side;y++) for (size_t x=0;x<side;x++) {
        double px=(x+.5)/scale, py=(y+.5)/scale;
        double d=NGGlassDistance(px,py,half,radius,shape)-margin;
        double rr=0,gg=0,bb=0,aa=0;
        if (outer>0 && d<0) {
            double shift=NGGlassDistance(px,py-1.5,half,radius,shape)-margin;
            NGOver(&rr,&gg,&bb,&aa,0,0,0,outer*.6*exp(-pow(fmin(0,shift)/2.5,2)));
        }
        if (d>=-.5) {
            double coverage=fmin(1,fmax(0,(d+.5)/fmax(.5,softness)));
            // Uniform center; directional gradient is confined to stretch-safe caps.
            double nx=(px-half)/half, ny=(py-half)/half;
            double ramp=fmin(1,fmax(-1,(nx*cos(angle)+ny*sin(angle))));
            double edge=exp(-fmax(d,0)/8);
            double bodyAlpha=fmin(1,fmax(0,opacity+gradient*ramp*edge*.3));
            NGOver(&rr,&gg,&bb,&aa,red,green,blue,bodyAlpha*coverage);
            if (inner>0) {
                double lower=.35+.65*(py/128);
                NGOver(&rr,&gg,&bb,&aa,0,0,0,inner*lower*exp(-pow((d-3)/3.5,2))*coverage);
            }
            double ring=thickness>0 ? exp(-pow((d-thickness*.5)/fmax(.25,thickness*.6),2)) : 0;
            double halo=width>0 ? .35*exp(-pow(d/fmax(.25,width),2)) : 0;
            double directional=fmin(1,fmax(.15,.7-.3*ny+.15*(-nx)));
            NGOver(&rr,&gg,&bb,&aa,1,1,1,light*directional*fmin(1,ring+halo)*coverage);
        }
        size_t o=y*stride+x*4;
        pixels[o]=(unsigned char)lrint(fmin(1,rr)*255);
        pixels[o+1]=(unsigned char)lrint(fmin(1,gg)*255);
        pixels[o+2]=(unsigned char)lrint(fmin(1,bb)*255);
        pixels[o+3]=(unsigned char)lrint(fmin(1,aa)*255);
    }
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(pixels,side,side,8,stride,space,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    CGImageRef image=context ? CGBitmapContextCreateImage(context) : NULL;
    UIImage *result=image ? [UIImage imageWithCGImage:image scale:2 orientation:UIImageOrientationUp] : nil;
    if (image) CGImageRelease(image);
    if (context) CGContextRelease(context);
    free(pixels);
    // All variable corners and rims stay in non-stretched caps (maximum radius 40).
    CGFloat cap=MAX(28,MIN(56,radius+16));
    return [result resizableImageWithCapInsets:UIEdgeInsetsMake(cap,cap,cap,cap) resizingMode:UIImageResizingModeStretch];
}
