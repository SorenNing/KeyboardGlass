#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "Material.h"
#import <QuartzCore/QuartzCore.h>
#include <unistd.h>
#import "Diagnostics.h"

// Pre-rendered approximation only. No capture, display link or Metal renderer.
static const void *NGImageKey = &NGImageKey;
static UIImage *NGMaterial(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [[NSData alloc] initWithBase64EncodedString:NGMaterialBase64 options:0];
        UIImage *raw = [UIImage imageWithData:data scale:2];
        image = [raw resizableImageWithCapInsets:UIEdgeInsetsMake(14,14,14,14) resizingMode:UIImageResizingModeStretch];
    });
    return image;
}
// Group only directly connected, aligned keyboard backdrops in the same host.
// Each region crops the same original image; no material or key views change.
static const void *NGClipKey = &NGClipKey;
static BOOL NGUpdating = NO;
static void NGCollect(UIView *root, NSMutableArray<UIVisualEffectView *> *out, NSUInteger depth) {
    if (!root || depth > 12 || root.hidden || root.alpha <= 0.0) return;
    if ([NSStringFromClass(root.class) containsString:@"KeyboardDock"]) return;
    Class backdrop = NSClassFromString(@"UIKBBackdropView");
    if (backdrop && [root isKindOfClass:backdrop]) {
        if (root.window && !CGRectIsEmpty(root.bounds)) [out addObject:(UIVisualEffectView *)root];
        return;
    }
    for (UIView *child in root.subviews) NGCollect(child, out, depth + 1);
}
static CGRect NGJoinedRect(UIVisualEffectView *host) {
    UIView *root = host.superview;
    for (UIView *v = root; v && v != host.window; v = v.superview) {
        NSString *name = NSStringFromClass(v.class);
        if ([name containsString:@"InputSetHost"]) { root = v; break; }
        if ([name containsString:@"KeyboardDock"]) break;
        if ([name containsString:@"InputSetContainer"]) break;
    }
    if (!root) return [host convertRect:host.bounds toView:host.window];
    NSMutableArray<UIVisualEffectView *> *all = [NSMutableArray array];
    NGCollect(root, all, 0);
    CGRect joined = [host convertRect:host.bounds toView:host.window];
    for (NSUInteger pass = 0; pass < all.count; pass++) {
        BOOL changed = NO;
        for (UIVisualEffectView *other in all) {
            if (other.window != host.window) continue;
            CGRect r = [other convertRect:other.bounds toView:host.window];
            if (fabs(CGRectGetMinX(r) - CGRectGetMinX(joined)) > 3.0 ||
                fabs(CGRectGetWidth(r) - CGRectGetWidth(joined)) > 3.0) continue;
            if (CGRectGetMinY(r) > CGRectGetMaxY(joined) + 2.0 ||
                CGRectGetMaxY(r) < CGRectGetMinY(joined) - 2.0) continue;
            CGRect next = CGRectUnion(joined, r);
            if (!CGRectEqualToRect(next, joined)) { joined = next; changed = YES; }
        }
        if (!changed) break;
    }
    return joined;
}
static void NGApply(UIVisualEffectView *host) {
    if (!host.window || CGRectIsEmpty(host.bounds)) return;
    UIImage *material = NGMaterial();
    if (!material) return; // Do not remove native background if asset fails.
    UIView *clip = objc_getAssociatedObject(host, NGClipKey);
    if (!clip) {
        clip = [[UIView alloc] initWithFrame:host.contentView.bounds];
        clip.userInteractionEnabled = NO;
        clip.isAccessibilityElement = NO;
        clip.backgroundColor = UIColor.clearColor;
        clip.clipsToBounds = YES;
        [host.contentView insertSubview:clip atIndex:0];
        objc_setAssociatedObject(host, NGClipKey, clip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIImageView *view = objc_getAssociatedObject(host, NGImageKey);
    if (!view) {
        view = [[UIImageView alloc] initWithImage:material];
        view.userInteractionEnabled = NO;
        view.isAccessibilityElement = NO;
        [clip addSubview:view];
        objc_setAssociatedObject(host, NGImageKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    clip.frame = host.contentView.bounds;
    view.frame = [clip convertRect:NGJoinedRect(host) fromView:host.window];
    if (host.effect) host.effect = nil;
    // Single-variable test: only the direct system backdrop child.
    Class backdropHostClass = NSClassFromString(@"UIKBBackdropView");
    Class backdropChildClass = NSClassFromString(@"_UIVisualEffectBackdropView");
    if (backdropHostClass && backdropChildClass && [host isKindOfClass:backdropHostClass]) {
        for (UIView *child in host.subviews) {
            if (object_getClass(child) == backdropChildClass) {
                child.hidden = NO;
                child.alpha = 0.8;
            }
        }
    }
    host.backgroundColor = UIColor.clearColor;
    host.contentView.backgroundColor = UIColor.clearColor;
}
static void (*NGOriginalLayout)(id,SEL);
static void NGLayout(id self, SEL cmd) {
    NGOriginalLayout(self,cmd);
    if (NGUpdating) return;
    NGUpdating = YES;
    @try {
        NGDiagnostic(self, NO);
        NGApply(self);
        NGDiagnostic(self, YES);
        UIView *root = [self superview];
        for (UIView *v = root; v && v != [self window]; v = v.superview) {
            if ([NSStringFromClass(v.class) containsString:@"InputSetHost"]) { root = v; break; }
            if ([NSStringFromClass(v.class) containsString:@"KeyboardDock"]) break;
        }
        NSMutableArray<UIVisualEffectView *> *all = [NSMutableArray array];
        NGCollect(root, all, 0);
        for (UIVisualEffectView *other in all) if (other != self) NGApply(other);
    } @finally { NGUpdating = NO; }
}
static BOOL NGHasVoidMethod(Class cls, SEL selector) {
    Method m=class_getInstanceMethod(cls,selector);
    if (!m || method_getNumberOfArguments(m)!=2) return NO;
    char *type=method_copyReturnType(m);
    BOOL ok=type && strcmp(type,"v")==0;
    free(type);
    return ok;
}
__attribute__((constructor)) static void NGInstall(void) {
    @autoreleasepool {
        Class cls=NSClassFromString(@"UIKBBackdropView");
        SEL sel=@selector(layoutSubviews);
        if (!cls || ![cls isSubclassOfClass:UIVisualEffectView.class] || !NGHasVoidMethod(cls,sel)) return;
        typedef void (*Hook)(Class,SEL,IMP,IMP *);
        Hook hook=(Hook)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
        if (!hook) return;
        static BOOL installed=NO;
        if (installed) return;
        installed=YES;
        hook(cls,sel,(IMP)NGLayout,(IMP *)&NGOriginalLayout);
    }
}
