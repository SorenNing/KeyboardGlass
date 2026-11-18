#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "NGGlassMaterial.h"

static const void *NGGlassKey = &NGGlassKey;
static const void *NGContainerKey = &NGContainerKey;
static const void *NGHiddenBackgroundsKey = &NGHiddenBackgroundsKey;
static const void *NGOriginalBackgroundAlphaKey = &NGOriginalBackgroundAlphaKey;
@interface NGKeyboardOwner : NSObject
@property(nonatomic,weak) UIView *container;
@end
@implementation NGKeyboardOwner @end
static NSHashTable<UIVisualEffectView *> *NGHosts;
static BOOL NGQueued;

static void NGHideOnlyBackgrounds(UIView *container) {
    NSHashTable<UIView *> *hidden=objc_getAssociatedObject(container,NGHiddenBackgroundsKey);
    if (!hidden) {
        hidden=[NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(container,NGHiddenBackgroundsKey,hidden,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSMutableArray<UIView *> *pending=[NSMutableArray arrayWithObject:container];
    Class backdrop=NSClassFromString(@"UIKBBackdropView");
    Class bitmap=NSClassFromString(@"UIKBBackgroundView");
    Class inputBackdrop=NSClassFromString(@"UIKBInputBackdropView");
    (void)inputBackdrop; // Do not hide a wrapper that may own controls.
    while (pending.count) {
        UIView *view=pending.lastObject;
        [pending removeLastObject];
        for (UIView *child in view.subviews) {
            if ([child isKindOfClass:NSClassFromString(@"NGKeyboardGlassView")]) continue;
            if ((backdrop && [child isKindOfClass:backdrop]) ||
                (bitmap && [child isKindOfClass:bitmap])) {
                if (child.subviews.count) {
                    [pending addObjectsFromArray:child.subviews];
                    continue;
                }
                if (!objc_getAssociatedObject(child,NGOriginalBackgroundAlphaKey))
                    objc_setAssociatedObject(child,NGOriginalBackgroundAlphaKey,@(child.alpha),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [hidden addObject:child];
                child.alpha=0;
            } else if (![child isKindOfClass:UIControl.class]) {
                [pending addObject:child];
            }
        }
    }
}
static void NGRestoreBackgrounds(UIView *container) {
    NSHashTable<UIView *> *hidden=objc_getAssociatedObject(container,NGHiddenBackgroundsKey);
    for (UIView *view in hidden.allObjects) {
        NSNumber *saved=objc_getAssociatedObject(view,NGOriginalBackgroundAlphaKey);
        if (saved) view.alpha=saved.doubleValue;
        objc_setAssociatedObject(view,NGOriginalBackgroundAlphaKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [hidden removeAllObjects];
}

static UIView *NGKeyboardContainer(UIView *view) {
    Class cls = NSClassFromString(@"UIInputSetHostView");
    for (UIView *v=view;v;v=v.superview) if (cls && [v isKindOfClass:cls]) return v;
    return nil;
}
static void NGRestore(UIVisualEffectView *host) {
    NGKeyboardOwner *owner=objc_getAssociatedObject(host,NGContainerKey);
    UIView *container=owner.container ?: NGKeyboardContainer(host);
    UIView *glass=objc_getAssociatedObject(container,NGGlassKey);
    if (glass) { NGGlassPause(glass); [glass removeFromSuperview]; objc_setAssociatedObject(container,NGGlassKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NGRestoreBackgrounds(container);
    if (host) objc_setAssociatedObject(host,NGContainerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void NGRefresh(void) {
    NGQueued=NO;
    NSMutableSet<UIView *> *seen=[NSMutableSet set];
    for (UIVisualEffectView *host in NGHosts.allObjects) {
        UIView *container=NGKeyboardContainer(host);
        if (!container || !container.window || CGRectIsEmpty(container.bounds)) { NGRestore(host); continue; }
        if ([seen containsObject:container]) continue;
        [seen addObject:container];
        UIVisualEffectView *primary=host;
        CGFloat primaryArea=0;
        for (UIVisualEffectView *member in NGHosts.allObjects) {
            if (NGKeyboardContainer(member)!=container) continue;
            NGKeyboardOwner *owner=objc_getAssociatedObject(member,NGContainerKey);
            if (!owner) { owner=[NGKeyboardOwner new]; objc_setAssociatedObject(member,NGContainerKey,owner,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            owner.container=container;
            CGRect memberRect=[member convertRect:member.bounds toView:container];
            CGFloat area=CGRectGetWidth(memberRect)*CGRectGetHeight(memberRect);
            if (area>primaryArea) { primaryArea=area; primary=member; }
        }
        UIVisualEffectView *selected=primary;
        // Only a confirmed keyboard-backdrop branch can be replaced. The
        // sibling above it remains below UIKit's later key/candidate siblings.
        UIView *branch=selected;
        while (branch.superview && branch.superview!=container) branch=branch.superview;
        Class wrapper=NSClassFromString(@"UIKBInputBackdropView");
        Class backdrop=NSClassFromString(@"UIKBBackdropView");
        if (branch.superview!=container ||
            !((wrapper && [branch isKindOfClass:wrapper]) ||
              (backdrop && [branch isKindOfClass:backdrop]))) continue;
        UIView *glass=objc_getAssociatedObject(container,NGGlassKey);
        if (!glass) {
            glass=NGGlassMake();
            if (!glass) continue;
            glass.userInteractionEnabled=NO;
            glass.isAccessibilityElement=NO;
            [container insertSubview:glass aboveSubview:branch];
            objc_setAssociatedObject(container,NGGlassKey,glass,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        glass.frame=container.bounds;
        __weak UIView *weakContainer=container;
        __weak UIView *weakGlass=glass;
        if (!NGGlassUpdate(glass,selected,^{
            UIView *current=weakContainer;
            if (!current.window || objc_getAssociatedObject(current,NGGlassKey)!=weakGlass) return;
            NGHideOnlyBackgrounds(current);
        })) NGRestore(host);
    }
}
static void NGSchedule(void) {
    if (NGQueued) return;
    NGQueued=YES;
    dispatch_async(dispatch_get_main_queue(),^{ NGRefresh(); });
}
static void (*NGOriginalLayout)(id,SEL);
static void NGLayout(id self,SEL cmd) {
    NGOriginalLayout(self,cmd);
    if (!NGHosts) NGHosts=[NSHashTable weakObjectsHashTable];
    [NGHosts addObject:(UIVisualEffectView *)self];
    NGSchedule();
}
static void (*NGOriginalWindow)(id,SEL);
static void NGWindow(id self,SEL cmd) {
    NGOriginalWindow(self,cmd);
    if (((UIView *)self).window) {
        if (!NGHosts) NGHosts=[NSHashTable weakObjectsHashTable];
        [NGHosts addObject:(UIVisualEffectView *)self];
    } else NGRestore(self);
    NGSchedule();
}
static BOOL NGVoidZero(Class cls,SEL sel) {
    Method method=class_getInstanceMethod(cls,sel);
    if (!method || method_getNumberOfArguments(method)!=2) return NO;
    char *type=method_copyReturnType(method);
    BOOL ok=type && type[0]=='v';free(type);return ok;
}
static BOOL NGInstalledLayout, NGInstalledWindow;
static void NGInstallHooks(void) {
    Class cls=NSClassFromString(@"UIKBBackdropView");
    typedef void (*Hook)(Class,SEL,IMP,IMP *);
    Hook hook=(Hook)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
    if (!cls || !hook || ![cls isSubclassOfClass:UIVisualEffectView.class]) return;
    if (!NGHosts) NGHosts=[NSHashTable weakObjectsHashTable];
    if (!NGInstalledLayout && NGVoidZero(cls,@selector(layoutSubviews))) {
        NGInstalledLayout=YES;
        hook(cls,@selector(layoutSubviews),(IMP)NGLayout,(IMP *)&NGOriginalLayout);
    }
    if (!NGInstalledWindow && NGVoidZero(cls,@selector(didMoveToWindow))) {
        NGInstalledWindow=YES;
        hook(cls,@selector(didMoveToWindow),(IMP)NGWindow,(IMP *)&NGOriginalWindow);
    }
}
__attribute__((constructor)) static void NGInstall(void) {
    @autoreleasepool {
        NGInstallHooks();
        [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { NGInstallHooks(); }];
    }
}
