#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "Material.h"

// Original 0.1.0 material. The only change in this file is joining the
// candidate/expanded backdrop with the keyboard backdrop as one surface.
static const void *NGImageKey = &NGImageKey;
static const void *NGMaskKey = &NGMaskKey;
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
static BOOL NGMergeQueued;
static BOOL NGMergeRunning;
static const void *NGClipKey = &NGClipKey;
static const void *NGArrowColorKey = &NGArrowColorKey;

static UIView *NGViewProperty(UIView *view, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    if (![view respondsToSelector:sel]) return nil;
    Method method = class_getInstanceMethod(view.class, sel);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char *type = method_copyReturnType(method);
    BOOL object = type && type[0] == '@';
    free(type);
    if (!object) return nil;
    id value = ((id (*)(id, SEL))[view methodForSelector:sel])(view, sel);
    return [value isKindOfClass:UIView.class] ? value : nil;
}

static void NGArrowBackground(UIView *arrow, BOOL joined) {
    if (!arrow) return;
    UIView *background = NGViewProperty(arrow, @"backgroundView");
    UIView *highlight = NGViewProperty(arrow, @"highlightBackgroundView");
    UIView *backdrop = NGViewProperty(arrow, @"backdropView");
    if (joined && backdrop && backdrop != arrow) {
        UIColor *clear = UIColor.clearColor;
        if (![backdrop.backgroundColor isEqual:clear]) backdrop.backgroundColor = clear;
        backdrop.layer.cornerRadius = 0;
        backdrop.clipsToBounds = NO;
    }
    if (!background || background == arrow || background == highlight || background == backdrop) return;
    id saved = objc_getAssociatedObject(background, NGArrowColorKey);
    if (joined) {
        UIColor *clear = UIColor.clearColor;
        if (![background.backgroundColor isEqual:clear]) {
            objc_setAssociatedObject(background, NGArrowColorKey, background.backgroundColor ?: NSNull.null,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            background.backgroundColor = clear;
        }
    } else if (saved) {
        background.backgroundColor = saved == NSNull.null ? nil : saved;
        objc_setAssociatedObject(background, NGArrowColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UIView *NGAncestor(UIView *view, NSString *className) {
    Class cls = NSClassFromString(className);
    if (!cls) return nil;
    for (UIView *current = view; current; current = current.superview) {
        if ([current isKindOfClass:cls]) return current;
    }
    return nil;
}

static UIView *NGScopeForHost(UIVisualEffectView *host) {
    return NGAncestor(host, @"UIInputSetHostView");
}

static BOOL NGVisible(UIView *view) {
    if (!view.window || CGRectIsEmpty(view.bounds)) return NO;
    for (UIView *current = view; current; current = current.superview) {
        if (current.hidden || current.alpha < 0.01) return NO;
    }
    return YES;
}

// The native base, arrow image, highlight, corner mask and button events are
// untouched. Only the 0.1.0 image layer is given shared coordinates.
static void NGClearNativeBackdrop(UIVisualEffectView *host) {
    if (host.effect) host.effect = nil;
    UIColor *clear = UIColor.clearColor;
    if (![host.backgroundColor isEqual:clear]) host.backgroundColor = clear;
    if (![host.contentView.backgroundColor isEqual:clear]) host.contentView.backgroundColor = clear;
}

static UIImageView *NGImageForHost(UIVisualEffectView *host) {
    UIImageView *view = objc_getAssociatedObject(host, NGImageKey);
    if (!view && NGMaterial()) {
        view = [[UIImageView alloc] initWithImage:NGMaterial()];
        view.userInteractionEnabled = NO;
        view.isAccessibilityElement = NO;
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host.contentView insertSubview:view atIndex:0];
        objc_setAssociatedObject(host, NGImageKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return view;
}

static void NGApplyStandalone(UIVisualEffectView *host) {
    UIView *clip = objc_getAssociatedObject(host, NGClipKey);
    if (clip && !clip.hidden) clip.hidden = YES;
    if (!host.window || CGRectIsEmpty(host.bounds)) return;
    UIImageView *view = NGImageForHost(host);
    if (!view) return;
    if (view.superview != host.contentView) [host.contentView insertSubview:view atIndex:0];
    if (view.hidden) view.hidden = NO;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    if (!CGRectEqualToRect(view.frame, host.contentView.bounds)) view.frame = host.contentView.bounds;
    NGClearNativeBackdrop(host);
}

static BOOL NGCandidateHost(UIVisualEffectView *host) {
    for (UIView *current = host; current; current = current.superview) {
        NSString *name = NSStringFromClass(current.class);
        if ([name containsString:@"Candidate"]) return YES;
    }
    return NO;
}

static void NGHideHostImage(UIVisualEffectView *host) {
    UIView *clip = objc_getAssociatedObject(host, NGClipKey);
    if (clip && !clip.hidden) clip.hidden = YES;
    UIImageView *view = objc_getAssociatedObject(host, NGImageKey);
    if (view && !view.hidden) view.hidden = YES;
}

static void NGOpenClipping(UIView *view, UIView *scope) {
    for (UIView *current = view; current && current != scope; current = current.superview) {
        if (current.clipsToBounds) current.clipsToBounds = NO;
        if (current.layer.masksToBounds) current.layer.masksToBounds = NO;
    }
}

static void NGHideCandidateChrome(UIVisualEffectView *host) {
    UIView *candidate = NGAncestor(host, @"TUICandidateView");
    UIView *backdrop = NGAncestor(host, @"TUICandidateBackdropView");
    if (backdrop) {
        UIColor *clear = UIColor.clearColor;
        if (![backdrop.backgroundColor isEqual:clear]) backdrop.backgroundColor = clear;
        backdrop.layer.cornerRadius = 0;
        backdrop.clipsToBounds = NO;
    }
    if (!candidate) return;
    id border = nil;
    if ([candidate respondsToSelector:NSSelectorFromString(@"roundedBorderLayer")]) {
        border = ((id (*)(id, SEL))[candidate methodForSelector:NSSelectorFromString(@"roundedBorderLayer")])
                 (candidate, NSSelectorFromString(@"roundedBorderLayer"));
    }
    if ([border isKindOfClass:CALayer.class] && ![border isHidden]) [border setHidden:YES];
}

static CGRect NGRegion(UIVisualEffectView *host, UIView *scope) {
    CGRect r = [host.contentView convertRect:host.contentView.bounds toView:scope];
    CGFloat scale = scope.window.screen.scale ?: 1;
    CGFloat x = round(CGRectGetMinX(r)*scale)/scale;
    CGFloat y = round(CGRectGetMinY(r)*scale)/scale;
    return CGRectMake(x, y, round(CGRectGetMaxX(r)*scale)/scale-x,
                      round(CGRectGetMaxY(r)*scale)/scale-y);
}

static BOOL NGKeyboardHost(UIVisualEffectView *host) {
    return NGAncestor(host, @"UIKeyboard") || NGAncestor(host, @"UIKeyboardImpl");
}

// Candidate bar, expand button and the keyboard below share one continuous
// surface. Its box is built from the real keyboard view, never from a
// full-screen backdrop, so nothing is stretched across the screen.
static void NGMergeScope(UIView *scope) {
    if (!scope || !scope.window || !NGMaterial()) return;
    NSMutableArray<UIVisualEffectView *> *members = [NSMutableArray array];
    NSMutableArray<UIVisualEffectView *> *joined = [NSMutableArray array];
    NSMutableArray<UIVisualEffectView *> *keyboards = [NSMutableArray array];
    NSMutableArray<UIVisualEffectView *> *candidates = [NSMutableArray array];
    for (UIVisualEffectView *host in NGHosts.allObjects) {
        if (NGScopeForHost(host) != scope) continue;
        [members addObject:host];
        if (!NGVisible(host)) continue;
        if (NGCandidateHost(host)) [candidates addObject:host];
        else if (NGKeyboardHost(host)) [keyboards addObject:host];
    }
    if (!keyboards.count) {
        for (UIVisualEffectView *host in members) {
            if ([candidates containsObject:host] || !NGVisible(host)) continue;
            [keyboards addObject:host];
        }
    }
    CGRect candidateArea = CGRectNull;
    for (UIVisualEffectView *host in candidates) candidateArea = CGRectUnion(candidateArea, NGRegion(host, scope));
    CGRect keyboardArea = CGRectNull;
    for (UIVisualEffectView *host in keyboards) {
        UIView *kb = NGAncestor(host, @"UIKeyboard") ?: NGAncestor(host, @"UIKeyboardImpl");
        CGRect r = kb ? [kb convertRect:kb.bounds toView:scope] : NGRegion(host, scope);
        keyboardArea = CGRectIsNull(keyboardArea) ? r : CGRectUnion(keyboardArea, r);
    }
    NSHashTable<UIView *> *joinedArrows = [NSHashTable weakObjectsHashTable];
    NSHashTable<UIView *> *plainArrows = [NSHashTable weakObjectsHashTable];
    UIVisualEffectView *owner = nil;
    if (!CGRectIsNull(candidateArea) && !CGRectIsNull(keyboardArea)) {
        CGFloat best = 0;
        for (UIVisualEffectView *host in keyboards) {
            CGRect r = NGRegion(host, scope);
            CGFloat area = r.size.width * r.size.height;
            if (!owner || area > best) { owner = host; best = area; }
        }
        [joined addObjectsFromArray:candidates];
        for (UIVisualEffectView *host in keyboards) {
            if (CGRectIntersectsRect(NGRegion(host, scope), keyboardArea)) [joined addObject:host];
        }
    }
    if (owner) {
        CGRect unionRect = CGRectUnion(candidateArea, keyboardArea);
        unionRect = CGRectIntersection(unionRect, scope.bounds);
        CGFloat pixel = 1/(scope.window.screen.scale ?: 1);
        unionRect = CGRectInset(unionRect, -pixel, -pixel);
        UIImageView *surface = NGImageForHost(owner);
        if (surface && !CGRectIsEmpty(unionRect)) {
            UIView *content = owner.contentView;
            content.clipsToBounds = NO;
            content.layer.masksToBounds = NO;
            owner.clipsToBounds = NO;
            owner.layer.masksToBounds = NO;
            NGOpenClipping(owner.superview, scope);
            if (surface.superview != content) [content insertSubview:surface atIndex:0];
            surface.autoresizingMask = UIViewAutoresizingNone;
            CGRect frame = [scope convertRect:unionRect toView:content];
            if (!CGRectEqualToRect(surface.frame, frame)) surface.frame = frame;
            if (surface.hidden) surface.hidden = NO;
            NGClearNativeBackdrop(owner);
            for (UIVisualEffectView *host in joined) {
                if (host != owner) { NGHideHostImage(host); NGClearNativeBackdrop(host); }
                if (NGCandidateHost(host)) NGHideCandidateChrome(host);
                UIView *arrow = NGAncestor(host, @"TUICandidateArrowButton");
                UIView *candidate = NGAncestor(host, @"TUICandidateView");
                if (!arrow && candidate) arrow = NGViewProperty(candidate, @"arrowButton");
                if (arrow) [joinedArrows addObject:arrow];
            }
        }
    }
    for (UIVisualEffectView *host in members) {
        if (owner && [joined containsObject:host]) continue;
        NGApplyStandalone(host);
        UIView *arrow = NGAncestor(host, @"TUICandidateArrowButton");
        UIView *candidate = NGAncestor(host, @"TUICandidateView");
        if (!arrow && candidate) arrow = NGViewProperty(candidate, @"arrowButton");
        if (arrow) [plainArrows addObject:arrow];
    }
    for (UIView *arrow in joinedArrows.allObjects) NGArrowBackground(arrow, YES);
    for (UIView *arrow in plainArrows.allObjects) NGArrowBackground(arrow, NO);
}

static void NGMergeAll(void) {
    NGMergeQueued = NO;
    if (!NGHosts) return;
    NSHashTable<UIView *> *scopes = [NSHashTable weakObjectsHashTable];
    for (UIVisualEffectView *host in NGHosts.allObjects) {
        UIView *scope = NGScopeForHost(host);
        if (scope) [scopes addObject:scope];
    }
    NGMergeRunning = YES;
    @try {
        for (UIView *scope in scopes.allObjects) NGMergeScope(scope);
    } @finally {
        NGMergeRunning = NO;
    }
}

static void NGScheduleMerge(void) {
    if (NGMergeQueued || NGMergeRunning) return;
    NGMergeQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        NGMergeAll();
    });
}

static void NGApply(UIVisualEffectView *host) {
    if (!NGHosts) NGHosts = [NSHashTable weakObjectsHashTable];
    [NGHosts addObject:host];
    if (NGScopeForHost(host)) {
        if (!objc_getAssociatedObject(host, NGClipKey)) NGApplyStandalone(host);
        else if (NGMaterial()) NGClearNativeBackdrop(host);
        NGScheduleMerge();
    } else {
        NGApplyStandalone(host);
    }
}

static void (*NGLayoutOriginal)(id, SEL);
static void NGLayout(id self, SEL cmd) {
    NGLayoutOriginal(self, cmd);
    NGApply((UIVisualEffectView *)self);
}

static void (*NGScopeLayoutOriginal)(id, SEL);
static void NGScopeLayout(id self, SEL cmd) {
    NGScopeLayoutOriginal(self, cmd);
    NGScheduleMerge();
}

static void (*NGCandidateLayoutOriginal)(id, SEL);
static void NGCandidateLayout(id self, SEL cmd) {
    NGCandidateLayoutOriginal(self, cmd);
    NGScheduleMerge();
}

static BOOL NGHasVoidMethod(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && strcmp(type, "v") == 0;
    free(type);
    return valid;
}

static void NGInstallOne(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls || !NGHasVoidMethod(cls, selector) || *original) return;
    typedef void (*Hook)(Class, SEL, IMP, IMP *);
    Hook hook = (Hook)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (hook) hook(cls, selector, replacement, original);
}

__attribute__((constructor)) static void NGInstall(void) {
    @autoreleasepool {
        Class backdrop = NSClassFromString(@"UIKBBackdropView");
        if (!backdrop || ![backdrop isSubclassOfClass:UIVisualEffectView.class]) return;
        NGInstallOne(backdrop, @selector(layoutSubviews), (IMP)NGLayout, (IMP *)&NGLayoutOriginal);
        NGInstallOne(NSClassFromString(@"UIInputSetHostView"), @selector(layoutSubviews),
                     (IMP)NGScopeLayout, (IMP *)&NGScopeLayoutOriginal);
        NGInstallOne(NSClassFromString(@"TUICandidateView"), @selector(layoutSubviews),
                     (IMP)NGCandidateLayout, (IMP *)&NGCandidateLayoutOriginal);
    }
}
