#import "NGGlassMaterial.h"
#import "NGPreferences.h"
#import <Glassify/GLSGlassView.h>
#import "GLSRenderer.h"
#import <dlfcn.h>
#import <limits.h>

NSBundle *NGGlassResources(void) {
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info={};
        if (!dladdr((const void *)&NGGlassResources,&info) || !info.dli_fname) return;
        NSString *directory=[[NSString stringWithUTF8String:info.dli_fname] stringByDeletingLastPathComponent];
        bundle=[NSBundle bundleWithPath:[directory stringByAppendingPathComponent:@"NingKeyboardGlassResources.bundle"]];
    });
    return bundle;
}
static UIImage *NGFixedImage(UIUserInterfaceStyle style) {
    static UIImage *light,*dark;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSBundle *bundle=NGGlassResources();
        for (NSUInteger i=0;i<2;i++) {
            NSString *name=i?@"GlassifyRegularDark":@"GlassifyRegularLight";
            NSData *data=[NSData dataWithContentsOfFile:[bundle pathForResource:name ofType:@"png"]];
            UIImage *raw=[UIImage imageWithData:data scale:3];
            UIImage *image=[raw resizableImageWithCapInsets:UIEdgeInsetsMake(30,32,30,32) resizingMode:UIImageResizingModeStretch];
            if (i) dark=image; else light=image;
        }
    });
    return style==UIUserInterfaceStyleDark?dark:light;
}
BOOL NGGlassAvailable(void) { return NGFixedImage(UIUserInterfaceStyleLight)!=nil && NGFixedImage(UIUserInterfaceStyleDark)!=nil; }
static BOOL NGKeyboardClass(UIView *view) {
    for (UIView *v=view;v;v=v.superview) {
        NSString *name=NSStringFromClass(v.class);
        if ([name containsString:@"Keyboard"] || [name containsString:@"UIInputSet"]) return YES;
    }
    return NO;
}
// Choose only a locally readable App view. A keyboard extension cannot read
// another process's layer tree. Such hosts keep the pre-baked Glassify image.
static UIView *NGAppSource(UIVisualEffectView *host) {
    UIView *root=host.window.rootViewController.view;
    if (root && !NGKeyboardClass(root) && !NGKeyboardClass(host.window)) return root;
    UIWindowScene *scene=host.window.windowScene;
    for (UIWindow *window in scene.windows) {
        if (window==host.window || window.hidden || window.alpha<0.01 || NGKeyboardClass(window)) continue;
        if (window.windowLevel!=UIWindowLevelNormal) continue;
        UIView *candidate=window.rootViewController.view;
        if (candidate && !NGKeyboardClass(candidate)) return candidate;
    }
    return nil;
}
@interface NGKeyboardMaterial : UIView
@property(nonatomic,strong) UIImageView *fixed;
@property(nonatomic,strong) UIImageView *input;
@property(nonatomic,strong) GLSGlassView *glass;
@property(nonatomic,weak) UIVisualEffectView *host;
@property(nonatomic,assign) CGRect previousRect;
@property(nonatomic,assign) NSInteger previousMode;
@property(nonatomic,assign) UIUserInterfaceStyle previousStyle;
@property(nonatomic,assign) BOOL hasGeometry;
- (void)updateForHost:(UIVisualEffectView *)host force:(BOOL)force;
- (void)pause;
@end
@implementation NGKeyboardMaterial
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;
        self.isAccessibilityElement=NO;
        self.accessibilityElementsHidden=YES;
        self.opaque=NO;
        _previousMode=-1;
        _fixed=[UIImageView new];
        _fixed.userInteractionEnabled=NO;
        _fixed.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self addSubview:_fixed];
    }
    return self;
}
- (void)pause {
    // Destroy the owned live view; do not just hide a registered renderer.
    [_glass removeFromSuperview];_glass=nil;
    [_input removeFromSuperview];_input=nil;
    _fixed.hidden=NO;
    _hasGeometry=NO;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self pause];
}
- (UIImage *)captureFrom:(UIView *)source host:(UIVisualEffectView *)host {
    if (CGRectIsEmpty(self.bounds) || !source.window) return nil;
    const CGRect rect=[self convertRect:self.bounds toView:source];
    if (!CGRectIntersectsRect(rect,source.bounds)) return nil;
    // Omit the whole keyboard branch from a same-root capture so key glyphs
    // never become a second sampled keyboard. No file writes or polling.
    UIView *keyboard=host;
    while (keyboard.superview && keyboard.superview!=source) keyboard=keyboard.superview;
    BOOL omit=keyboard!=source && keyboard.superview==source;
    BOOL wasHidden=keyboard.layer.hidden;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];
    format.scale=host.window.screen.scale;
    format.opaque=YES;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:self.bounds.size format:format];
    __block UIImage *image=nil;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    @try {
        if (omit) keyboard.layer.hidden=YES;
        image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            UIColor *base=[UIColor.systemBackgroundColor resolvedColorWithTraitCollection:host.traitCollection];
            CGContextSetFillColorWithColor(context.CGContext,base.CGColor);
            CGContextFillRect(context.CGContext,(CGRect){CGPointZero,self.bounds.size});
            CGContextTranslateCTM(context.CGContext,-rect.origin.x,-rect.origin.y);
            [source.layer renderInContext:context.CGContext];
        }];
    } @finally {
        if (omit) keyboard.layer.hidden=wasHidden;
        [CATransaction commit];
    }
    return image;
}
- (void)updateForHost:(UIVisualEffectView *)host force:(BOOL)force {
    self.host=host;
    UIUserInterfaceStyle style=host.traitCollection.userInterfaceStyle;
    UIImage *fixed=NGFixedImage(style);
    if (_fixed.image!=fixed) _fixed.image=fixed;
    _fixed.frame=self.bounds;
    NSInteger mode=NGKeyboardRenderingMode();
    CGRect rect=[self convertRect:self.bounds toView:host.window];
    BOOL changed=force || !_hasGeometry || mode!=_previousMode || style!=_previousStyle || !CGRectEqualToRect(rect,_previousRect);
    _previousMode=mode;_previousStyle=style;_previousRect=rect;_hasGeometry=YES;
    if (mode==0 || !self.window) {
        if (_glass || _input) [self pause];
        return;
    }
    if (!changed) return;
    UIView *source=NGAppSource(host);
    if (!source || ![GLSRenderer shared]) { [self pause];_hasGeometry=YES;return; }
    UIImage *snapshot=[self captureFrom:source host:host];
    if (!snapshot) { [self pause];_hasGeometry=YES;return; }
    if (!_input) {
        _input=[UIImageView new];_input.userInteractionEnabled=NO;
        [self insertSubview:_input atIndex:0];
    }
    _input.image=snapshot;_input.frame=self.bounds;
    if (!_glass) {
        _glass=[GLSGlassView new];
        // Exactly the stock TabBar platter material: default Regular,
        // Automatic frost, nil tint. No controls, lens or selection pill.
        _glass.contentVibrancy=NO;
        _glass.userInteractionEnabled=NO;
        _glass.isAccessibilityElement=NO;
        _glass.tracksBackdropMotion=NO;
        _glass.backdropSourceView=_input;
        [self insertSubview:_glass aboveSubview:_input];
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    _glass.frame=self.bounds;
    // The stock capsule radius is adapted only to the existing keyboard's
    // outside corners, never changing Glassify's optical/material fields.
    CGFloat radius=14;
    if (_glass.cornerRadius!=radius) _glass.cornerRadius=radius;
    [CATransaction commit];
    [_glass setNeedsBackdropUpdate];
    [_glass setNeedsLayout];[_glass layoutIfNeeded];
    _fixed.hidden=YES;
}
@end
UIView *NGGlassMake(void) { return [[NGKeyboardMaterial alloc] initWithFrame:CGRectZero]; }
void NGGlassUpdate(UIView *material, UIVisualEffectView *host, BOOL force) {
    if ([material isKindOfClass:NGKeyboardMaterial.class]) [(NGKeyboardMaterial *)material updateForHost:host force:force];
}
void NGGlassPause(UIView *material) {
    if ([material isKindOfClass:NGKeyboardMaterial.class]) [(NGKeyboardMaterial *)material pause];
}
