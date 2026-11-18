#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <os/log.h>
#ifndef APELIN_BUILD_ID
#define APELIN_BUILD_ID "untracked"
#endif

static void (*NGOriginalLayout)(id, SEL);
static void NGLayout(UIVisualEffectView *host, SEL selector) {
    NGOriginalLayout(host, selector);
    // Clear immediately, independently of Theseus capture or GPU readiness.
    if (host.effect != nil) host.effect = nil;
    if (![host.backgroundColor isEqual:UIColor.clearColor]) host.backgroundColor = UIColor.clearColor;
    if (![host.contentView.backgroundColor isEqual:UIColor.clearColor]) host.contentView.backgroundColor = UIColor.clearColor;
    Class bridge = NSClassFromString(@"NGTheseusBridge");
    SEL apply = NSSelectorFromString(@"applyTo:");
    if ([bridge respondsToSelector:apply]) {
        ((void (*)(id, SEL, id))objc_msgSend)(bridge, apply, host);
    }
}

static BOOL NGTryInstall(void) {
    Class cls = NSClassFromString(@"UIKBBackdropView");
    SEL sel = @selector(layoutSubviews);
    if (!cls || ![cls isSubclassOfClass:UIVisualEffectView.class]) return NO;
    Method method = class_getInstanceMethod(cls, sel);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char *type = method_copyReturnType(method);
    BOOL valid = type && strcmp(type, "v") == 0;
    free(type);
    if (!valid) return NO;
    typedef void (*Hook)(Class, SEL, IMP, IMP *);
    Hook hook = (Hook)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
    if (!hook) return NO;
    hook(cls, sel, (IMP)NGLayout, (IMP *)&NGOriginalLayout);
    os_log(os_log_create("com.ning.keyboardglass", "hook"), "UIKBBackdropView hook installed");
    return YES;
}

__attribute__((constructor)) static void NGInstall(void) {
    os_log(os_log_create("com.ning.keyboardglass", "load"), "ApelinLoaded %{public}s", APELIN_BUILD_ID);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (NGTryInstall()) return;
        // UIKit may load keyboard implementation after this dylib's constructor.
        __block unsigned attempts = 0;
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 10);
        dispatch_source_set_event_handler(timer, ^{
            if (NGTryInstall() || ++attempts >= 120) dispatch_source_cancel(timer);
        });
        dispatch_resume(timer);
    });
}
