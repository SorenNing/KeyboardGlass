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
    return NGAncestor(host, @"TUICandidateView") ||
           NGAncestor(host, @"TUICandidateBackdropView") ||
           NGAncestor(host, @"TUICandidateArrowButton");
}

static BOOL NGKeyboardHost(UIVisualEffectView *host) {
    return NGAncestor(host, @"UIKeyboard") || NGAncestor(host, @"UIKeyboardImpl");
}

static BOOL NGAdjacent(CGRect a, CGRect b, CGFloat pixel) {
    return CGRectIntersectsRect(CGRectInset(a, -pixel, -pixel), b);
}

// Remove overlap rectangles, so translucent material is drawn once per pixel.
static NSArray<NSValue *> *NGSubtract(NSArray<NSValue *> *parts, CGRect cut) {
    NSMutableArray<NSValue *> *result = [NSMutableArray array];
    for (NSValue *value in parts) {
        CGRect r = value.CGRectValue;
        CGRect i = CGRectIntersection(r, cut);
        if (CGRectIsNull(i) || CGRectIsEmpty(i)) { [result addObject:value]; continue; }
        CGRect pieces[] = {
            CGRectMake(r.origin.x, r.origin.y, r.size.width, i.origin.y-r.origin.y),
            CGRectMake(r.origin.x, CGRectGetMaxY(i), r.size.width, CGRectGetMaxY(r)-CGRectGetMaxY(i)),
            CGRectMake(r.origin.x, i.origin.y, i.origin.x-r.origin.x, i.size.height),
            CGRectMake(CGRectGetMaxX(i), i.origin.y, CGRectGetMaxX(r)-CGRectGetMaxX(i), i.size.height)
        };
        for (NSUInteger n=0; n<4; ++n) {
            if (!CGRectIsEmpty(pieces[n])) [result addObject:[NSValue valueWithCGRect:pieces[n]]];
        }
    }
    return result;
}

static void NGApplyJoined(UIVisualEffectView *host, UIView *scope, CGRect joined,
                          NSArray<NSValue *> *parts) {
    UIImageView *image = NGImageForHost(host);
    if (!image) return;
    UIView *clip = objc_getAssociatedObject(host, NGClipKey);
    if (!clip) {
        clip = [[UIView alloc] initWithFrame:host.contentView.bounds];
        clip.userInteractionEnabled = NO;
        clip.isAccessibilityElement = NO;
        clip.clipsToBounds = YES;
        clip.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host.contentView insertSubview:clip atIndex:0];
        objc_setAssociatedObject(host, NGClipKey, clip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!CGRectEqualToRect(clip.frame, host.contentView.bounds)) clip.frame = host.contentView.bounds;
    if (clip.hidden) clip.hidden = NO;
    if (image.superview != clip) [clip addSubview:image];
    if (image.hidden) image.hidden = NO;
    image.autoresizingMask = UIViewAutoresizingNone;
    CGRect imageFrame = [scope convertRect:joined toView:clip];
    if (!CGRectEqualToRect(image.frame, imageFrame)) image.frame = imageFrame;
    CAShapeLayer *mask = objc_getAssociatedObject(host, NGMaskKey);
    if (!mask) {
        mask = [CAShapeLayer layer];
        objc_setAssociatedObject(host, NGMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSValue *part in parts) {
        [path appendPath:[UIBezierPath bezierPathWithRect:[scope convertRect:part.CGRectValue toView:clip]]];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!CGRectEqualToRect(mask.frame, clip.bounds)) mask.frame = clip.bounds;
    if (!mask.path || !CGPathEqualToPath(mask.path, path.CGPath)) mask.path = path.CGPath;
    if (clip.layer.mask != mask) clip.layer.mask = mask;
    [CATransaction commit];
    NGClearNativeBackdrop(host);
}

static CGRect NGRegion(UIVisualEffectView *host, UIView *scope) {
    CGRect r = [host.contentView convertRect:host.contentView.bounds toView:scope];
    CGFloat scale = scope.window.screen.scale ?: 1;
    CGFloat x = round(CGRectGetMinX(r)*scale)/scale;
    CGFloat y = round(CGRectGetMinY(r)*scale)/scale;
    return CGRectMake(x, y, round(CGRectGetMaxX(r)*scale)/scale-x,
                      round(CGRectGetMaxY(r)*scale)/scale-y);
}

static void NGMergeScope(UIView *scope) {
    if (!scope || !scope.window || !NGMaterial()) return;
    NSMutableArray<UIVisualEffectView *> *pending = [NSMutableArray array];
    NSMutableArray<UIVisualEffectView *> *members = [NSMutableArray array];
    NSHashTable<UIVisualEffectView *> *joinedHosts = [NSHashTable weakObjectsHashTable];
    for (UIVisualEffectView *host in NGHosts.allObjects) {
        if (NGScopeForHost(host) != scope) continue;
        [members addObject:host];
        if (NGVisible(host) && (NGCandidateHost(host) || NGKeyboardHost(host))) [pending addObject:host];
    }
    CGFloat pixel = 1/(scope.window.screen.scale ?: 1);
    while (pending.count) {
        NSMutableArray<UIVisualEffectView *> *group = [NSMutableArray arrayWithObject:pending.lastObject];
        [pending removeLastObject];
        for (NSUInteger index=0; index<group.count; ++index) {
            CGRect a = NGRegion(group[index], scope);
            for (NSInteger n=(NSInteger)pending.count-1; n>=0; --n) {
                if (NGAdjacent(a, NGRegion(pending[(NSUInteger)n], scope), pixel)) {
                    [group addObject:pending[(NSUInteger)n]];
                    [pending removeObjectAtIndex:(NSUInteger)n];
                }
            }
        }
        BOOL candidate = NO;
        CGRect joined = CGRectNull;
        for (UIVisualEffectView *host in group) {
            candidate |= NGCandidateHost(host);
            joined = CGRectUnion(joined, NGRegion(host, scope));
        }
        if (!candidate || group.count < 2) continue;
        // Let an enclosing backdrop own its full area first. Nested rounded
        // button backdrops then cannot cut holes into that continuous surface.
        [group sortUsingComparator:^NSComparisonResult(UIVisualEffectView *a, UIVisualEffectView *b) {
            CGRect ar = NGRegion(a, scope), br = NGRegion(b, scope);
            CGFloat aa=ar.size.width*ar.size.height, ba=br.size.width*br.size.height;
            return aa>ba ? NSOrderedAscending : (aa<ba ? NSOrderedDescending : NSOrderedSame);
        }];
        NSMutableArray<NSValue *> *covered = [NSMutableArray array];
        for (UIVisualEffectView *host in group) {
            CGRect region = NGRegion(host, scope);
            NSArray<NSValue *> *parts = @[[NSValue valueWithCGRect:region]];
            for (NSValue *cut in covered) parts = NGSubtract(parts, cut.CGRectValue);
            NGApplyJoined(host, scope, joined, parts);
            [joinedHosts addObject:host];
            [covered addObject:[NSValue valueWithCGRect:region]];
        }
    }
    NSHashTable<UIView *> *arrows = [NSHashTable weakObjectsHashTable];
    NSHashTable<UIView *> *joinedArrows = [NSHashTable weakObjectsHashTable];
    for (UIVisualEffectView *host in members) {
        BOOL isJoined = [joinedHosts containsObject:host];
        if (!isJoined) NGApplyStandalone(host);
        UIView *arrow = NGAncestor(host, @"TUICandidateArrowButton");
        UIView *candidate = NGAncestor(host, @"TUICandidateView");
        if (!arrow && candidate) arrow = NGViewProperty(candidate, @"arrowButton");
        if (arrow) {
            [arrows addObject:arrow];
            if (isJoined) [joinedArrows addObject:arrow];
        }
    }
    for (UIView *arrow in arrows.allObjects) NGArrowBackground(arrow, [joinedArrows containsObject:arrow]);
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
