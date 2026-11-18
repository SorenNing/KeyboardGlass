#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "Material.h"

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
static NSHashTable<UIVisualEffectView *> *NGHosts;
static const void *NGSharedKey = &NGSharedKey;
static BOOL NGUpdatePending;

static UIView *NGKeyboardHost(UIView *view) {
    Class cls = NSClassFromString(@"UIInputSetHostView");
    for (UIView *parent = view; parent; parent = parent.superview) {
        if (cls && [parent isKindOfClass:cls]) return parent;
    }
    return nil;
}

static void NGUpdateShared(void) {
    NSArray<UIVisualEffectView *> *hosts = NGHosts.allObjects;
    NSMutableSet<UIView *> *used = [NSMutableSet set];
    for (UIVisualEffectView *host in hosts) {
        UIView *parent = NGKeyboardHost(host);
        if (!parent || !parent.window || [used containsObject:parent]) continue;
        [used addObject:parent];
        // Only keyboard-sized input hosts may own a shared background. Other
        // views retain the original 0.1.0 per-backdrop image without changes.
        CGRect bounds = parent.bounds;
        if (bounds.size.width < 200 || bounds.size.height < 120 || bounds.size.height > 650) continue;
        UIImageView *shared = objc_getAssociatedObject(parent, NGSharedKey);
        if (!shared) {
            shared = [[UIImageView alloc] initWithImage:NGMaterial()];
            shared.userInteractionEnabled = NO;
            shared.isAccessibilityElement = NO;
            shared.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [parent insertSubview:shared atIndex:0];
            objc_setAssociatedObject(parent, NGSharedKey, shared, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        shared.frame = bounds;
        shared.hidden = NO;
        for (UIVisualEffectView *member in hosts) {
            if (NGKeyboardHost(member) != parent) continue;
            UIImageView *old = objc_getAssociatedObject(member, NGImageKey);
            old.hidden = YES;
        }
    }
}

static void NGScheduleShared(void) {
    if (NGUpdatePending) return;
    NGUpdatePending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        NGUpdatePending = NO;
        NGUpdateShared();
    });
}

static void NGApply(UIVisualEffectView *host) {
    if (!host.window || CGRectIsEmpty(host.bounds)) return;
    UIImage *material = NGMaterial();
    if (!material) return; // Do not remove native background if asset fails.
    UIImageView *view = objc_getAssociatedObject(host, NGImageKey);
    if (!view) {
        view = [[UIImageView alloc] initWithImage:material];
        view.userInteractionEnabled = NO;
        view.isAccessibilityElement = NO;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host.contentView insertSubview:view atIndex:0];
        objc_setAssociatedObject(host, NGImageKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    view.frame = host.contentView.bounds;
    if (!NGHosts) NGHosts = [NSHashTable weakObjectsHashTable];
    [NGHosts addObject:host];
    // Restore the original image until the shared backing is actually ready.
    view.hidden = NO;
    if (host.effect) host.effect = nil;
    host.backgroundColor = UIColor.clearColor;
    host.contentView.backgroundColor = UIColor.clearColor;
    NGScheduleShared();
}
static void (*NGOriginalLayout)(id,SEL);
static void NGLayout(id self, SEL cmd) {
    NGOriginalLayout(self,cmd);
    NGApply(self);
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
