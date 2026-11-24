#import <UIKit/UIKit.h>
#import "../GlassPreferences.h"

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
@end
@interface PSListController : UIViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
@end
@interface NGKeyboardGlassPrefsController : PSListController
@property(nonatomic, strong) NSArray *ngSpecifiers;
@end
@implementation NGKeyboardGlassPrefsController
- (NSArray *)specifiers {
    if (!self.ngSpecifiers) self.ngSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return self.ngSpecifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NGDomain);
    NSString *key = [specifier propertyForKey:@"key"];
    if (NGLimits()[key]) return NGEffectiveValues(NGSelectedSkin())[key];
    if ([key isEqual:@"Skin"]) return NGSelectedSkin();
    if ([key isEqual:@"SystemAlpha"]) return @(NGNumber(NGCopyPreference(key), 1, 0, 1));
    return [specifier propertyForKey:@"default"];
}
- (void)changed {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NGDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)NGChanged, NULL, NULL, true);
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    CFPreferencesAppSynchronize((__bridge CFStringRef)NGDomain);
    if (NGLimits()[key]) {
        NSString *skin = NGSelectedSkin();
        id saved = NGCopyPreference(@"Overrides");
        NSMutableDictionary *all = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
        NSMutableDictionary *selected = [NGOverridesForSkin(skin) mutableCopy];
        NSArray *range = NGLimits()[key];
        selected[key] = @(NGNumber(value, [NGBaseValues(skin)[key] doubleValue], [range[0] doubleValue], [range[1] doubleValue]));
        all[skin] = selected;
        CFPreferencesSetAppValue(CFSTR("Overrides"), (__bridge CFPropertyListRef)all, (__bridge CFStringRef)NGDomain);
    } else if ([key isEqual:@"Skin"] && [NGSkinIDs() containsObject:value]) {
        CFPreferencesSetAppValue(CFSTR("Skin"), (__bridge CFPropertyListRef)value, (__bridge CFStringRef)NGDomain);
    } else if ([key isEqual:@"SystemAlpha"]) {
        CFPreferencesSetAppValue(CFSTR("SystemAlpha"), (__bridge CFNumberRef)@(NGNumber(value,1,0,1)), (__bridge CFStringRef)NGDomain);
    } else return;
    [self changed];
    if ([key isEqual:@"Skin"]) {
        self.ngSpecifiers = nil;
        [self reloadSpecifiers];
    }
}
- (void)resetCurrentSkin {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NGDomain);
    id saved = NGCopyPreference(@"Overrides");
    NSMutableDictionary *all = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    [all removeObjectForKey:NGSelectedSkin()];
    CFPreferencesSetAppValue(CFSTR("Overrides"), (__bridge CFPropertyListRef)all, (__bridge CFStringRef)NGDomain);
    [self changed]; self.ngSpecifiers = nil; [self reloadSpecifiers];
}
- (void)resetAll {
    for (NSString *key in @[@"Skin",@"Overrides",@"SystemAlpha"]) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)NGDomain);
    }
    [self changed]; self.ngSpecifiers = nil; [self reloadSpecifiers];
}
@end
