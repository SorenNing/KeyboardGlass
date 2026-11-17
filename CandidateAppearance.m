#import "CandidateAppearance.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static const void *NGCandidateSnapshotKey = &NGCandidateSnapshotKey;
static id NGGetObject(id object, const char *name) {
    SEL sel = sel_registerName(name);
    Method m = class_getInstanceMethod(object_getClass(object),sel);
    if (!m || method_getNumberOfArguments(m) != 2) return nil;
    char *type = method_copyReturnType(m);
    BOOL valid = type && type[0]=='@';
    free(type);
    if (!valid) return nil;
    return ((id (*)(id,SEL))[object methodForSelector:sel])(object,sel);
}
static BOOL NGIsClass(id view, NSString *name) {
    Class cls = NSClassFromString(name);
    return cls && [view isKindOfClass:cls];
}
@interface NGCandidateSnapshot : NSObject
@property(nonatomic,strong) NSMapTable<UIView *,NSNumber *> *hidden;
@property(nonatomic,strong) NSMapTable<UIView *,UIColor *> *colors;
@property(nonatomic,strong) NSMapTable<CALayer *,NSNumber *> *layers;
- (void)hide:(id)view;
- (void)clear:(UIView *)view;
- (void)restore;
@end
@implementation NGCandidateSnapshot
- (instancetype)init {
    if ((self=[super init])) {
        _hidden = [NSMapTable weakToStrongObjectsMapTable];
        _colors = [NSMapTable weakToStrongObjectsMapTable];
        _layers = [NSMapTable weakToStrongObjectsMapTable];
    }
    return self;
}
- (void)hide:(id)view {
    if (![view isKindOfClass:UIView.class] || [view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class]) return;
    UIView *v = view;
    if (![self.hidden objectForKey:v]) [self.hidden setObject:@(v.hidden) forKey:v];
    if (!v.hidden) v.hidden = YES;
}
- (void)clear:(UIView *)view {
    if (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor)>0) {
        [self.colors setObject:view.backgroundColor forKey:view];
        view.backgroundColor = UIColor.clearColor;
    }
}
- (void)restore {
    for (UIView *v in self.hidden.keyEnumerator) v.hidden = [[self.hidden objectForKey:v] boolValue];
    for (UIView *v in self.colors.keyEnumerator) v.backgroundColor = [self.colors objectForKey:v];
    for (CALayer *layer in self.layers.keyEnumerator) layer.hidden = [[self.layers objectForKey:layer] boolValue];
    [self.hidden removeAllObjects]; [self.colors removeAllObjects]; [self.layers removeAllObjects];
}
@end
// Only these private views own candidate chrome; never walk the whole keyboard.
void NGCandidateApply(UIView *view, BOOL active) {
    if (!view) return;
    // The merged surface is inserted after the initial child layout. Apply
    // arrow/mask cleanup here as well so the first visible frame is covered.
    if (NGIsClass(view,@"TUICandidateView")) {
        UIView *arrow = NGGetObject(view,"arrowButton");
        UIView *mask = NGGetObject(view,"maskView");
        if (arrow!=view && NGIsClass(arrow,@"TUICandidateArrowButton")) NGCandidateApply(arrow,active);
        if (mask!=view && NGIsClass(mask,@"TUICandidateMask")) NGCandidateApply(mask,active);
    }
    NGCandidateSnapshot *snapshot = objc_getAssociatedObject(view,NGCandidateSnapshotKey);
    if (!active) { [snapshot restore]; return; }
    if (!snapshot) {
        snapshot = [NGCandidateSnapshot new];
        objc_setAssociatedObject(view,NGCandidateSnapshotKey,snapshot,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [snapshot clear:view];
    if (NGIsClass(view,@"TUICandidateArrowButton")) {
        // These accessors name background-only views. Keep UIButton.imageView,
        // contentView, highlight feedback, targets and hit testing untouched.
        UIView *glyph = NGGetObject(view,"imageView");
        UIView *content = NGGetObject(view,"contentView");
        for (NSString *name in @[@"backgroundView",@"backdropView"]) {
            UIView *bg = NGGetObject(view,name.UTF8String);
            if (![bg isKindOfClass:UIView.class] || bg==view || bg==glyph || bg==content) continue;
            if ([glyph isDescendantOfView:bg] || [content isDescendantOfView:bg]) continue;
            [snapshot hide:bg];
        }
        // Some keyboard styles have a separate thin leading hairline. Restrict
        // this geometry check to direct noninteractive arrow decorations.
        for (UIView *child in view.subviews) {
            if (child==glyph || child==content || child.userInteractionEnabled) continue;
            CGRect f=child.frame;
            if (CGRectGetWidth(f)>0 && CGRectGetWidth(f)<=3 && CGRectGetHeight(f)>=12 && fabs(CGRectGetMinX(f)-CGRectGetMinX(view.bounds))<=4) [snapshot hide:child];
        }
    } else if (NGIsClass(view,@"TUICandidateView")) {
        id border = NGGetObject(view,"roundedBorderLayer");
        if ([border isKindOfClass:CAShapeLayer.class]) {
            CALayer *layer = border;
            if (![snapshot.layers objectForKey:layer]) [snapshot.layers setObject:@(layer.hidden) forKey:layer];
            if (!layer.hidden) layer.hidden = YES;
        }
    } else if (NGIsClass(view,@"TUICandidateMask")) {
        UIView *rightEdge = NGGetObject(view,"rightEdgeImageView");
        if ([rightEdge isKindOfClass:UIView.class] && rightEdge.bounds.size.width<=3 && rightEdge.bounds.size.height>=12) [snapshot hide:rightEdge];
    }
}
