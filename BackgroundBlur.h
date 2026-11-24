// Included after NGApplyBackdropOutline. This layer sits below our material,
// never above candidate labels or keycaps. No screenshots or App-window capture.
@interface NGBackgroundBlurState : NSObject
@property(nonatomic,strong) UIVisualEffectView *view;
@property(nonatomic,strong) UIViewPropertyAnimator *animator;
@property(nonatomic) CGFloat strength;
@property(nonatomic) BOOL dark;
@end
@implementation NGBackgroundBlurState
- (void)dealloc { [_animator stopAnimation:YES]; }
@end
static const void *NGBlurStateKey=&NGBlurStateKey;
static void NGApplyBackgroundBlur(UIVisualEffectView *host, CGRect joined, BOOL sharedArrow) {
    NGBackgroundBlurState *state=objc_getAssociatedObject(host,NGBlurStateKey);
    BOOL enabled=NGBlurEnabled && NGBlurStrength>0 && !sharedArrow;
    if (!enabled) {
        [state.animator stopAnimation:YES];
        state.animator=nil;
        state.view.effect=nil;
        [state.view removeFromSuperview];
        objc_setAssociatedObject(host,NGBlurStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    BOOL dark=host.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark;
    if (!state) {
        state=[NGBackgroundBlurState new];
        state.view=[[UIVisualEffectView alloc] initWithEffect:nil];
        state.view.userInteractionEnabled=NO;
        state.view.isAccessibilityElement=NO;
        state.strength=-1;
        [host.contentView insertSubview:state.view atIndex:0];
        objc_setAssociatedObject(host,NGBlurStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL reattached=state.view.superview!=host.contentView;
    if (reattached) [host.contentView insertSubview:state.view atIndex:0];
    // Actual effect interpolation, not view alpha: the glass tint and system
    // background opacity remain separate. UIKit does not expose a blur radius.
    if (reattached || state.strength!=NGBlurStrength || state.dark!=dark) {
        [state.animator stopAnimation:YES];
        state.animator=nil;
        state.view.effect=nil;
        UIVisualEffectView *view=state.view;
        UIBlurEffect *effect=[UIBlurEffect effectWithStyle:dark ? UIBlurEffectStyleDark : UIBlurEffectStyleLight];
        state.animator=[[UIViewPropertyAnimator alloc] initWithDuration:1 curve:UIViewAnimationCurveLinear animations:^{ view.effect=effect; }];
        state.animator.pausesOnCompletion=YES;
        [state.animator startAnimation];
        [state.animator pauseAnimation];
        state.animator.fractionComplete=NGBlurStrength;
        state.strength=NGBlurStrength; state.dark=dark;
    }
    state.view.frame=host.contentView.bounds;
    // Use the same joined outline crop as the glass and native background.
    // Blur also respects the unmodified original skin's outline.
    NGApplyBackdropOutline(state.view,joined,CGRectGetWidth(joined)>=200 && CGRectGetHeight(joined)>=100);
}
