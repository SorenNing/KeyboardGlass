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
static BOOL NGSharedQueued;
static UIView *NGKeyboardContainer(UIView *view) {
    Class cls = NSClassFromString(@"UIInputSetHostView");
    for (UIView *parent = view; parent; parent = parent.superview)
        if (cls && [parent isKindOfClass:cls]) return parent;
    return nil;
}
static void NGUpdateSharedBackgrounds(void) {
    NSArray<UIVisualEffectView *> *hosts = NGHosts.allObjects;
    NSMutableSet<UIView *> *done = [NSMutableSet set];
    for (UIVisualEffectView *host in hosts) {
        UIView *parent = NGKeyboardContainer(host);
        if (!parent || !parent.window || [done containsObject:parent]) continue;
        [done addObject:parent];
        if (CGRectIsEmpty(parent.bounds)) continue;
        UIImageView *shared = objc_getAssociatedObject(parent, NGSharedKey);
        if (!shared) {
            shared = [[UIImageView alloc] initWithImage:NGMaterial()];
            shared.userInteractionEnabled = NO;
            shared.isAccessibilityElement = NO;
            shared.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [parent insertSubview:shared atIndex:0];
            objc_setAssociatedObject(parent, NGSharedKey, shared, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        shared.frame = parent.bounds;
        shared.hidden = NO;
        for (UIVisualEffectView *member in hosts) {
            if (NGKeyboardContainer(member) != parent) continue;
            UIImageView *old = objc_getAssociatedObject(member, NGImageKey);
            if (old) old.hidden = YES;
        }
    }
}
static void NGScheduleSharedBackgrounds(void) {
    if (NGSharedQueued) return;
    NGSharedQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        NGSharedQueued = NO;
        NGUpdateSharedBackgrounds();
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
    view.hidden = NO;
    if (host.effect) host.effect = nil;
    host.backgroundColor = UIColor.clearColor;
    host.contentView.backgroundColor = UIColor.clearColor;
    NGScheduleSharedBackgrounds();
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
