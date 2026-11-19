#import "KeyboardSurface.h"
#import "KeyboardGeometry.h"
#import "CandidateAppearance.h"
#import <objc/runtime.h>
#import "Material.h"

static const void *NGRecordKey = &NGRecordKey;
static const void *NGStateKey = &NGStateKey;
static const void *NGAccessoryKey = &NGAccessoryKey;
static const void *NGScopeKey = &NGScopeKey;
@interface NGKeyboardScope : NSObject
@property(nonatomic,weak) UIView *host;
@end
@implementation NGKeyboardScope
@end
static id NGObjectGetter(id object, const char *name) {
    SEL sel = sel_registerName(name);
    Method method = class_getInstanceMethod(object_getClass(object),sel);
    if (!method || method_getNumberOfArguments(method) != 2) return nil;
    char *type = method_copyReturnType(method);
    BOOL valid = type && type[0] == '@';
    free(type);
    if (!valid) return nil;
    return ((id (*)(id,SEL))[object methodForSelector:sel])(object,sel);
}
static BOOL NGAccessoryAncestor(UIView *view) {
    for (UIView *p=view;p;p=p.superview) if ([objc_getAssociatedObject(p,NGAccessoryKey) boolValue]) return YES;
    return NO;
}
static UIView *NGKeyboardAnchor(UIView *view) {
    Class cls = NSClassFromString(@"UIInputSetHostView");
    for (UIView *p=view;p;p=p.superview) {
        NGKeyboardScope *scope = objc_getAssociatedObject(p,NGScopeKey);
        if (scope.host) return scope.host;
        if (cls && [p isKindOfClass:cls]) return p;
    }
    return view.window;
}
static UIImage *NGSurfaceMaterial(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [[NSData alloc] initWithBase64EncodedString:NGMaterialBase64 options:0];
        UIImage *raw = [UIImage imageWithData:data scale:2];
        image = [raw resizableImageWithCapInsets:UIEdgeInsetsMake(14,14,14,14) resizingMode:UIImageResizingModeStretch];
    });
    return image;
}
BOOL NGSurfaceMaterialAvailable(void) { return NGSurfaceMaterial() != nil; }

@class NGSurfaceState;
@interface NGSurfaceRecord : NSObject
@property(nonatomic,weak) UIView *host;
@property(nonatomic,weak) NGSurfaceState *state;
@property(nonatomic,assign) CGFloat nativeAlpha;
@property(nonatomic,assign) BOOL active;
@property(nonatomic,assign) BOOL geometryOnly;
- (void)hideNative;
- (void)restoreNative;
@end
@implementation NGSurfaceRecord
- (void)hideNative {
    UIView *host = self.host;
    if (!host) return;
    if (self.geometryOnly) { NGCandidateApply(host,YES); self.active=YES; return; }
    if (!self.active || host.alpha > 0.001) self.nativeAlpha = host.alpha;
    self.active = YES;
    // These exact background classes have no keycaps or candidate text. Hide
    // their corner/shadow images as well as their blur; effect=nil alone does
    // not remove those separate native edges.
    if (host.alpha != 0) host.alpha = 0;
}
- (void)restoreNative {
    UIView *host = self.host;
    if (!self.active) return;
    self.active = NO;
    if (self.geometryOnly) { NGCandidateApply(host,NO); return; }
    if (host && host.alpha == 0) host.alpha = self.nativeAlpha;
}
@end

@interface NGSurfaceState : NSObject
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,strong) NSHashTable<NGSurfaceRecord *> *records;
@property(nonatomic,strong) NSMutableDictionary<NSValue *,UIImageView *> *surfaces;
@property(nonatomic,assign) BOOL scheduled;
@property(nonatomic,assign) BOOL updating;
- (void)schedule;
- (void)update;
@end

static BOOL NGHostVisible(UIView *view, UIWindow *window) {
    if (!view || view.window != window || CGRectIsEmpty(view.bounds) || NGAccessoryAncestor(view)) return NO;
    Class arrow = NSClassFromString(@"TUICandidateArrowButton");
    for (UIView *v = view; v; v = v.superview) {
        if (arrow && [v isKindOfClass:arrow]) return NO;
        NGSurfaceRecord *record = objc_getAssociatedObject(v,NGRecordKey);
        if (v.hidden || (v.alpha < 0.01 && (!record.active || record.geometryOnly))) return NO;
    }
    CGRect frame = [view convertRect:view.bounds toView:window];
    return CGRectIntersectsRect(frame,window.bounds);
}
static BOOL NGAncestorContains(UIView *parent, UIView *child) {
    return parent == child || [child isDescendantOfView:parent];
}
static UIView *NGCommonContainer(NSArray<NGSurfaceRecord *> *records) {
    UIView *parent = records.firstObject.host.superview;
    while (parent) {
        BOOL common = YES;
        for (NGSurfaceRecord *record in records) {
            if (!NGAncestorContains(parent, record.host)) { common = NO; break; }
        }
        if (common) {
            BOOL insideHiddenBackground = NO;
            for (NGSurfaceRecord *record in records) {
                if (!record.geometryOnly && NGAncestorContains(record.host,parent)) { insideHiddenBackground=YES; break; }
            }
            if (!insideHiddenBackground) return parent;
        }
        parent = parent.superview;
    }
    return nil;
}
static void NGInsertUnderBackgrounds(UIImageView *image, UIView *parent, NSArray<NGSurfaceRecord *> *records) {
    NSUInteger index = parent.subviews.count;
    for (NGSurfaceRecord *record in records) {
        UIView *branch = record.host;
        while (branch && branch.superview != parent) branch = branch.superview;
        if (!branch) continue;
        NSUInteger position = [parent.subviews indexOfObjectIdenticalTo:branch];
        if (position != NSNotFound) index = MIN(index, position);
    }
    if (index >= parent.subviews.count) [parent addSubview:image];
    else [parent insertSubview:image atIndex:index];
}

@implementation NGSurfaceState
- (instancetype)init {
    if ((self = [super init])) {
        _records = [NSHashTable weakObjectsHashTable];
        _surfaces = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)schedule {
    if (self.scheduled || self.updating) return;
    self.scheduled = YES;
    __weak NGSurfaceState *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NGSurfaceState *state = weakSelf;
        state.scheduled = NO;
        [state update];
    });
}
- (void)update {
    UIWindow *window = self.window;
    UIImage *material = NGSurfaceMaterial();
    if (!window || !material || self.updating) return;
    self.updating = YES;
    NSArray<NGSurfaceRecord *> *all = self.records.allObjects;
    NSMutableArray<NGSurfaceRecord *> *visible = [NSMutableArray array];
    for (NGSurfaceRecord *r in all) {
        if (NGHostVisible(r.host, window)) [visible addObject:r];
        else [r restoreNative];
    }
    [visible sortUsingComparator:^NSComparisonResult(NGSurfaceRecord *a, NGSurfaceRecord *b) {
        uintptr_t x=(uintptr_t)(__bridge void *)a.host, y=(uintptr_t)(__bridge void *)b.host;
        return x<y ? NSOrderedAscending : (x>y ? NSOrderedDescending : NSOrderedSame);
    }];
    // Guard allocation: ordinary system keyboards have only a handful of
    // backdrop strips. Never allocate unbounded matrices from a view tree.
    NSUInteger n = visible.count;
    if (n > 64) {
        for (NGSurfaceRecord *r in all) [r restoreNative];
        for (UIImageView *surface in self.surfaces.allValues) [surface removeFromSuperview];
        [self.surfaces removeAllObjects];
        self.updating = NO;
        return;
    }
    NGSurfaceRect rects[64]; size_t groups[64]; uintptr_t scopes[64];
    for (NSUInteger i=0;i<n;i++) {
        CGRect f = [visible[i].host convertRect:visible[i].host.bounds toView:window];
        rects[i] = (NGSurfaceRect){f.origin.x,f.origin.y,f.size.width,f.size.height};
        scopes[i] = (uintptr_t)(__bridge void *)NGKeyboardAnchor(visible[i].host);
    }
    NGSurfaceGroups(rects,scopes,n,groups);
    NSMutableSet<NSValue *> *used = [NSMutableSet set];
    const NGSurfaceRect *rectData = rects;
    const size_t *groupData = groups;
    [UIView performWithoutAnimation:^{
        for (NSUInteger i=0;i<n;i++) {
            if (groupData[i] != i) continue;
            NGSurfaceRect combined = rectData[i];
            NSMutableArray<NGSurfaceRecord *> *members = [NSMutableArray array];
            for (NSUInteger j=0;j<n;j++) if (groupData[j] == i) {
                combined = NGSurfaceUnion(combined,rectData[j]);
                [members addObject:visible[j]];
            }
            BOOL hasBackground = NO;
            for (NGSurfaceRecord *r in members) if (!r.geometryOnly) hasBackground = YES;
            UIView *parent = NGCommonContainer(members);
            if (!hasBackground || !parent || !NGSurfaceValid(combined)) {
                for (NGSurfaceRecord *r in members) [r restoreNative];
                continue;
            }
            NSValue *key = [NSValue valueWithNonretainedObject:visible[i].host];
            [used addObject:key];
            UIImageView *surface = self.surfaces[key];
            if (!surface) {
                surface = [[UIImageView alloc] initWithImage:material];
                surface.userInteractionEnabled = NO;
                surface.isAccessibilityElement = NO;
                surface.accessibilityElementsHidden = YES;
                surface.opaque = NO;
                self.surfaces[key] = surface;
            }
            CGRect windowRect = CGRectMake(combined.x,combined.y,combined.w,combined.h);
            CGRect frame = [parent convertRect:windowRect fromView:window];
            if (surface.superview != parent) {
                [surface removeFromSuperview];
                NGInsertUnderBackgrounds(surface,parent,members);
            }
            if (!CGRectEqualToRect(surface.frame,frame)) surface.frame = frame;
            for (NGSurfaceRecord *r in members) [r hideNative];
        }
        for (NSValue *key in self.surfaces.allKeys) if (![used containsObject:key]) {
            [self.surfaces[key] removeFromSuperview];
            [self.surfaces removeObjectForKey:key];
        }
    }];
    self.updating = NO;
}
@end

void NGSurfaceRefresh(UIView *host) {
    if (![NSThread isMainThread]) return;
    NGSurfaceRecord *record = objc_getAssociatedObject(host, NGRecordKey);
    if (!record) {
        record = [NGSurfaceRecord new];
        record.host = host;
        objc_setAssociatedObject(host,NGRecordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIWindow *window = host.window;
    NGSurfaceState *previous = record.state;
    if (previous.window != window) {
        [record restoreNative];
        [previous.records removeObject:record];
        [previous schedule];
        record.state = nil;
    }
    if (!window) return;
    NGSurfaceState *state = objc_getAssociatedObject(window,NGStateKey);
    if (!state) {
        state = [NGSurfaceState new];
        state.window = window;
        objc_setAssociatedObject(window,NGStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    record.state = state;
    [state.records addObject:record];
    [state schedule];
}
void NGSurfaceWindowRefresh(UIView *view) {
    NGSurfaceState *state = objc_getAssociatedObject(view.window,NGStateKey);
    [state schedule];
}
void NGSurfaceCandidateRefresh(UIView *view) {
    NGSurfaceRefresh(view);
    NGSurfaceRecord *record = objc_getAssociatedObject(view,NGRecordKey);
    record.geometryOnly = YES;
    id backdrop = NGObjectGetter(view,"backdropView");
    if ([backdrop isKindOfClass:UIView.class]) {
        Class cls = NSClassFromString(@"UIKBBackdropView");
        if (cls && [backdrop isKindOfClass:cls]) NGSurfaceRefresh(backdrop);
        else {
            id inner = NGObjectGetter(backdrop,"backdropView");
            if (cls && [inner isKindOfClass:cls]) NGSurfaceRefresh(inner);
        }
    }
}
BOOL NGSurfaceHasCoverage(UIView *view) {
    NGSurfaceState *state = objc_getAssociatedObject(view.window,NGStateKey);
    if (!view.window || !state) return NO;
    CGRect rect = [view convertRect:view.bounds toView:view.window];
    for (UIImageView *surface in state.surfaces.allValues) {
        if (!surface.superview) continue;
        CGRect area = [surface convertRect:surface.bounds toView:view.window];
        if (CGRectContainsRect(CGRectInset(area,-1,-1),rect)) return YES;
    }
    return NO;
}
void NGSurfaceHostingRefresh(id item) {
    UIView *accessory = NGObjectGetter(item,"_inputAccessoryBackdropView");
    if ([accessory isKindOfClass:UIView.class]) {
        objc_setAssociatedObject(accessory,NGAccessoryKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *host = NGObjectGetter(item,"hostView");
    if ([host isKindOfClass:UIView.class]) {
        NGKeyboardScope *scope = [NGKeyboardScope new];
        scope.host = host;
        for (NSString *name in @[@"_inputBackdropView",@"_inputAssistantBackdropView",@"inputView",@"inputAssistantView"]) {
            UIView *view = NGObjectGetter(item,name.UTF8String);
            if ([view isKindOfClass:UIView.class]) objc_setAssociatedObject(view,NGScopeKey,scope,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NGSurfaceWindowRefresh(host);
    }
}
