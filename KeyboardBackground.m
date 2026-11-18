#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <os/log.h>
#import "Material.h"

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
static UIView *NGSurface(UIView *view) {
    Class cls = NSClassFromString(@"UIInputSetHostView");
    for (UIView *p = view; p; p = p.superview) {
        if (cls && [p isKindOfClass:cls]) return p;
    }
    return nil;
}
static void NGApply(UIView *surface) {
    if (!surface.window || CGRectIsEmpty(surface.bounds)) return;
    UIImage *image = NGMaterial();
    if (!image) return;
    UIImageView *view = objc_getAssociatedObject(surface, NGImageKey);
    if (!view) {
        view = [[UIImageView alloc] initWithImage:image];
        view.userInteractionEnabled = NO;
        view.isAccessibilityElement = NO;
        view.accessibilityElementsHidden = YES;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        // One background and one outline for the entire keyboard host.
        view.alpha = 0.85;
        view.layer.cornerRadius = 14;
        view.layer.masksToBounds = YES;
        view.layer.borderWidth = 1.25;
        view.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
        [surface insertSubview:view atIndex:0];
        objc_setAssociatedObject(surface, NGImageKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    view.frame = surface.bounds;
    [surface sendSubviewToBack:view];
}
static void (*NGOriginalBackdropLayout)(id, SEL);
static void NGBackdropLayout(UIVisualEffectView *host, SEL cmd) {
    NGOriginalBackdropLayout(host, cmd);
    UIView *surface = NGSurface(host);
    if (!surface) return;
    NGApply(surface);
    if (!objc_getAssociatedObject(surface, NGImageKey)) return;
    host.effect = nil;
    host.backgroundColor = UIColor.clearColor;
    host.contentView.backgroundColor = UIColor.clearColor;
}
static void (*NGOriginalHostLayout)(id, SEL);
static void NGHostLayout(UIView *host, SEL cmd) {
    NGOriginalHostLayout(host, cmd);
    NGApply(host);
}
static void NGHook(Class cls, IMP implementation, IMP *original) {
    SEL sel = @selector(layoutSubviews);
    Method m = class_getInstanceMethod(cls, sel);
    if (!cls || !m || method_getNumberOfArguments(m) != 2) return;
    char *type = method_copyReturnType(m);
    BOOL valid = type && strcmp(type, "v") == 0;
    free(type);
    if (!valid) return;
    typedef void (*Hook)(Class, SEL, IMP, IMP *);
    Hook hook = (Hook)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (hook) hook(cls, sel, implementation, original);
}
__attribute__((constructor)) static void NGInstall(void) {
    @autoreleasepool {
        NGHook(NSClassFromString(@"UIInputSetHostView"), (IMP)NGHostLayout, (IMP *)&NGOriginalHostLayout);
        Class backdrop = NSClassFromString(@"UIKBBackdropView");
        if ([backdrop isSubclassOfClass:UIVisualEffectView.class])
            NGHook(backdrop, (IMP)NGBackdropLayout, (IMP *)&NGOriginalBackdropLayout);
    }
}
