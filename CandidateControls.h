// Included after preference state and NGArrowHasSharedBackground declarations.
// Only candidate controls are touched; no UILabel, keycap or backdrop is hidden.
@interface NGControlVisibilityState : NSObject
@property(nonatomic,weak) UIView *view;
@property(nonatomic) BOOL hidden;
@property(nonatomic) BOOL interactive;
@end
@implementation NGControlVisibilityState
@end
static NSMapTable<UIView *, NGControlVisibilityState *> *NGControlStates;
static NSHashTable<UIView *> *NGCandidateContainers;
static BOOL NGUpdatingControls;
static void NGRestoreCandidateControls(UIView *scope) {
    for (UIView *view in NGControlStates.keyEnumerator.allObjects) {
        if (scope && view!=scope && ![view isDescendantOfView:scope]) continue;
        NGControlVisibilityState *state=[NGControlStates objectForKey:view];
        view.hidden=state.hidden;
        view.userInteractionEnabled=state.interactive;
        [NGControlStates removeObjectForKey:view];
    }
}
static void NGSaveControl(UIView *view, BOOL hide) {
    if (!NGControlStates) NGControlStates=[NSMapTable weakToStrongObjectsMapTable];
    if (![NGControlStates objectForKey:view]) {
        NGControlVisibilityState *state=[NGControlVisibilityState new];
        state.view=view; state.hidden=view.hidden; state.interactive=view.userInteractionEnabled;
        [NGControlStates setObject:state forKey:view];
    }
    if (hide) view.hidden=YES;
    else view.userInteractionEnabled=NO;
}
static BOOL NGIsCandidateLine(UIView *view) {
    Class cls=NSClassFromString(@"TUICandidateLine");
    return cls && [view isKindOfClass:cls] && view.bounds.size.width<=3 &&
        view.bounds.size.width>0 && view.bounds.size.height>=20 && view.bounds.size.height<=80;
}
static void NGApplyArrowControls(UIView *arrow) {
    if (!arrow.window || arrow.bounds.size.width>80 || arrow.bounds.size.height>80) return;
    // The observed arrow glyph and its separator are direct children. Leave
    // the background and pressed-state branches entirely intact.
    for (UIView *child in arrow.subviews) {
        if ([child isKindOfClass:UIImageView.class] || NGIsCandidateLine(child)) NGSaveControl(child,YES);
    }
    // Some keyboards put the same separator alongside, rather than inside, the button.
    CGRect target=[arrow convertRect:arrow.bounds toView:arrow.window];
    for (UIView *child in arrow.superview.subviews) {
        if (!NGIsCandidateLine(child)) continue;
        CGRect r=[child convertRect:child.bounds toView:arrow.window];
        if (fabs(CGRectGetMaxX(r)-CGRectGetMinX(target))<=3 &&
            fabs(CGRectGetMinY(r)-CGRectGetMinY(target))<=1 &&
            fabs(r.size.height-target.size.height)<=1) NGSaveControl(child,YES);
    }
    NGSaveControl(arrow,NO); // No invisible hit target; do not reclaim its layout slot.
}
static void NGVisitCandidateControls(UIView *view, NSUInteger depth) {
    if (depth>12) return;
    Class arrow=NSClassFromString(@"TUICandidateArrowButton");
    if (arrow && [view isKindOfClass:arrow]) { NGApplyArrowControls(view); return; }
    for (UIView *child in view.subviews) NGVisitCandidateControls(child,depth+1);
}
static void (*NGOriginalCandidateLayout)(id,SEL);
static void (*NGOriginalArrowLayout)(id,SEL);
static void NGCandidateLayoutCore(UIView *view, SEL cmd, void (*original)(id,SEL)) {
    if (NGUpdatingControls) { original(view,cmd); return; }
    NGUpdatingControls=YES;
    @try {
        if (!NGCandidateContainers) NGCandidateContainers=[NSHashTable weakObjectsHashTable];
        [NGCandidateContainers addObject:view];
        NGRestoreCandidateControls(view);
        original(view,cmd);
        if (!NGValues || CACurrentMediaTime()-NGLastPreferenceCheck>1) NGReadPrefs();
        if (NGHideCandidateControls) NGVisitCandidateControls(view,0);
    } @finally { NGUpdatingControls=NO; }
}
static void NGCandidateLayout(id self, SEL cmd) { NGCandidateLayoutCore(self,cmd,NGOriginalCandidateLayout); }
static void NGArrowLayout(id self, SEL cmd) { NGCandidateLayoutCore(self,cmd,NGOriginalArrowLayout); }
static void NGRefreshCandidateControls(void) {
    if (!NGHideCandidateControls) NGRestoreCandidateControls(nil);
    for (UIView *view in NGCandidateContainers.allObjects) {
        if (NGHideCandidateControls) NGVisitCandidateControls(view,0);
        [view setNeedsLayout];
    }
}
