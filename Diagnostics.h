// Diagnostic only: view metadata, never text, keystrokes, screenshots or pixels.
static const void *NGDiagSeenKey = &NGDiagSeenKey;
static NSUInteger NGDiagCount = 0;
static NSString *NGDiagPath(void) {
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSArray<NSString *> *dirs = @[@"/var/mobile/Library/Accessibility",
            [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"]];
        NSString *name = [NSString stringWithFormat:@"KeyboardGlass-diagnostic-%d.log", (int)getpid()];
        for (NSString *dir in dirs) {
            NSString *candidate = [dir stringByAppendingPathComponent:name];
            if ([fm createFileAtPath:candidate contents:[NSData data] attributes:nil]) { path = candidate; break; }
        }
        NSLog(@"[KeyboardGlass diagnostic 0.2.1] log=%@", path ?: @"unavailable");
    });
    return path;
}
static void NGDiagLine(UIView *v, NSString *label, NSMutableString *s) {
    CALayer *l = v.layer;
    [s appendFormat:@"%@ class=%@ ptr=%p parent=%p frame=%@ bounds=%@ alpha=%.4f hidden=%d opaque=%d clips=%d bg=%@ layerBG=%@ layerOpacity=%.4f corner=%.3f mask=%@ maskToBounds=%d subviews=%lu sublayers=%lu",
        label, NSStringFromClass(v.class), (__bridge void *)v, (__bridge void *)v.superview,
        NSStringFromCGRect(v.frame), NSStringFromCGRect(v.bounds), v.alpha, v.hidden, v.opaque,
        v.clipsToBounds, v.backgroundColor, l.backgroundColor ? (__bridge id)l.backgroundColor : @"nil",
        l.opacity, l.cornerRadius, l.mask ? NSStringFromClass(l.mask.class) : @"nil",
        l.masksToBounds, (unsigned long)v.subviews.count, (unsigned long)l.sublayers.count];
    if ([v isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *e = (UIVisualEffectView *)v;
        [s appendFormat:@" effect=%@ content=%p", e.effect ? NSStringFromClass(e.effect.class) : @"nil", (__bridge void *)e.contentView];
    }
    [s appendString:@"\n"];
}
static void NGDiagTree(UIView *v, NSUInteger depth, NSUInteger *remaining, NSMutableString *s) {
    if (!v || !*remaining || depth > 16) return;
    --*remaining;
    NGDiagLine(v, [NSString stringWithFormat:@"tree[%lu]", (unsigned long)depth], s);
    for (UIView *child in v.subviews) NGDiagTree(child, depth + 1, remaining, s);
}
static void NGDiagnostic(UIVisualEffectView *host, BOOL after) {
    if (!host.window || CGRectIsEmpty(host.bounds)) return;
    if (!after) {
        if (NGDiagCount >= 6 || objc_getAssociatedObject(host, NGDiagSeenKey)) return;
        ++NGDiagCount;
        objc_setAssociatedObject(host, NGDiagSeenKey, @1, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        if (![objc_getAssociatedObject(host, NGDiagSeenKey) isEqual:@1]) return;
        objc_setAssociatedObject(host, NGDiagSeenKey, @2, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    @try {
        NSMutableString *s = [NSMutableString stringWithFormat:@"\n=== KeyboardGlass 0.2.1 pid=%d bundle=%@ phase=%@ time=%@ ===\n",
            (int)getpid(), NSBundle.mainBundle.bundleIdentifier, after ? @"after-apply" : @"before-apply", NSDate.date];
        UIView *root = host;
        NSUInteger level = 0;
        for (UIView *v = host; v && level < 24; v = v.superview, ++level) {
            NGDiagLine(v, [NSString stringWithFormat:@"ancestor[%lu]", (unsigned long)level], s);
            if ([NSStringFromClass(v.class) containsString:@"InputSetContainer"]) root = v;
        }
        for (UIWindow *window in host.window.windowScene.windows) {
            [s appendFormat:@"window class=%@ ptr=%p level=%.2f key=%d hidden=%d alpha=%.3f frame=%@ bg=%@ opaque=%d\n",
                NSStringFromClass(window.class), (__bridge void *)window, window.windowLevel, window.keyWindow,
                window.hidden, window.alpha, NSStringFromCGRect(window.frame), window.backgroundColor, window.opaque];
        }
        NSUInteger remaining = 240;
        NGDiagTree(root, 0, &remaining, s);
        if (!remaining) [s appendString:@"tree truncated at 240 nodes\n"];
        NSString *path = NGDiagPath();
        if (path) {
            NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
            [file seekToEndOfFile]; [file writeData:[s dataUsingEncoding:NSUTF8StringEncoding]]; [file closeFile];
        }
    } @catch (NSException *exception) {
        NSLog(@"[KeyboardGlass diagnostic] metadata logging failed: %@", exception.name);
    }
}

