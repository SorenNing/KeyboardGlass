#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <CydiaSubstrate/CydiaSubstrate.h>
#import "KGCommon.h"

// ---------------------------------------------------------------------------
// KeyboardGlass — 键盘美化（照 Laetus 图像主题实现方式）
//  - 注入 UIKit/UIKitCore 宿主进程
//  - 跟踪 keyplane 变化（KeyboardMain/Numbers/Emoji/Dictation × 横竖屏）
//  - 主题图按 keyplane 命名：KeyboardMainBGPortrait-896h@3x.png 等
//  - 背景/前景双 UIImageView 插到键盘视图层级最上/最下
//  - 可选隐藏原键帽/阴影；UIKBCachedImage 缓存贴图一并清掉
// ---------------------------------------------------------------------------

#define KG_DOMAIN       "com.ning.keyboardglass"
#define KG_CHANGED      "com.ning.keyboardglass.changed"
#define KG_REFRESH      "com.ning.keyboardglass.refresh"
#define KG_THEMES_DIR   "/var/jb/Library/KeyboardGlass/Themes"
#define KG_PREFS_PATH   "/var/mobile/Library/Preferences/com.ning.keyboardglass.plist"

#pragma mark - 偏好读取

BOOL kgEnabled = YES;
BOOL kgHideKeyCaps = NO;
BOOL kgHideKeyShadows = NO;
CGFloat kgBackgroundAlpha = 1.0;
static NSString *kgActiveTheme = nil;          // 主题目录名
static NSString *kgResolvedThemePath = nil;    // 全路径（含 jbroot 归一化）

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

static void KGReloadPreferences(void) {
    kgEnabled        = KGBoolDefault(@"Enabled", YES);
    kgHideKeyCaps    = KGBoolDefault(@"HideKeyCaps", NO);
    kgHideKeyShadows = KGBoolDefault(@"HideKeyShadows", NO);
    kgBackgroundAlpha= KGNumberDefault(@"BackgroundAlpha", 1.0);
    CFPreferencesAppSynchronize(CFSTR(KG_DOMAIN));
    CFPropertyListRef t = CFPreferencesCopyAppValue(CFSTR("ActiveTheme"), CFSTR(KG_DOMAIN));
    NSString *theme = t ? [(id)CFBridgingRelease(t) copy] : nil;
    if (!kgActiveTheme || ![kgActiveTheme isEqualToString:theme]) {
        kgActiveTheme = theme;
        kgResolvedThemePath = nil; // 触发重查
    } else {
        kgActiveTheme = theme;
    }
    if (kgActiveTheme.length) {
        NSString *dir = [NSString stringWithFormat:@"%@/%@", @KG_THEMES_DIR, kgActiveTheme];
        if ([[NSFileManager defaultManager] fileExistsAtPath:dir]) kgResolvedThemePath = dir;
        else kgResolvedThemePath = nil;
    } else {
        kgResolvedThemePath = nil;
    }
}

// 调试日志（/var/mobile/Library/KeyboardGlass.log）
void KGLog(NSString *format, ...) {
    static NSInteger kgLogLines = -1;
    if (kgLogLines < 0) {
        kgLogLines = 0;
        unlink("/var/mobile/Library/KeyboardGlass.log");
    }
    if (kgLogLines > 4000) return;
    va_list args; va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *stamp = [NSString stringWithFormat:@"[%@] %@\n",
        [NSDate.date descriptionWithLocale:@"HH:mm:ss"], line];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@"/var/mobile/Library/KeyboardGlass.log"];
    if (!fh) {
        [@"" writeToFile:@"/var/mobile/Library/KeyboardGlass.log" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        fh = [NSFileHandle fileHandleForWritingAtPath:@"/var/mobile/Library/KeyboardGlass.log"];
    }
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[stamp dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    kgLogLines++;
}

#pragma mark - 主题图查找

// 与 iOS 键盘内部命名一致（Laetus 同款约定）：
//   KeyboardMainBG / KeyboardNumbersBG / KeyboardEmojiBG / KeyboardDictationBG
//   KeyboardPredictionBarBG / KeyboardEmojiSearchBarBG / KeyboardEmojiSearchBarExpandedBG
//   KeyboardLettersKeyPlane / KeyboardNumbersKeyPlane
//   -Portrait / -Landscape，机型后缀（896h 等）可选，@2x/@3x
// 查找优先级：机型屏高后缀 > 无后缀；@3x > @2x > 无

static NSString *KGDeviceHeightSuffix(void) {
    static NSString *suffix;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGFloat h = UIScreen.mainScreen.bounds.size.height * UIScreen.mainScreen.scale;
        if      (h >= 2680) suffix = @"1792h";  // XR/XS Max/11 系
        else if (h >= 2660) suffix = @"896h";   // X/11 Pro/12 mini 系… 以实机为准
        else if (h >= 2430) suffix = @"926h";   // 14/15 Pro Max (2796)
        else if (h >= 2200) suffix = @"844h";   // 12/13/14 系
        else if (h >= 1900) suffix = @"667h";
        else suffix = @"";
        // 2796 (926h) 先判大屏
        if (h >= 2790) suffix = @"926h";
    });
    return suffix;
}

static UIImage *KGImageForBaseName(NSString *base) {
    if (!kgResolvedThemePath) return nil;
    // 机型屏高后缀优先，其次通用（无后缀）
    NSArray *heights = @[ [KGDeviceHeightSuffix() stringByReplacingOccurrencesOfString:@"h" withString:@""].length ? KGDeviceHeightSuffix() : @"", @"" ];
    NSArray *scales  = @[@"@3x", @"@2x", @""];
    for (NSString *height in heights) {
        for (NSString *scale in scales) {
            NSString *name = [NSString stringWithFormat:@"%@%@%@.png", base, height, scale];
            NSString *path = [kgResolvedThemePath stringByAppendingPathComponent:name];
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                UIImage *img = [UIImage imageWithContentsOfFile:path];
                if (img) { img = [UIImage imageWithCGImage:img.CGImage scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp]; }
                return img;
            }
        }
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
    return [NSString stringWithFormat:@"%@|%@", keyplaneName ?: @"", landscape ? @"L" : @"P"];
}

static void KGApplyThemeToKeyboard(UIView *keyboard, NSString *keyplaneName) {
    if (!keyboard || !kgEnabled || !kgResolvedThemePath) return;

    BOOL landscape = UIScreen.mainScreen.bounds.size.width > UIScreen.mainScreen.bounds.size.height;
    NSString *signature = KGKeyplaneSignature(keyplaneName, landscape);

    // 状态去重：同一 keyplane + 方向已应用过则跳过
    NSString *last = objc_getAssociatedObject(keyboard, &kKGAssocCurrentKey);
    if ([last isEqualToString:signature]) return;
    objc_setAssociatedObject(keyboard, &kKGAssocCurrentKey, signature, OBJC_ASSOCIATION_COPY_NONATOMIC);

    // 基名 = <Keyplane 面名>BG + 方向
    // keyplaneName 形如 "KeyboardMain" / "KeyboardNumbers" / "KeyboardEmoji" …
    NSString *base = [NSString stringWithFormat:@"%@BG", keyplaneName ?: @""];
    UIImage *bg = KGImageForBaseName([base stringByAppendingString:landscape ? @"Landscape" : @"Portrait"]);
    if (!bg) bg = KGImageForBaseName([base stringByAppendingString:landscape ? @"-Landscape" : @"-Portrait"]);

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
            // 放在最底层（index 0），键帽画在上面
            [keyboard insertSubview:bgView atIndex:0];
            KGLog(@"insert background for %@ (%@)", keyplaneName, signature);
        }
        KGLog(@"theme bg applied: %@ -> %@x%@", signature, @(bg.size.width), @(bg.size.height));
    } else {
        bgView.image = nil;
    }

    // 前景图（可选覆盖层，如毛玻璃蒙层素材）
    UIImage *fg = KGImageForBaseName([NSString stringWithFormat:@"%@FG%@", keyplaneName ?: @"", landscape ? @"Landscape" : @"Portrait"]);
    if (fg) {
        fgView.image = fg;
        fgView.frame = keyboard.bounds;
        fgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        if (!fgView.superview) [keyboard addSubview:fgView];
    } else if (fgView.superview) {
        fgView.image = nil;
    }

    [CATransaction commit];
}

#pragma mark - Hook 核心

// 设置变更通知回调（C 函数指针，CF 要求）
static void KGPreferencesChangedCallback(CFNotificationCenterRef center, void *observer,
                                         CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    KGReloadPreferences();
    KGLog(@"preferences changed: theme=%@ enabled=%d", kgActiveTheme, kgEnabled);
}

// UIKeyboardLayoutStar = 键盘根视图（Laetus 主要 hook 点）
static IMP orig_setCurrentKeyboardLayoutStar = NULL;

static void KG_hooked_setCurrentKeyboardLayoutStar(id self, SEL _cmd, id layoutStar) {
    ((void (*)(id, SEL, id))orig_setCurrentKeyboardLayoutStar)(self, _cmd, layoutStar);
    @try {
        if (!kgEnabled) return;
        KGReloadPreferences();
        // 延迟到布局完成后应用
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *keyboard = (UIView *)self;
            if (![keyboard isKindOfClass:UIView.class]) return;
            KGApplyThemeToKeyboard(keyboard, @"KeyboardMain");
        });
    } @catch (NSException *e) { KGLog(@"exception setCurrentLayout: %@", e); }
}

// keyplane 切换（字母/数字/emoji）
static IMP orig_keyPlaneDidChange = NULL;
static void KG_hooked_keyPlaneDidChange(id self, SEL _cmd, id context) {
    ((void (*)(id, SEL, id))orig_keyPlaneDidChange)(self, _cmd, context);
    @try {
        if (!kgEnabled) return;
        KGReloadPreferences();
        NSString *name = nil;
        @try { name = [self valueForKey:@"keyplaneName"]; } @catch (__unused NSException *e) {}
        if (!name.length) name = @"KeyboardMain";
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *keyboard = (UIView *)self;
            if ([keyboard isKindOfClass:UIView.class]) KGApplyThemeToKeyboard(keyboard, name);
        });
    } @catch (NSException *e) { KGLog(@"exception keyPlaneDidChange: %@", e); }
}

__attribute__((constructor))
static void KGInitialize(void) {
    @autoreleasepool {
        KGReloadPreferences();
        KGLog(@"KeyboardGlass init — enabled=%d theme=%@", kgEnabled, kgActiveTheme);

        // 目标类（宿主进程 = UIKit 键盘）
        Class layoutStar = NSClassFromString(@"UIKeyboardLayoutStar");
        if (!layoutStar) {
            // iOS 17 实测 UIKeyboardLayoutStar 存在；保底再试一遍延迟安装
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                Class c = NSClassFromString(@"UIKeyboardLayoutStar");
                KGLog(@"retry: UIKeyboardLayoutStar = %@", c);
            });
            return;
        }

        MSHookMessageEx(layoutStar, @selector(setCurrentKeyboardLayoutStar:),
                        (IMP)KG_hooked_setCurrentKeyboardLayoutStar,
                        (IMP *)&orig_setCurrentKeyboardLayoutStar);
        KGLog(@"hook installed: UIKeyboardLayoutStar setCurrentKeyboardLayoutStar:");

        SEL kpSel = NSSelectorFromString(@"keyPlaneDidChange:");
        if ([layoutStar instancesRespondToSelector:kpSel]) {
            MSHookMessageEx(layoutStar, kpSel, (IMP)KG_hooked_keyPlaneDidChange,
                            (IMP *)&orig_keyPlaneDidChange);
            KGLog(@"hook installed: keyPlaneDidChange:");
        } else {
            KGLog(@"keyPlaneDidChange: NOT found on UIKeyboardLayoutStar");
        }

        // 设置变更即时生效
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        &KGPreferencesChangedCallback,
                                        CFSTR(KG_CHANGED), NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
