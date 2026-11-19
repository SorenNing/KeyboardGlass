#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "KeyboardSurface.h"
#import "CandidateAppearance.h"

// No timer, display link, background capture or Metal renderer.
#define NG_LAYOUT_HOOK(NAME, ACTION) \
    static void (*NAME##Original)(id,SEL); \
    static void NAME(id self, SEL cmd) { NAME##Original(self,cmd); ACTION; }
NG_LAYOUT_HOOK(NGBackdropLayout, NGSurfaceRefresh(self))
NG_LAYOUT_HOOK(NGBackdropWindow, NGSurfaceRefresh(self))
NG_LAYOUT_HOOK(NGBitmapLayout, NGSurfaceRefresh(self))
NG_LAYOUT_HOOK(NGBitmapWindow, NGSurfaceRefresh(self))
NG_LAYOUT_HOOK(NGHostLayout, NGSurfaceWindowRefresh(self))
NG_LAYOUT_HOOK(NGHostingUpdate, NGSurfaceHostingRefresh(self))
NG_LAYOUT_HOOK(NGCandidateLayout, NGSurfaceCandidateRefresh(self))
NG_LAYOUT_HOOK(NGCandidateWindow, NGSurfaceCandidateRefresh(self))
NG_LAYOUT_HOOK(NGPredictionLayout, NGSurfaceCandidateRefresh(self))
NG_LAYOUT_HOOK(NGPredictionWindow, NGSurfaceCandidateRefresh(self))
NG_LAYOUT_HOOK(NGArrowLayout, NGCandidateApply(self, NGSurfaceMaterialAvailable() && NGSurfaceHasCoverage(self)))
NG_LAYOUT_HOOK(NGArrowWindow, NGCandidateApply(self, NGSurfaceMaterialAvailable() && NGSurfaceHasCoverage(self)))
NG_LAYOUT_HOOK(NGMaskLayout, NGCandidateApply(self, NGSurfaceMaterialAvailable() && NGSurfaceHasCoverage(self)))
NG_LAYOUT_HOOK(NGMaskWindow, NGCandidateApply(self, NGSurfaceMaterialAvailable() && NGSurfaceHasCoverage(self)))
#undef NG_LAYOUT_HOOK

typedef struct {
    const char *className, *selector;
    IMP replacement;
    void (*original)(id,SEL);
    BOOL done;
} NGHookEntry;
static NGHookEntry NGHooks[] = {
#define NG_ENTRY(C, S, N) { C, S, (IMP)N, NULL, NO }
    NG_ENTRY("UIKBBackdropView", "layoutSubviews", NGBackdropLayout),
    NG_ENTRY("UIKBBackdropView", "didMoveToWindow", NGBackdropWindow),
    NG_ENTRY("UIKBBackgroundView", "layoutSubviews", NGBitmapLayout),
    NG_ENTRY("UIKBBackgroundView", "didMoveToWindow", NGBitmapWindow),
    NG_ENTRY("UIInputSetHostView", "layoutSubviews", NGHostLayout),
    NG_ENTRY("UIInputWindowControllerHostingItem", "someViewDidLayoutSubviews", NGHostingUpdate),
    NG_ENTRY("TUICandidateView", "layoutSubviews", NGCandidateLayout),
    NG_ENTRY("TUICandidateView", "didMoveToWindow", NGCandidateWindow),
    NG_ENTRY("TUIPredictionView", "layoutSubviews", NGPredictionLayout),
    NG_ENTRY("TUIPredictionView", "didMoveToWindow", NGPredictionWindow),
    NG_ENTRY("TUICandidateArrowButton", "layoutSubviews", NGArrowLayout),
    NG_ENTRY("TUICandidateArrowButton", "didMoveToWindow", NGArrowWindow),
    NG_ENTRY("TUICandidateMask", "layoutSubviews", NGMaskLayout),
    NG_ENTRY("TUICandidateMask", "didMoveToWindow", NGMaskWindow)
#undef NG_ENTRY
};
static void **NGOriginalSlots[] = {
    (void **)&NGBackdropLayoutOriginal, (void **)&NGBackdropWindowOriginal,
    (void **)&NGBitmapLayoutOriginal, (void **)&NGBitmapWindowOriginal,
    (void **)&NGHostLayoutOriginal, (void **)&NGHostingUpdateOriginal,
    (void **)&NGCandidateLayoutOriginal, (void **)&NGCandidateWindowOriginal,
    (void **)&NGPredictionLayoutOriginal, (void **)&NGPredictionWindowOriginal,
    (void **)&NGArrowLayoutOriginal, (void **)&NGArrowWindowOriginal,
    (void **)&NGMaskLayoutOriginal, (void **)&NGMaskWindowOriginal
};
static BOOL NGHasVoidMethod(Class cls, SEL selector) {
    Method m = class_getInstanceMethod(cls,selector);
    if (!m || method_getNumberOfArguments(m)!=2) return NO;
    char *type = method_copyReturnType(m);
    BOOL valid = type && strcmp(type,"v")==0;
    free(type);
    return valid;
}
static void NGInstallHooks(void) {
    typedef void (*Hook)(Class,SEL,IMP,IMP *);
    Hook hook = (Hook)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
    if (!hook) return;
    for (NSUInteger i=0; i<sizeof(NGHooks)/sizeof(NGHooks[0]); i++) {
        NGHookEntry *entry = &NGHooks[i];
        if (entry->done) continue;
        Class cls = objc_getClass(entry->className);
        SEL sel = sel_registerName(entry->selector);
        if (!cls || !NGHasVoidMethod(cls,sel)) continue;
        entry->done = YES; // Never overwrite an original slot on retry.
        hook(cls,sel,entry->replacement,(IMP *)NGOriginalSlots[i]);
    }
}
__attribute__((constructor)) static void NGInstall(void) {
    @autoreleasepool {
        NGInstallHooks();
        // TextInputUI may load after our UIKit-filtered dylib. Recheck only
        // when a bundle loads, never with polling or a rendering loop.
        [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            NGInstallHooks();
        }];
    }
}
