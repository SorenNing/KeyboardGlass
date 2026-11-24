"""Exercise the production raster math; no UIKit or device-visual claim."""
from pathlib import Path
import subprocess,tempfile
P=Path(__file__).resolve().parents[1]
code=r'''#include "GlassRaster.h"
#include <assert.h>
#include <stdio.h>
static int checks;
static void check(int v) { assert(v);checks++; }
int main(void) {
 for(int ri=0;ri<=40;ri+=2) for(int pi=20;pi<=50;pi+=2) {
  double radius=ri,shape=pi/10.;
  NGGlassRasterValues v={.radius=radius,.shape=shape,.red=1,.green=1,.blue=1,
   .opacity=.06,.gradient=.12,.angle=1.5707963267948966,.thickness=1.2,.light=.75,.width=5,.softness=.6,.inner=.24};
  // OuterShadow cannot change the contour or shrink the body by 6pt.
  for(int shadow=0;shadow<3;shadow++) {
   v.outer=shadow*.1;
   check(fabs(NGGlassDistance(64,0,64,radius,shape))<1e-10);
   check(fabs(NGGlassDistance(128,64,64,radius,shape))<1e-10);
   check(fabs(NGGlassCoverage(0,.6,3)-.5)<1e-10);
   double color[4];NGGlassSample(v,64,1,3,color);check(color[3]>.06);
   for(int c=0;c<3;c++) check(color[c]>=0 && color[c]<=color[3]+1e-12);
  }
  // Nine-slice cap/center rows on straight top/right edges must be identical.
  double cap=fmax(28,fmin(56,radius+16));
  for(int k=1;k<=18;k++) {
   double a[4],b[4];double inset=k/6.;
   NGGlassSample(v,cap-.1,inset,3,a);NGGlassSample(v,cap+.1,inset,3,b);
   for(int c=0;c<4;c++) check(fabs(a[c]-b[c])<1e-9);
   NGGlassSample(v,128-inset,cap-.1,3,a);NGGlassSample(v,128-inset,cap+.1,3,b);
   for(int c=0;c<4;c++) check(fabs(a[c]-b[c])<1e-9);
  }
  if(radius==0) continue;
  // Sample the actual superellipse contour and its outward normal. The boundary
  // is fixed, coverage monotonic, and equal-width highlight uses unit distance.
  for(int i=1;i<40;i++) {
   double angle=i*1.5707963267948966/40.;
   double x=128-radius+radius*pow(cos(angle),2/shape);
   double y=radius-radius*pow(sin(angle),2/shape);
   NGGlassGeometry g=NGGlassGeometryAt(x,y,64,radius,shape);
   check(fabs(g.distance)<1e-8);
   check(fabs(hypot(g.nx,g.ny)-1)<1e-10);
   double inside=NGGlassDistance(x-g.nx*.05,y-g.ny*.05,64,radius,shape);
   double outside=NGGlassDistance(x+g.nx*.05,y+g.ny*.05,64,radius,shape);
   check(inside>0 && outside<0);
   check(NGGlassCoverage(inside,.4,3)>NGGlassCoverage(outside,.4,3));
  }
 }
 printf("PASS: %d production raster checks: fixed frame, shadow-independent contour, cap continuity, unit normals, premultiplied AA\n",checks);
 return 0;
}
'''
with tempfile.TemporaryDirectory() as t:
 f=Path(t)/'edges.c';exe=Path(t)/'edges';f.write_text(code)
 subprocess.run(['cc','-O2','-Wall','-Wextra','-Werror','-I',str(P),str(f),'-lm','-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
