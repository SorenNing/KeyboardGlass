#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <CydiaSubstrate/CydiaSubstrate.h>
#import "KGCommon.h"

// ---------------------------------------------------------------------------
// KeyboardGlass — 键盘美化（照 Laetus 图像主题实现方式）0.2
//  - 注入 UIKit/UIKitCore 宿主进程
//  - hook UIKeyboardLayoutStar setCurrentKeyboardLayoutStar: + layoutSubviews
//    （17.2.1 上 keyPlaneDidChange: 不在该类，layoutSubviews 是 UIView 必有方法）
//  - 运行时 KVC 探测当前 keyplane 名，失败回退 KeyboardMain
//  - 主题目录多根扫描：/var/jb/Library/KeyboardGlass/Themes 优先，
//    /var/mobile/Library/KeyboardGlass/Themes、/Library/KeyboardGlass/Themes 兜底
//  - 未选主题时自动使用发现的第一个主题目录（"放进去就生效"）
// ---------------------------------------------------------------------------

#define KG_DOMAIN       "com.ning.keyboardglass"
#define KG_CHANGED      "com.ning.keyboardglass.changed"
#define KG_LOG_PATH     "/var/mobile/Library/KeyboardGlass.log"

#pragma mark - 日志（与 prefs 进程共用一个文件）

void KGLog(NSString *format, ...) {
    static NSInteger kgLogLines = -1;
    if (kgLogLines < 0) {
        kgLogLines = 0;
        unlink(KG_LOG_PATH);
    }
    if (kgLogLines > 6000) return;
    va_list args; va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *stamp = [NSString stringWithFormat:@"[tweak %@] %@\n",
        [NSDate.date descriptionWithLocale:@"HH:mm:ss"], line];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@KG_LOG_PATH];
    if (!fh) {
        [@"" writeToFile:@KG_LOG_PATH atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        fh = [NSFileHandle fileHandleForWritingAtPath:@KG_LOG_PATH];
    }
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[stamp dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    kgLogLines++;
}

#pragma mark - 偏好读取

BOOL kgEnabled = YES;
BOOL kgHideKeyCaps = NO;
BOOL kgHideKeyShadows = NO;
CGFloat kgBackgroundAlpha = 1.0;
static NSString *kgActiveThemeName = nil;      // 设置里选的主题名（可空）
static NSString *kgResolvedThemePath = nil;    // 解析出的主题目录（或单文件）
static BOOL kgResolvedIsFile = NO;             // 主题是单个 PNG（直接铺满一切 keyplane）
static NSInteger kgGeneration = 0;             // 主题变化代数（用于视图去重失效）

#pragma mark - 主题根目录扫描

static NSArray *KGThemeRoots(void) {
    return @[@"/var/jb/Library/KeyboardGlass/Themes",
             @"/var/mobile/Library/KeyboardGlass/Themes",
             @"/Library/KeyboardGlass/Themes"];
}

// 收集所有根目录下的主题（目录；同名去重，/var/jb 优先）
static NSArray *KGAllThemeDirs(void) {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *root in KGThemeRoots()) {
        for (NSString *item in [fm contentsOfDirectoryAtPath:root error:NULL]) {
            if ([item hasPrefix:@"."]) continue;
            NSString *full = [root stringByAppendingPathComponent:item];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir && ![seen containsObject:item]) {
                [seen addObject:item];
                [out addObject:full];
            }
        }
    }
    return out;
}

static BOOL KGBoolDefault(NSString *key, BOOL dflt) {
    CFPreferencesAppSynchronize(CFSTR(KG_DOMAIN));
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR(KG_DOMAIN));
    BOOL out = dflt;
    if (v) { out = CFBooleanGetTypeID() == CFGetTypeID(v) ? [(id)CFBridgingRelease(v) boolValue] : dflt; }
    return out;
}

static CGFloat KGNumberDefault(NSString *key, CGFloat dflt) {
    CFPreferencesAppSynchronize(CFSTR(KG_DOMAIN));
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR(KG_DOMAIN));
    CGFloat out = dflt;
    if (v) {
        if (CFNumberGetTypeID() == CFGetTypeID(v)) { double d = dflt; CFNumberGetValue(v, kCFNumberDoubleType, &d); out = d; }
        CFRelease(v);
    }
    return out;
}

static void KGResolveThemePath(void) {
    NSString *resolved = nil;
    BOOL isFile = NO;
    NSFileManager *fm = NSFileManager.defaultManager;

    if (kgActiveThemeName.length) {
        for (NSString *root in KGThemeRoots()) {
            NSString *dir = [root stringByAppendingPathComponent:kgActiveThemeName];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:dir isDirectory:&isDir]) {
                resolved = dir; isFile = !isDir; break;
            }
        }
        if (!resolved) KGLog(@"theme '%@' NOT found in any root, falling back", kgActiveThemeName);
    }
    if (!resolved) {
        // 自动发现：第一个主题目录
        NSArray *dirs = KGAllThemeDirs();
        if (dirs.count) { resolved = dirs.firstObject; isFile = NO; }
    }
    if (resolved && ![resolved isEqualToString:kgResolvedThemePath]) {
        kgResolvedThemePath = resolved;
        kgResolvedIsFile = isFile;
        kgGeneration++;
        KGLog(@"theme resolved -> %@ (gen %ld)", resolved, (long)kgGeneration);
    } else if (!resolved && kgResolvedThemePath) {
        kgResolvedThemePath = nil;
        kgGeneration++;
        KGLog(@"theme cleared (gen %ld)", (long)kgGeneration);
    }
}

static void KGReloadPreferences(void) {
    kgEnabled         = KGBoolDefault(@"Enabled", YES);
    kgHideKeyCaps     = KGBoolDefault(@"HideKeyCaps", NO);
    kgHideKeyShadows  = KGBoolDefault(@"HideKeyShadows", NO);
    kgBackgroundAlpha = KGNumberDefault(@"BackgroundAlpha", 1.0);
    CFPreferencesAppSynchronize(CFSTR(KG_DOMAIN));
    CFPropertyListRef t = CFPreferencesCopyAppValue(CFSTR("ActiveTheme"), CFSTR(KG_DOMAIN));
    NSString *theme = t ? [(id)CFBridgingRelease(t) copy] : nil;
    if (![kgActiveThemeName isEqualToString:theme]) {
        kgActiveThemeName = [theme copy];
        KGLog(@"preferences: ActiveTheme='%@' Enabled=%d", kgActiveThemeName, kgEnabled);
    }
    KGResolveThemePath();
}

#pragma mark - 主题图查找

// 屏高后缀用 POINTS（与系统资源命名一致：896h=414x896pt 的 XR/11 系）
static NSString *KGDeviceHeightSuffix(void) {
    static NSString *suffix;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGFloat pt = UIScreen.mainScreen.bounds.size.height;
        if      (pt >= 930) suffix = @"-932h";
        else if (pt >= 890) suffix = @"-896h";
        else if (pt >= 850) suffix = @"-852h";
        else if (pt >= 840) suffix = @"-844h";
        else if (pt >= 810) suffix = @"-812h";
        else if (pt >= 730) suffix = @"-736h";
        else if (pt >= 660) suffix = @"-667h";
        else suffix = @"";
        KGLog(@"device height %.0fpt -> suffix '%@'", pt, suffix);
    });
    return suffix;
}

static NSMutableDictionary *kgMissLogged;   // base -> @YES（避免刷屏）
static UIImage *KGImageForBaseName(NSString *base) {
    if (!kgResolvedThemePath) return nil;

    if (kgResolvedIsFile) {
        // 单文件主题：一张图铺所有 keyplane
        return [UIImage imageWithContentsOfFile:kgResolvedThemePath];
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *heights = @[ KGDeviceHeightSuffix(), @"" ];
    NSArray *scales  = @[@"@3x", @"@2x", @""];
    for (NSString *height in heights) {
        for (NSString *scale in scales) {
            NSString *name = [NSString stringWithFormat:@"%@%@%@.png", base, height, scale];
            NSString *path = [kgResolvedThemePath stringByAppendingPathComponent:name];
            if ([fm fileExistsAtPath:path]) {
                UIImage *raw = [UIImage imageWithContentsOfFile:path];
                if (raw) {
                    return [UIImage imageWithCGImage:raw.CGImage
                                               scale:UIScreen.mainScreen.scale
                                         orientation:UIImageOrientationUp];
                }
            }
        }
    }

    // 兜底：目录里找 base 开头的任意 PNG（主题图屏高后缀不匹配也能铺上）
    NSArray *files = [fm contentsOfDirectoryAtPath:kgResolvedThemePath error:NULL];
    NSString *best = nil;
    for (NSString *f in files) {
        if ([f hasPrefix:base] && [f.pathExtension isEqualToString:@"png"]) {
            if (!best || f.length > best.length) best = f;   // 优先带后缀的长名
        }
    }
    if (best) {
        UIImage *raw = [UIImage imageWithContentsOfFile:[kgResolvedThemePath stringByAppendingPathComponent:best]];
        if (raw) {
            return [UIImage imageWithCGImage:raw.CGImage
                                       scale:UIScreen.mainScreen.scale
                                 orientation:UIImageOrientationUp];
        }
    }

    if (!kgMissLogged) kgMissLogged = [NSMutableDictionary new];
    if (!kgMissLogged[base]) {
        kgMissLogged[base] = @YES;
        KGLog(@"no image for '%@' in %@ (files: %@)", base, kgResolvedThemePath.lastPathComponent,
              [files count] ? [files componentsJoinedByString:@", "] : @"(empty)");
    }
    return nil;
}

#pragma mark - 背景视图管理

static const char kKGAssocBackground = '\0';
static const char kKGAssocForeground = '\0';
static const char kKGAssocCurrentKey = '\0';

static UIImageView *KGBackgroundViewForView(UIView *keyboard) {
    UIImageView *v = objc_getAssociatedObject(keyboard, &kKGAssocBackground);
    if (!v) {
        v = [[UIImageView alloc] initWithFrame:keyboard.bounds];
        v.userInteractionEnabled = NO;
        v.contentMode = UIViewContentModeScaleToFill;
        objc_setAssociatedObject(keyboard, &kKGAssocBackground, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return v;
}

static UIImageView *KGForegroundViewForView(UIView *keyboard) {
    UIImageView *v = objc_getAssociatedObject(keyboard, &kKGAssocForeground);
    if (!v) {
        v = [[UIImageView alloc] initWithFrame:keyboard.bounds];
        v.userInteractionEnabled = NO;
        v.contentMode = UIViewContentModeScaleToFill;
        objc_setAssociatedObject(keyboard, &kKGAssocForeground, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return v;
}

static NSString *KGKeyplaneSignature(NSString *keyplaneName, BOOL landscape) {
    return [NSString stringWithFormat:@"%@|%@|gen%ld", keyplaneName ?: @"", landscape ? @"L" : @"P", (long)kgGeneration];
}

static void KGApplyThemeToKeyboard(UIView *keyboard, NSString *keyplaneName) {
    if (!keyboard || !kgEnabled || !kgResolvedThemePath) return;

    BOOL landscape = UIScreen.mainScreen.bounds.size.width > UIScreen.mainScreen.bounds.size.height;
    NSString *signature = KGKeyplaneSignature(keyplaneName, landscape);

    NSString *last = objc_getAssociatedObject(keyboard, &kKGAssocCurrentKey);
    if ([last isEqualToString:signature]) return;
    objc_setAssociatedObject(keyboard, &kKGAssocCurrentKey, signature, OBJC_ASSOCIATION_COPY_NONATOMIC);

    NSString *orient = landscape ? @"Landscape" : @"Portrait";
    NSString *base = [NSString stringWithFormat:@"%@BG%@", keyplaneName ?: @"", orient];
    UIImage *bg = KGImageForBaseName(base);
    if (!bg) bg = KGImageForBaseName([NSString stringWithFormat:@"%@BG-%@", keyplaneName ?: @"", orient]);

    UIImageView *bgView = KGBackgroundViewForView(keyboard);
    UIImageView *fgView = KGForegroundViewForView(keyboard);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (bg) {
        bgView.image = bg;
        bgView.alpha = kgBackgroundAlpha;
        bgView.frame = keyboard.bounds;
        bgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        if (bgView.superview != keyboard) {
            [keyboard insertSubview:bgView atIndex:0];
            KGLog(@"insert background for %@ (%@)", keyplaneName, signature);
        }
        KGLog(@"theme bg applied: %@ -> %@x%@ alpha=%.2f", signature, @(bg.size.width), @(bg.size.height), kgBackgroundAlpha);
    } else {
        bgView.image = nil;
    }

    // 前景层（可选素材）
    UIImage *fg = KGImageForBaseName([NSString stringWithFormat:@"%@FG%@", keyplaneName ?: @"", orient]);
    if (fg) {
        fgView.image = fg;
        fgView.alpha = kgBackgroundAlpha;
        fgView.frame = keyboard.bounds;
        fgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        if (!fgView.superview) [keyboard addSubview:fgView];
        fgView.layer.zPosition = 9999;
    } else if (fgView.superview) {
        fgView.image = nil;
    }

    [CATransaction commit];
}

#pragma mark - keyplane 名探测（KVC）

static NSString *kgProbedKeyplaneKey = nil;

static NSString *KGProbeKeyplaneName(UIView *keyboard) {
    if (kgProbedKeyplaneKey) {
        @try {
            id v = [keyboard valueForKey:kgProbedKeyplaneKey];
            if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v;
            id n = [v valueForKey:@"name"];
            if ([n isKindOfClass:NSString.class] && [(NSString *)n length]) return n;
        } @catch (__unused NSException *e) { kgProbedKeyplaneKey = nil; }
    }

    static NSArray *candidates;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        candidates = @[@"keyplaneName", @"_keyplaneName", @"keyplane", @"_keyplane",
                       @"currentKeyplane", @"_currentKeyplane", @"keyPlane", @"_keyPlane",
                       @"layout", @"_layout"];
    });
    for (NSString *key in candidates) {
        @try {
            id v = [keyboard valueForKey:key];
            if (!v) continue;
            if ([v isKindOfClass:NSString.class] && [v length]) {
                kgProbedKeyplaneKey = key;
                KGLog(@"probe: key '%@' = '%@'", key, v);
                return v;
            }
            @try {
                id n = [v valueForKey:@"name"];
                if ([n isKindOfClass:NSString.class] && [n length]) {
                    kgProbedKeyplaneKey = key;
                    KGLog(@"probe: key '%@'.name = '%@'", key, n);
                    return n;
                }
            } @catch (__unused NSException *e) {}
            static int probedLogged = 0;
            if (probedLogged++ < 12) KGLog(@"probe: key '%@' -> %@ (no usable name)", key, NSStringFromClass([v class]));
        } @catch (__unused NSException *e) {}
    }
    static BOOL probeFailLogged = NO;
    if (!probeFailLogged) {
        probeFailLogged = YES;
        KGLog(@"probe: NO keyplane key found, using KeyboardMain fallback");
    }
    return nil;
}

#pragma mark - Hook 核心

static void KGPreferencesChangedCallback(CFNotificationCenterRef center, void *observer,
                                         CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    KGReloadPreferences();
    KGLog(@"preferences changed notification received");
}

static IMP orig_setCurrentKeyboardLayoutStar = NULL;
static void KG_hooked_setCurrentKeyboardLayoutStar(id self, SEL _cmd, id layoutStar) {
    ((void (*)(id, SEL, id))orig_setCurrentKeyboardLayoutStar)(self, _cmd, layoutStar);
    @try {
        static int fires = 0;
        fires++;
        if (fires <= 8) KGLog(@"setCurrentKeyboardLayoutStar: fired (#%d)", fires);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *keyboard = (UIView *)self;
            if (![keyboard isKindOfClass:UIView.class]) return;
            NSString *name = KGProbeKeyplaneName(keyboard);
            KGApplyThemeToKeyboard(keyboard, name ?: @"KeyboardMain");
        });
    } @catch (NSException *e) { KGLog(@"exception setCurrentLayout: %@", e); }
}

static IMP orig_layoutStarLayout = NULL;
static void KG_hooked_layoutStarLayout(id self, SEL _cmd) {
    ((void (*)(id, SEL))orig_layoutStarLayout)(self, _cmd);
    @try {
        if (!kgEnabled) return;
        static NSTimeInterval lastReload = 0;
        NSTimeInterval now = [NSDate.date timeIntervalSince1970];
        if (now - lastReload > 0.5) {
            lastReload = now;
            KGReloadPreferences();
        }
        UIView *keyboard = (UIView *)self;
        if (![keyboard isKindOfClass:UIView.class]) return;
        NSString *name = KGProbeKeyplaneName(keyboard);
        KGApplyThemeToKeyboard(keyboard, name ?: @"KeyboardMain");
    } @catch (NSException *e) { KGLog(@"exception layout: %@", e); }
}

static void KGInstallHooks(void) {
    Class layoutStar = NSClassFromString(@"UIKeyboardLayoutStar");
    if (!layoutStar) {
        KGLog(@"UIKeyboardLayoutStar missing, will retry");
        return;
    }

    if (!orig_setCurrentKeyboardLayoutStar) {
        MSHookMessageEx(layoutStar, @selector(setCurrentKeyboardLayoutStar:),
                        (IMP)KG_hooked_setCurrentKeyboardLayoutStar,
                        (IMP *)&orig_setCurrentKeyboardLayoutStar);
        KGLog(@"hook installed: setCurrentKeyboardLayoutStar:");
    }

    if (!orig_layoutStarLayout) {
        SEL layout = @selector(layoutSubviews);
        if ([layoutStar instancesRespondToSelector:layout]) {
            MSHookMessageEx(layoutStar, layout, (IMP)KG_hooked_layoutStarLayout,
                            (IMP *)&orig_layoutStarLayout);
            KGLog(@"hook installed: UIKeyboardLayoutStar layoutSubviews");
        } else {
            KGLog(@"layoutSubviews NOT found on UIKeyboardLayoutStar (!)");
        }
    }

    // 17.2.1 上候选切换方法的存在性盘点（供后续精修）
    for (NSString *selName in @[@"keyPlaneDidChange:", @"rawKeyPlaneDidChange:",
                                @"keyplaneDidChange:", @"setKeyplane:", @"_setKeyplane:",
                                @"setCurrentKeyplane:", @"keyplaneChanged:"]) {
        SEL sel = NSSelectorFromString(selName);
        KGLog(@"candidate %@ : %@", selName,
              [layoutStar instancesRespondToSelector:sel] ? @"EXISTS" : @"absent");
    }
}

__attribute__((constructor))
static void KGInitialize(void) {
    @autoreleasepool {
        KGReloadPreferences();
        KGLog(@"KeyboardGlass 0.2 init — enabled=%d theme='%@' resolved=%@",
              kgEnabled, kgActiveThemeName, kgResolvedThemePath);

        KGInstallHooks();

        // 类未就绪时延迟重试安装（幂等）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!NSClassFromString(@"UIKeyboardLayoutStar")) {
                KGLog(@"retry install: class still missing");
                return;
            }
            KGInstallHooks();
        });

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        &KGPreferencesChangedCallback,
                                        CFSTR(KG_CHANGED), NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
