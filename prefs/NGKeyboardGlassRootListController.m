#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <notify.h>
#import "NGKeyboardPreferenceStore.h"

// Minimal private declarations. Do not assume PSViewController's ivar layout.
@class PSSpecifier;
@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (NSArray *)specifiers;
@end

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
@end

@interface NGKeyboardGlassRootListController : PSListController
@property(nonatomic, strong) NSArray *ngSpecifiers;
@end

@implementation NGKeyboardGlassRootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"键盘玻璃";
}

- (NSArray *)specifiers {
    if (!self.ngSpecifiers) {
        self.ngSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        // Inherited table methods must see the same array. Runtime metadata
        // avoids hard-coding private superclass instance sizes/ivar offsets.
        Ivar ivar = class_getInstanceVariable(PSListController.class, "_specifiers");
        const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
        if (type && type[0] == '@') object_setIvar(self, ivar, self.ngSpecifiers);
    }
    return self.ngSpecifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    if (![[specifier propertyForKey:@"key"] isEqual:@"RenderingMode"]) return nil;
    return NGKeyboardReadStoredMode();
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if (![[specifier propertyForKey:@"key"] isEqual:@"RenderingMode"] ||
        ![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
        (![value isEqualToNumber:@0] && ![value isEqualToNumber:@1])) return;

    NSNumber *mode = @(NGKeyboardModeFromValue(value));
    NSMutableDictionary *preferences = [[NSDictionary dictionaryWithContentsOfFile:
        NG_KEYBOARD_PREFERENCES_PATH] mutableCopy] ?: [NSMutableDictionary dictionary];
    // Preserve other data in the domain; write only this pane's single key.
    preferences[@"RenderingMode"] = mode;
    CFPreferencesSetAppValue(NG_KEYBOARD_RENDERING_MODE_KEY,
        (__bridge CFPropertyListRef)mode, NG_KEYBOARD_PREFERENCES_DOMAIN);
    BOOL synchronized = CFPreferencesAppSynchronize(NG_KEYBOARD_PREFERENCES_DOMAIN);
    BOOL savedToUserFile = [preferences writeToFile:NG_KEYBOARD_PREFERENCES_PATH
        atomically:YES];
    // If the real file cannot be updated, the CFPreferences fallback is usable
    // only when it actually reads back the selected mode (no stale-file notice).
    if (savedToUserFile ||
        (synchronized && [NGKeyboardReadStoredMode() isEqualToNumber:mode])) {
        notify_post(NG_KEYBOARD_PREFERENCES_CHANGED);
    }
}

@end
