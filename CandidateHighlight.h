// Only TUICandidateCell's background painting and TUICandidateGrid's dedicated
// selectedRowHighlightView are changed. Selection state and text are untouched.
@interface NGHighlightVisibility : NSObject
@property(nonatomic) BOOL hidden;
@end
@implementation NGHighlightVisibility
@end
static NSHashTable<UIView *> *NGHighlightHosts;
static NSMapTable<UIView *,NGHighlightVisibility *> *NGHighlightViews;
static void NGRestoreHighlightViews(UIView *scope) {
    for (UIView *view in NGHighlightViews.keyEnumerator.allObjects) {
        if (scope && view!=scope && ![view isDescendantOfView:scope]) continue;
        view.hidden=[NGHighlightViews objectForKey:view].hidden;
        [NGHighlightViews removeObjectForKey:view];
    }
}
static BOOL NGIsCandidateCell(id cell) {
    Class cls=NSClassFromString(@"TUICandidateCell");
    return cls && [cell isKindOfClass:cls];
}
static void NGTrackHighlightHost(UIView *view) {
    if (!NGHighlightHosts) NGHighlightHosts=[NSHashTable weakObjectsHashTable];
    [NGHighlightHosts addObject:view];
}
static BOOL NGObjectGetter(Class cls,SEL selector) {
    Method m=class_getInstanceMethod(cls,selector);
    if (!m || method_getNumberOfArguments(m)!=2) return NO;
    char *type=method_copyReturnType(m);
    BOOL ok=type && type[0]=='@'; free(type); return ok;
}
static BOOL NGBackgroundSetter(Class cls,SEL selector) {
    Method m=class_getInstanceMethod(cls,selector);
    if (!m || method_getNumberOfArguments(m)!=4) return NO;
    char *ret=method_copyReturnType(m),*a=method_copyArgumentType(m,2),*b=method_copyArgumentType(m,3);
    BOOL ok=ret && strcmp(ret,"v")==0 && a && a[0]=='@' && b && b[0]=='@';
    free(ret);free(a);free(b);return ok;
}
static void NGPaintCandidateCell(UIView *cell) {
    if (!NGHideCandidateHighlight || !NGIsCandidateCell(cell)) return;
    SEL selector=NSSelectorFromString(@"updateBackground:color:");
    if (NGBackgroundSetter(object_getClass(cell),selector)) {
        typedef void (*Paint)(id,SEL,id,id);
        ((Paint)objc_msgSend)(cell,selector,nil,UIColor.clearColor);
    }
}
static void NGApplySelectedRowHighlight(UIView *grid) {
    if (!NGHideCandidateHighlight || !grid.window) return;
    SEL getter=NSSelectorFromString(@"selectedRowHighlightView");
    if (!NGObjectGetter(object_getClass(grid),getter)) return;
    id view=((id (*)(id,SEL))objc_msgSend)(grid,getter);
    if (![view isKindOfClass:UIView.class] || view==grid || ![view isDescendantOfView:grid]) return;
    if (!NGHighlightViews) NGHighlightViews=[NSMapTable weakToStrongObjectsMapTable];
    if (![NGHighlightViews objectForKey:view]) {
        NGHighlightVisibility *state=[NGHighlightVisibility new];state.hidden=[view isHidden];
        [NGHighlightViews setObject:state forKey:view];
    }
    [view setHidden:YES];
}
static void (*NGOriginalCellBackgroundUpdate)(id,SEL,id,id);
static void NGCellBackgroundUpdate(id self,SEL cmd,id image,id color) {
    if (NGIsCandidateCell(self)) {
        NGTrackHighlightHost(self);
        if (NGHideCandidateHighlight) { image=nil;color=UIColor.clearColor; }
    }
    NGOriginalCellBackgroundUpdate(self,cmd,image,color);
}
static void (*NGOriginalHighlightCellLayout)(id,SEL);
static void NGHighlightCellLayout(id self,SEL cmd) {
    NGOriginalHighlightCellLayout(self,cmd);
    NGTrackHighlightHost(self);
    NGPaintCandidateCell(self);
}
static void (*NGOriginalHighlightGridLayout)(id,SEL);
static void (*NGOriginalSelectedRowUpdate)(id,SEL);
static void NGHighlightGridCore(UIView *grid,SEL cmd,void (*original)(id,SEL)) {
    NGRestoreHighlightViews(grid);
    original(grid,cmd);
    NGTrackHighlightHost(grid);
    NGApplySelectedRowHighlight(grid);
}
static void NGHighlightGridLayout(id self,SEL cmd) { NGHighlightGridCore(self,cmd,NGOriginalHighlightGridLayout); }
static void NGSelectedRowUpdate(id self,SEL cmd) { NGHighlightGridCore(self,cmd,NGOriginalSelectedRowUpdate); }
static void NGRefreshCandidateHighlight(void) {
    NGRestoreHighlightViews(nil);
    Class grid=NSClassFromString(@"TUICandidateGrid");
    for (UIView *view in NGHighlightHosts.allObjects) {
        // Ask the system to repaint using its current state. Never restore a
        // cached color/image from a different candidate after cell reuse.
        if (NGIsCandidateCell(view)) {
            SEL colors=NSSelectorFromString(@"updateColors");
            if (NGHasVoidMethod(object_getClass(view),colors)) ((void (*)(id,SEL))objc_msgSend)(view,colors);
            NGPaintCandidateCell(view);
        } else if (grid && [view isKindOfClass:grid]) NGApplySelectedRowHighlight(view);
        [view setNeedsLayout];
    }
}
static void NGInstallCandidateHighlightHooks(void) {
    typedef void (*Hook)(Class,SEL,IMP,IMP *);
    Hook hook=(Hook)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
    if (!hook) return;
    Class base=NSClassFromString(@"TUICandidateBaseCell"),cell=NSClassFromString(@"TUICandidateCell"),grid=NSClassFromString(@"TUICandidateGrid");
    static BOOL baseDone=NO,cellDone=NO,gridDone=NO,updateDone=NO;
    SEL paint=NSSelectorFromString(@"updateBackground:color:"),layout=@selector(layoutSubviews),update=NSSelectorFromString(@"updateSelectedRowHighlightView");
    if (!baseDone && base && [base isSubclassOfClass:UICollectionViewCell.class] && NGBackgroundSetter(base,paint)) {
        baseDone=YES;hook(base,paint,(IMP)NGCellBackgroundUpdate,(IMP *)&NGOriginalCellBackgroundUpdate);
    }
    if (!cellDone && cell && [cell isSubclassOfClass:UICollectionViewCell.class] && NGHasVoidMethod(cell,layout)) {
        cellDone=YES;hook(cell,layout,(IMP)NGHighlightCellLayout,(IMP *)&NGOriginalHighlightCellLayout);
    }
    if (grid && [grid isSubclassOfClass:UIView.class] && NGObjectGetter(grid,NSSelectorFromString(@"selectedRowHighlightView"))) {
        if (!gridDone && NGHasVoidMethod(grid,layout)) {
            gridDone=YES;hook(grid,layout,(IMP)NGHighlightGridLayout,(IMP *)&NGOriginalHighlightGridLayout);
        }
        if (!updateDone && NGHasVoidMethod(grid,update)) {
            updateDone=YES;hook(grid,update,(IMP)NGSelectedRowUpdate,(IMP *)&NGOriginalSelectedRowUpdate);
        }
    }
}
