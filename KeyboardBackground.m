#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "NGGlassMaterial.h"
#import "NGPreferences.h"

static const void *NGImageKey = &NGImageKey;
// Keep the first-version background placement and native base-layer handling.
// Both Glassify modes share one coordinate space across adjoining strips.
static NSHashTable<UIVisualEffectView *> *NGHosts;
static BOOL NGQueued;
@interface UIView (NGKeyboardBackgroundAccessors)
- (BOOL)showsBackground;
- (void)setShowsBackground:(BOOL)value;
- (UIView *)backgroundView;
- (UIView *)backdropView;
- (UIView *)highlightBackgroundView;
- (UIView *)arrowButton;
- (UIImage *)imageForCorners;
- (void)setImageForCorners:(UIImage *)image;
@end
static UIView *NGAncestor(UIView *view, NSString *name) {
    Class cls=NSClassFromString(name);
    for (UIView *v=view; v; v=v.superview) if (cls && [v isKindOfClass:cls]) return v;
    return nil;
}
static BOOL NGVisible(UIView *view) {
    if (!view.window || CGRectIsEmpty(view.bounds)) return NO;
    for (UIView *v=view;v;v=v.superview) if (v.hidden || v.alpha<0.01) return NO;
    return YES;
}
static BOOL NGAdjacent(CGRect a, CGRect b) {
    CGFloat overlap=MIN(CGRectGetMaxX(a),CGRectGetMaxX(b))-MAX(CGRectGetMinX(a),CGRectGetMinX(b));
    CGFloat gap=MAX(CGRectGetMinY(a),CGRectGetMinY(b))-MIN(CGRectGetMaxY(a),CGRectGetMaxY(b));
    return overlap>=MIN(a.size.width,b.size.width)*0.8 && gap<=4;
}
static void NGArrow(UIView *view) {
    if (![view isKindOfClass:NSClassFromString(@"TUICandidateArrowButton")] || !NGGlassAvailable()) return;
    static const void *busyKey=&busyKey;
    if ([objc_getAssociatedObject(view,busyKey) boolValue]) return;
    objc_setAssociatedObject(view,busyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIButton *button=(UIButton *)view;
    if ([view respondsToSelector:@selector(showsBackground)] && [view showsBackground]) [view setShowsBackground:NO];
    view.backgroundColor=UIColor.clearColor;
    for (NSNumber *state in @[@(UIControlStateNormal),@(UIControlStateHighlighted),@(UIControlStateSelected),@(UIControlStateDisabled)]) {
        if ([button backgroundImageForState:state.unsignedIntegerValue]) [button setBackgroundImage:nil forState:state.unsignedIntegerValue];
    }
    // Named backing views only; never change the button or its glyph.
    for (NSString *name in @[@"backgroundView",@"backdropView",@"highlightBackgroundView"]) {
        SEL sel=NSSelectorFromString(name);
        if (![view respondsToSelector:sel]) continue;
        UIView *bg=((UIView *(*)(id,SEL))[view methodForSelector:sel])(view,sel);
        if (![bg isKindOfClass:UIView.class] || bg==view || bg==button.imageView || [button.imageView isDescendantOfView:bg]) continue;
        bg.hidden=YES;
    }
    objc_setAssociatedObject(view,busyKey,@NO,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static CGRect NGRegion(UIVisualEffectView *host) {
    UIView *candidate=NGAncestor(host,@"TUICandidateView");
    return candidate ? [candidate convertRect:candidate.bounds toView:host.window] : [host convertRect:host.bounds toView:host.window];
}
static void NGJoin(void) {
    NSArray<UIVisualEffectView *> *hosts=NGHosts.allObjects;
    if (hosts.count>32) return;
    for (UIVisualEffectView *host in hosts) {
        UIView *image=objc_getAssociatedObject(host,NGImageKey);
        image.hidden=!NGVisible(host);
        if (image.hidden) { NGGlassPause(image); continue; }
        UIView *scope=NGAncestor(host,@"UIInputSetHostView") ?: host.window;
        CGRect area=NGRegion(host);
        BOOL joined=NO;
        // Fixed-point union of only adjacent keyboard backdrop strips.
        for (NSUInteger pass=0;pass<hosts.count;pass++) {
            CGRect before=area;
            for (UIVisualEffectView *other in hosts) {
                if (!NGVisible(other) || other.window!=host.window) continue;
                UIView *otherScope=NGAncestor(other,@"UIInputSetHostView") ?: other.window;
                CGRect r=NGRegion(other);
                if (otherScope==scope && NGAdjacent(area,r)) {
                    area=CGRectUnion(area,r);
                    if (other!=host) joined=YES;
                }
            }
            if (CGRectEqualToRect(area,before)) break;
        }
        [UIView performWithoutAnimation:^{
            CGRect frame=[host.contentView convertRect:area fromView:host.window];
            if (!CGRectEqualToRect(image.frame,frame)) image.frame=frame;
            host.contentView.clipsToBounds=YES;
            // The original image supplies the outside corners. Native corner
            // images between joined strips must not draw a second inner edge.
            if (joined && [host respondsToSelector:@selector(imageForCorners)] && [host imageForCorners]) [host setImageForCorners:nil];
        }];
        NGGlassUpdate(image,host,NO);
        UIView *candidate=NGAncestor(host,@"TUICandidateView");
        if ([candidate respondsToSelector:@selector(arrowButton)]) NGArrow([candidate arrowButton]);
    }
}
static void NGScheduleJoin(void) {
    if (NGQueued) return;
    NGQueued=YES;
    dispatch_async(dispatch_get_main_queue(), ^{ NGJoin(); NGQueued=NO; });
}
static void NGApply(UIVisualEffectView *host) {
    UIView *arrow=NGAncestor(host,@"TUICandidateArrowButton");
    if (arrow) { NGArrow(arrow); return; }
    if (!host.window || CGRectIsEmpty(host.bounds)) { NGScheduleJoin(); return; }
    if (!NGGlassAvailable()) return;
    UIView *view=objc_getAssociatedObject(host,NGImageKey);
    if (!view) {
        view=NGGlassMake();
        view.userInteractionEnabled=NO;
        view.isAccessibilityElement=NO;
        view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [host.contentView insertSubview:view atIndex:0];
        objc_setAssociatedObject(host,NGImageKey,view,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.frame=host.contentView.bounds;
    }
    if (!NGHosts) NGHosts=[NSHashTable weakObjectsHashTable];
    [NGHosts addObject:host];
    // Exactly the first version's base-layer treatment. Do not hide the host,
    // UIKBBackgroundView or other native keyboard fills.
    if (host.effect) host.effect=nil;
    host.backgroundColor=UIColor.clearColor;
    host.contentView.backgroundColor=UIColor.clearColor;
    NGScheduleJoin();
}
#define NG_ZERO_HOOK(NAME,ACTION) \
static void (*NAME##Original)(id,SEL); \
static void NAME(id self,SEL cmd) { NAME##Original(self,cmd); ACTION; }
NG_ZERO_HOOK(NGLayout,NGApply(self))
NG_ZERO_HOOK(NGWindow,NGApply(self))
NG_ZERO_HOOK(NGArrowLayout,NGArrow(self))
NG_ZERO_HOOK(NGArrowStyle,NGArrow(self))
NG_ZERO_HOOK(NGArrowColor,NGArrow(self))
#undef NG_ZERO_HOOK
static BOOL NGHasVoidMethod(Class cls, SEL selector) {
    Method m=class_getInstanceMethod(cls,selector);
    if (!m || method_getNumberOfArguments(m)!=2) return NO;
    char *type=method_copyReturnType(m);
    BOOL ok=type && strcmp(type,"v")==0;
    free(type);
    return ok;
}
static void NGInstallOne(Class cls, SEL sel, IMP replacement, IMP *original) {
    if (!cls || !NGHasVoidMethod(cls,sel) || *original) return;
    typedef void (*Hook)(Class,SEL,IMP,IMP *);
    Hook hook=(Hook)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
    if (hook) hook(cls,sel,replacement,original);
}
static void NGInstallAvailable(void) {
    Class backdrop=NSClassFromString(@"UIKBBackdropView");
    if (backdrop && [backdrop isSubclassOfClass:UIVisualEffectView.class]) {
        NGInstallOne(backdrop,@selector(layoutSubviews),(IMP)NGLayout,(IMP *)&NGLayoutOriginal);
        NGInstallOne(backdrop,@selector(didMoveToWindow),(IMP)NGWindow,(IMP *)&NGWindowOriginal);
    }
    Class arrow=NSClassFromString(@"TUICandidateArrowButton");
    if (arrow && [arrow isSubclassOfClass:UIButton.class]) {
        NGInstallOne(arrow,@selector(layoutSubviews),(IMP)NGArrowLayout,(IMP *)&NGArrowLayoutOriginal);
        NGInstallOne(arrow,NSSelectorFromString(@"updateStyle"),(IMP)NGArrowStyle,(IMP *)&NGArrowStyleOriginal);
        NGInstallOne(arrow,NSSelectorFromString(@"udpateBackgroundColor"),(IMP)NGArrowColor,(IMP *)&NGArrowColorOriginal);
    }
}
static void NGModeChanged(void) {
    for (UIVisualEffectView *host in NGHosts.allObjects) {
        UIView *material=objc_getAssociatedObject(host,NGImageKey);
        NGGlassPause(material);
    }
    NGScheduleJoin();
}
__attribute__((constructor)) static void NGInstall(void) {
    @autoreleasepool {
        NGKeyboardPreferencesObserve(NGModeChanged);
        NGInstallAvailable();
        [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { NGInstallAvailable(); }];
    }
}
