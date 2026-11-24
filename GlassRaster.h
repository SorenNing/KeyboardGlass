#pragma once
#include <math.h>
#include <stddef.h>

// All distances are in points. Outward unit normals make straight edges
// constant across nine-slice caps instead of changing brightness at the join.
typedef struct { double distance, nx, ny; } NGGlassGeometry;
typedef struct {
    double radius, shape, red, green, blue, opacity, gradient, angle;
    double thickness, light, width, softness, inner, outer;
} NGGlassRasterValues;
static inline double NGClamp01(double x) { return fmin(1,fmax(0,x)); }
static inline NGGlassGeometry NGGlassGeometryAt(double x,double y,double half,double radius,double exponent) {
    double sx=x-half, sy=y-half;
    double qx=fabs(sx)-(half-radius), qy=fabs(sy)-(half-radius);
    double ax=fmax(qx,0), ay=fmax(qy,0);
    double n=exponent==2 ? hypot(ax,ay) : pow(pow(ax,exponent)+pow(ay,exponent),1.0/exponent);
    double gx=0,gy=0,raw=radius-n-fmin(fmax(qx,qy),0);
    if (n>1e-10) {
        gx=pow(ax/n,exponent-1); gy=pow(ay/n,exponent-1);
    } else if(qx>=qy) gx=1;
    else gy=1;
    double length=hypot(gx,gy);
    NGGlassGeometry g={raw/fmax(length,1e-10),gx*(sx<0 ? -1:1)/length,gy*(sy<0 ? -1:1)/length};
    return g;
}
static inline double NGGlassDistance(double x,double y,double half,double radius,double exponent) {
    return NGGlassGeometryAt(x,y,half,radius,exponent).distance;
}
static inline double NGGlassCoverage(double distance,double softness,double scale) {
    // Center the transition on the actual contour, regardless of shadow strength.
    double span=fmax(1.0/scale,softness),t=NGClamp01(distance/span+.5);
    return t*t*(3-2*t);
}
static inline void NGOver(double *r,double *g,double *b,double *a,double nr,double ng,double nb,double na) {
    na=NGClamp01(na);
    *r=nr*na+*r*(1-na);*g=ng*na+*g*(1-na);*b=nb*na+*b*(1-na);*a=na+*a*(1-na);
}
static inline void NGGlassSample(NGGlassRasterValues v,double x,double y,double scale,double out[4]) {
    NGGlassGeometry g=NGGlassGeometryAt(x,y,64,v.radius,v.shape);
    double d=g.distance,aa=1.0/scale;
    double coverage=NGGlassCoverage(d,v.softness,scale);
    double r=0,green=0,b=0,a=0;
    // Cast into the existing corner cutout only. Never reserve an inset margin
    // or move the body to make room for a shadow: layout bounds stay fixed.
    if(v.outer>0 && coverage<1) {
        double shifted=NGGlassDistance(x,y-1.5,64,v.radius,v.shape);
        NGOver(&r,&green,&b,&a,0,0,0,v.outer*.6*exp(-pow(fmin(0,shifted)/2.5,2))*(1-coverage));
    }
    if(coverage>0) {
        double ramp=g.nx*cos(v.angle)+g.ny*sin(v.angle);
        double edge=exp(-fmax(d,0)/8);
        double ring=v.thickness>0 ? exp(-pow((d-v.thickness*.5)/fmax(aa*.5,v.thickness*.6),2)) : 0;
        double halo=v.width>0 ? .35*exp(-pow(d/fmax(aa*.5,v.width),2)) : 0;
        double directional=NGClamp01(.7-.3*g.ny-.15*g.nx);

        // Apply geometric coverage once to the complete body, so overlapping
        // tint/highlight/shadow components cannot turn AA pixels into hard edges.
        // The separate shadow already lives outside this body.
        double body[4]={0,0,0,0};
        NGOver(&body[0],&body[1],&body[2],&body[3],v.red,v.green,v.blue,NGClamp01(v.opacity+v.gradient*ramp*edge*.3));
        if(v.inner>0) NGOver(&body[0],&body[1],&body[2],&body[3],0,0,0,v.inner*(.35+.65*fmax(0,g.ny))*exp(-pow((d-3)/3.5,2)));
        NGOver(&body[0],&body[1],&body[2],&body[3],1,1,1,v.light*directional*fmin(1,ring+halo));
        // Compose the coverage-weighted material over the outside shadow.
        r=body[0]*coverage+r*(1-body[3]*coverage);
        green=body[1]*coverage+green*(1-body[3]*coverage);
        b=body[2]*coverage+b*(1-body[3]*coverage);
        a=body[3]*coverage+a*(1-body[3]*coverage);
    }
    out[0]=r;out[1]=green;out[2]=b;out[3]=a;
}
