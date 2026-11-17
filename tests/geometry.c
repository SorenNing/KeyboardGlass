#include "../KeyboardGeometry.h"
#include <assert.h>
#include <stdio.h>
static void joined(NGSurfaceRect a, NGSurfaceRect b, int yes) {
    assert(NGSurfaceConnected(a,b)==yes);
    assert(NGSurfaceConnected(b,a)==yes);
}
int main(void) {
    NGSurfaceRect row={0,0,390,44}, keys={0,44,390,270}, dock={0,314,390,80};
    NGSurfaceRect r[]={row,keys,dock}; uintptr_t s[]={1,1,1}; size_t g[3];
    NGSurfaceGroups(r,s,3,g);
    assert(g[0]==g[1] && g[1]==g[2]);
    NGSurfaceRect u=NGSurfaceUnion(NGSurfaceUnion(row,keys),dock);
    assert(u.x==0 && u.y==0 && u.w==390 && u.h==394);
    joined(row,keys,1);
    joined((NGSurfaceRect){0,0,844,44},(NGSurfaceRect){0,44,844,220},1);
    joined((NGSurfaceRect){98,0,292,44},(NGSurfaceRect){98,44,292,270},1);
    joined((NGSurfaceRect){0,0,390,240},(NGSurfaceRect){0,240,390,270},1);
    joined(row,(NGSurfaceRect){0,52,390,270},1);
    joined(row,(NGSurfaceRect){0,53,390,270},0);
    joined((NGSurfaceRect){0,0,160,200},(NGSurfaceRect){230,0,160,200},0);
    joined(row,(NGSurfaceRect){0,700,390,100},0);
    joined(row,(NGSurfaceRect){0,44,0,270},0);
    joined(row,(NGSurfaceRect){NAN,44,390,270},0);
    s[1]=2; s[2]=2; NGSurfaceGroups(r,s,3,g);
    assert(g[0]!=g[1] && g[1]==g[2]);
    NGSurfaceGroups(r,s,0,g);
    puts("geometry: 14 cases passed");
}
