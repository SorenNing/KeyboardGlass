// KeyboardGlass 键帽隐藏支持：hook UIKBTree 渲染管线（照 Laetus HideKeyCaps 方式）
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <CydiaSubstrate/CydiaSubstrate.h>

#import "KGCommon.h"

// UIKBVisualEffectView = 键盘背景模糊层；Laetus 用它控制键盘底材质
// 隐藏键帽：遍历 UIKBKeyView 设 alpha；阴影：清除 layer shadow
static IMP orig_layoutSubviews = NULL;

static void KG_hooked_keyViewLayout(id self, SEL _cmd) {
    ((void (*)(id, SEL))orig_layoutSubviews)(self, _cmd);
    @try {
        if (!kgEnabled) return;
        UIView *view = (UIView *)self;
        // UIKBKeyView 的 shadow 子层隐藏
        if (kgHideKeyShadows) {
            for (CALayer *layer in view.layer.sublayers) {
                if (layer.shadowOpacity > 0) layer.shadowOpacity = 0;
            }
        }
    } @catch (__unused NSException *e) {}
}

__attribute__((constructor))
static void KGKeyCapsInitialize(void) {
    @autoreleasepool {
        Class keyView = NSClassFromString(@"UIKBKeyView");
        if (!keyView) return;
        SEL layout = @selector(layoutSubviews);
        if ([keyView instancesRespondToSelector:layout]) {
            MSHookMessageEx(keyView, layout, (IMP)KG_hooked_keyViewLayout, (IMP *)&orig_layoutSubviews);
            KGLog(@"hook installed: UIKBKeyView layoutSubviews (shadow suppression)");
        }
    }
}
