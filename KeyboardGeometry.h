#ifndef NG_KEYBOARD_GEOMETRY_H
#define NG_KEYBOARD_GEOMETRY_H
#include <math.h>
#include <stddef.h>
#include <stdint.h>
typedef struct { double x, y, w, h; } NGSurfaceRect;
static inline int NGSurfaceValid(NGSurfaceRect r) {
    return isfinite(r.x) && isfinite(r.y) && isfinite(r.w) && isfinite(r.h) && r.w > 0 && r.h > 0;
}
static inline NGSurfaceRect NGSurfaceUnion(NGSurfaceRect a, NGSurfaceRect b) {
    double x = fmin(a.x,b.x), y = fmin(a.y,b.y);
    return (NGSurfaceRect){x,y,fmax(a.x+a.w,b.x+b.w)-x,fmax(a.y+a.h,b.y+b.h)-y};
}
// Adjacent full-width strips of one keyboard share one surface. A separate
// floating keyboard or another window is never joined just by screen width.
static inline int NGSurfaceConnected(NGSurfaceRect a, NGSurfaceRect b) {
    if (!NGSurfaceValid(a) || !NGSurfaceValid(b)) return 0;
    double overlap = fmin(a.x+a.w,b.x+b.w)-fmax(a.x,b.x);
    double gap = fmax(a.y,b.y)-fmin(a.y+a.h,b.y+b.h);
    return overlap >= fmin(a.w,b.w)*0.8 && gap <= 8.0;
}
static inline void NGSurfaceGroups(const NGSurfaceRect *r, const uintptr_t *scope, size_t n, size_t *group) {
    for (size_t i=0;i<n;i++) group[i]=i;
    for (size_t i=0;i<n;i++) for (size_t j=0;j<i;j++) {
        if (scope[i] != scope[j] || !NGSurfaceConnected(r[i],r[j])) continue;
        size_t a=group[i],b=group[j];
        for (size_t k=0;k<n;k++) if (group[k]==a) group[k]=b;
    }
}
#endif
