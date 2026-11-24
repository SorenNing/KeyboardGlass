// 0.1.6 input feasibility probe. Does not display or persist captured pixels.
#include <stdint.h>
#include <math.h>
static NSUInteger NGProbeFrames = 0;
static BOOL NGProbeBusy = NO;
static void NGProbeMask(UIView *v, UIView *target, NSMutableArray<UIView *> *hidden) {
    if (v == target) return;
    for (UIView *child in v.subviews) {
        if (child == target || [target isDescendantOfView:child]) NGProbeMask(child, target, hidden);
        else if (!child.hidden) { [hidden addObject:child]; child.hidden = YES; }
    }
}
static NSString *NGProbeStats(UIImage *image) {
    if (!image.CGImage) return @"image=nil";
    uint8_t px[32*32*4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px,32,32,8,32*4,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!ctx) return @"stats=context_failed";
    CGContextDrawImage(ctx,CGRectMake(0,0,32,32),image.CGImage);
    CGContextRelease(ctx);
    double sum=0, sq=0, alpha=0; NSUInteger visible=0;
    uint64_t fingerprint=14695981039346656037ULL;
    for (NSUInteger i=0;i<32*32;i++) {
        double a=px[i*4+3]/255.0; alpha+=a;
        if (a>0.01) {
            double y=(0.2126*px[i*4]+0.7152*px[i*4+1]+0.0722*px[i*4+2])/(255*a);
            sum+=y; sq+=y*y; visible++;
        }
        for (NSUInteger c=0;c<4;c++) { fingerprint^=px[i*4+c]; fingerprint*=1099511628211ULL; }
    }
    double mean=visible?sum/visible:0;
    return [NSString stringWithFormat:@"size=%@ visible=%lu/1024 meanAlpha=%.4f luminance=%.4f variance=%.6f fingerprint=%016llx",NSStringFromCGSize(image.size),(unsigned long)visible,alpha/1024,mean,visible?fmax(0,sq/visible-mean*mean):0,(unsigned long long)fingerprint];
}
static void NGProbeWrite(NSString *line) {
    NSString *path=NGDiagPath();
    if (!path) return;
    @try {
        NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];
        [file seekToEndOfFile]; [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [file closeFile];
    } @catch (NSException *e) { NSLog(@"[KG016 probe] log failed %@",e.name); }
}
static void NGProbeCapture(UIVisualEffectView *host) {
    if (NGProbeBusy || NGProbeFrames>=3 || !host.window || host.hidden || host.bounds.size.width<200 || host.bounds.size.height<100) return;
    // Only inspect a visible, settled keyboard. No remote-process capture assumption.
    UIWindow *window=host.window;
    CGRect region=CGRectIntersection([host convertRect:host.bounds toView:window],window.bounds);
    if (CGRectIsNull(region) || region.size.height<100) return;
    UIView *background=nil;
    Class cls=NSClassFromString(@"_UIVisualEffectBackdropView");
    for (UIView *v in host.subviews) if (cls && object_getClass(v)==cls) { background=v; break; }
    if (!background || background.hidden || fabs(background.alpha-0.8)>0.001) return;
    NGProbeBusy=YES; ++NGProbeFrames;
    NSMutableArray<UIView *> *hidden=[NSMutableArray array];
    BOOL contextOpen=NO;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    @try {
        // Keep exactly the ancestor path to this system background. Excludes keys,
        // toolbars, candidate text, ALL plugin images and other backdrop copies.
        NGProbeMask(window,background,hidden);
        NSMutableString *log=[NSMutableString stringWithFormat:@"\n[KG016 capture] sample=%lu time=%@ bundle=%@ window=%@ region=%@ background=%@ alpha=%.3f excluded=%lu\n",(unsigned long)NGProbeFrames,NSDate.date,NSBundle.mainBundle.bundleIdentifier,NSStringFromClass(window.class),NSStringFromCGRect(region),NSStringFromClass(background.class),background.alpha,(unsigned long)hidden.count];
        for (NSUInteger method=0;method<2;method++) {
            // Crop by translating window coordinates into a region-sized context.
            // scale=0.5 is diagnostic only; final renderer will use its own texture scale.
            UIGraphicsBeginImageContextWithOptions(region.size,NO,0.5); contextOpen=YES;
            CGContextRef ctx=UIGraphicsGetCurrentContext();
            BOOL ok=ctx!=NULL;
            if (ctx) {
                CGContextTranslateCTM(ctx,-region.origin.x,-region.origin.y);
                if (method==0) [window.layer renderInContext:ctx];
                else ok=[window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
            }
            UIImage *image=UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext(); contextOpen=NO;
            [log appendFormat:@"method=%@ returned=%d %@\n",method==0?@"layer.render":@"drawHierarchy",ok,NGProbeStats(image)];
        }
        [log appendString:@"[KG016 capture] stats do NOT prove App pixels; needs content-change correlation and feedback check. No pixel files written.\n"];
        NGProbeWrite(log);
    } @catch (NSException *e) {
        NGProbeWrite([NSString stringWithFormat:@"[KG016 capture] exception=%@\n",e.name]);
    } @finally {
        if (contextOpen) UIGraphicsEndImageContext();
        for (UIView *v in hidden) v.hidden=NO;
        [CATransaction commit];
        NGProbeBusy=NO;
    }
}
static void NGProbeSchedule(UIVisualEffectView *host) {
    if (NGProbeFrames>=3 || NGProbeBusy || host.bounds.size.width<200 || host.bounds.size.height<100) return;
    static CFTimeInterval last=0;
    CFTimeInterval now=CACurrentMediaTime();
    if (now-last<1.0) return;
    last=now;
    __weak UIVisualEffectView *weakHost=host;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        UIVisualEffectView *strongHost=weakHost;
        if (strongHost) NGProbeCapture(strongHost);
    });
}
