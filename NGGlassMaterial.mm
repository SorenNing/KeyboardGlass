#import "NGGlassMaterial.h"
#import <Glassify/GLSGlassView.h>
#import "GLSGlassSurface.h"
#import "GLSRenderer.h"
#import <dlfcn.h>
#import <Metal/Metal.h>

@interface GLSGlassView (NGReadback)
- (GLSGlassSurface *)gls_surface;
@end

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

static BOOL NGKeyboardOwned(UIView *view) {
    for (UIView *v=view;v;v=v.superview) {
        NSString *name=NSStringFromClass(v.class);
        if ([name containsString:@"Keyboard"] || [name containsString:@"UIInputSet"]) return YES;
    }
    return NO;
}
static UIView *NGBackdropSource(UIVisualEffectView *host) {
    UIWindowScene *scene=host.window.windowScene;
    for (UIWindow *window in scene.windows) {
        if (window==host.window || window.hidden || window.alpha<0.01 || NGKeyboardOwned(window)) continue;
        if (window.windowLevel!=UIWindowLevelNormal) continue;
        UIView *candidate=window.rootViewController.view;
        if (candidate && !NGKeyboardOwned(candidate)) return candidate;
    }
    // A separate keyboard process cannot inspect another App's view tree.
    return nil;
}

@interface NGKeyboardGlassView : UIView
@property(nonatomic,strong) GLSGlassView *glass;
@property(nonatomic,weak) UIView *source;
@property(nonatomic,copy) void (^ready)(void);
@property(nonatomic,assign) BOOL confirmed;
@property(nonatomic,assign) BOOL checking;
- (BOOL)updateForHost:(UIVisualEffectView *)host ready:(void (^)(void))ready;
- (void)pause;
@end
@implementation NGKeyboardGlassView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;
        self.isAccessibilityElement=NO;
        self.backgroundColor=UIColor.clearColor;
        self.opaque=NO;
        _glass=[GLSGlassView new];
        // Original GLSGlassView defaults: Regular, Automatic frost, nil tint.
        _glass.contentVibrancy=NO; // Original tab-bar platter, no tab content.
        _glass.userInteractionEnabled=NO;
        _glass.isAccessibilityElement=NO;
        _glass.tracksBackdropMotion=YES;
        [_glass gls_surface].keepsOutput=YES;
        [self addSubview:_glass];
    }
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self pause];
}
- (void)pause {
    [_glass gls_surface].hidden=YES;
    _glass.tracksBackdropMotion=NO;
    _glass.backdropSourceView=nil;
    _source=nil;
    _ready=nil;
    _confirmed=NO;
    _checking=NO;
}
- (BOOL)updateForHost:(UIVisualEffectView *)host ready:(void (^)(void))ready {
    if (!self.window || !host.window || CGRectIsEmpty(self.bounds)) { [self pause]; return NO; }
    UIView *source=NGBackdropSource(host);
    if (!source || ![GLSRenderer shared]) { [self pause]; return NO; }
    if (_source!=source) { _confirmed=NO; _checking=NO; }
    _source=source;
    _ready=[ready copy];
    if (!CGRectEqualToRect(_glass.frame,self.bounds)) _glass.frame=self.bounds;
    if (_glass.backdropSourceView!=source) _glass.backdropSourceView=source;
    if (!_glass.tracksBackdropMotion) _glass.tracksBackdropMotion=YES;
    [_glass gls_surface].hidden=NO;
    // This changes only the keyboard's outline, not original optical fields.
    CGFloat radius=host.layer.cornerRadius;
    if (radius<=0) radius=14;
    if (_glass.cornerRadius!=radius) _glass.cornerRadius=radius;
    if (_confirmed || _checking) return YES;
    [_glass gls_surface].keepsOutput=YES;
    [_glass setNeedsBackdropUpdate];
    [_glass setNeedsLayout];
    _checking=YES;
    __weak NGKeyboardGlassView *weakSelf=self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NGKeyboardGlassView *v=weakSelf;
        if (!v || !v.window || v.confirmed) return;
        id<MTLTexture> texture=[v.glass gls_surface].outputTexture;
        id<MTLCommandQueue> queue=[GLSRenderer shared].queue;
        id<MTLBuffer> pixel=texture ? [texture.device newBufferWithLength:256 options:MTLResourceStorageModeShared] : nil;
        id<MTLCommandBuffer> fence=texture && pixel ? [queue commandBuffer] : nil;
        id<MTLBlitCommandEncoder> blit=fence ? [fence blitCommandEncoder] : nil;
        if (!blit || !texture.width || !texture.height) { v.checking=NO; return; }
        [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0
             sourceOrigin:MTLOriginMake(texture.width/2,texture.height/2,0)
               sourceSize:MTLSizeMake(1,1,1) toBuffer:pixel destinationOffset:0
        destinationBytesPerRow:256 destinationBytesPerImage:256];
        [blit endEncoding];
        [fence addCompletedHandler:^(id<MTLCommandBuffer> completed) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NGKeyboardGlassView *current=weakSelf;
                if (!current || current.source!=source) return;
                current.checking=NO;
                const uint8_t *rgba=(const uint8_t *)pixel.contents;
                if (current.window && completed.status==MTLCommandBufferStatusCompleted && rgba && rgba[3]>=200) {
                    current.confirmed=YES;
                    if (current.ready) current.ready();
                    [current.glass gls_surface].keepsOutput=NO;
                }
            });
        }];
        [fence commit];
    });
    return YES;
}
@end
UIView *NGGlassMake(void) {
    NSBundle *resources=NGGlassResources();
    NSURL *library=[resources URLForResource:@"default" withExtension:@"metallib"];
    if (!library || !MTLCreateSystemDefaultDevice()) return nil;
    if (![GLSRenderer shared]) return nil;
    return [[NGKeyboardGlassView alloc] initWithFrame:CGRectZero];
}
BOOL NGGlassUpdate(UIView *material, UIVisualEffectView *host, void (^ready)(void)) {
    return [material isKindOfClass:NGKeyboardGlassView.class] &&
        [(NGKeyboardGlassView *)material updateForHost:host ready:ready];
}
void NGGlassPause(UIView *material) {
    if ([material isKindOfClass:NGKeyboardGlassView.class]) [(NGKeyboardGlassView *)material pause];
}
