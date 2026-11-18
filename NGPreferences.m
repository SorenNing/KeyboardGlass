#import "NGPreferences.h"
#import "prefs/NGKeyboardPreferenceStore.h"
#import <dispatch/dispatch.h>
#include <stdatomic.h>

static atomic_int NGRenderingMode = ATOMIC_VAR_INIT(0);
static void (*NGChangedCallback)(void);
static char NGObserverContext;

void NGKeyboardPreferencesReload(void) {
    @autoreleasepool {
        atomic_store_explicit(&NGRenderingMode,
            NGKeyboardReadStoredMode().intValue, memory_order_release);
    }
}

static void NGKeyboardLoadInitialPreferences(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NGKeyboardPreferencesReload();
    });
}

int NGKeyboardRenderingMode(void) {
    NGKeyboardLoadInitialPreferences();
    return atomic_load_explicit(&NGRenderingMode, memory_order_acquire);
}

static void NGKeyboardPreferencesChanged(
    __unused CFNotificationCenterRef center,
    __unused void *observer,
    __unused CFNotificationName name,
    __unused const void *object,
    __unused CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NGKeyboardPreferencesReload();
        if (NGChangedCallback) NGChangedCallback();
    });
}

void NGKeyboardPreferencesObserve(void (*callback)(void)) {
    static dispatch_once_t observerOnce;
    dispatch_once(&observerOnce, ^{
        NGChangedCallback = callback;
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), &NGObserverContext,
            NGKeyboardPreferencesChanged,
            CFSTR(NG_KEYBOARD_PREFERENCES_CHANGED), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        // Register before reloading, so a change during initialization is not
        // lost between the initial read and the notification subscription.
        NGKeyboardLoadInitialPreferences();
        NGKeyboardPreferencesReload();
    });
}
