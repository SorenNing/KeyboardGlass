#pragma once

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

// Shared only by the reader and the Settings bundle. Never derive user
// preferences from the dylib/bundle path or a rootless/RootHide install prefix.
#define NG_KEYBOARD_PREFERENCES_DOMAIN CFSTR("com.ning.keyboardglass")
#define NG_KEYBOARD_RENDERING_MODE_KEY CFSTR("RenderingMode")
#define NG_KEYBOARD_PREFERENCES_CHANGED "com.ning.keyboardglass.changed"
#define NG_KEYBOARD_PREFERENCES_PATH \
    @"/var/mobile/Library/Preferences/com.ning.keyboardglass.plist"

static inline int NGKeyboardModeFromValue(id value) {
    if (![value isKindOfClass:NSNumber.class]) return 0;
    // Reject booleans, strings, fractional values and unknown future modes.
    if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return 0;
    return [value isEqualToNumber:@1] ? 1 : 0;
}

static inline NSNumber *NGKeyboardReadStoredMode(void) {
    CFPreferencesAppSynchronize(NG_KEYBOARD_PREFERENCES_DOMAIN);
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:
        NG_KEYBOARD_PREFERENCES_PATH];
    id value = preferences[@"RenderingMode"];
    // On rootless/RootHide devices, a sandbox/container CFPreferences domain
    // must not override a value in the real mobile user's preference file.
    if (!value) {
        value = CFBridgingRelease(CFPreferencesCopyAppValue(
            NG_KEYBOARD_RENDERING_MODE_KEY, NG_KEYBOARD_PREFERENCES_DOMAIN));
    }
    return @(NGKeyboardModeFromValue(value));
}
