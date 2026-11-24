#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>
#import <dlfcn.h>

// Grants read access to this tweak's configuration only; never to App data.
static NSInteger NGConfigAccessStatus = -1;
static NSString *NGConfigReadError;
static inline int NGAcquireConfigReadAccess(void) {
    typedef int (*ApplyProfile)(const char *);
    static ApplyProfile apply;
    static void *handle;
    if (!apply) apply=(ApplyProfile)dlsym(RTLD_DEFAULT,"libSandy_applyProfile");
    if (!apply) {
        Dl_info info={0};
        NSString *root=nil;
        if (dladdr((const void *)&NGAcquireConfigReadAccess,&info) && info.dli_fname) {
            NSString *library=[NSString stringWithUTF8String:info.dli_fname];
            for (NSString *suffix in @[@"/Library/MobileSubstrate/DynamicLibraries/", @"/usr/lib/TweakInject/"]) {
                NSRange range=[library rangeOfString:suffix options:NSBackwardsSearch];
                if (range.location!=NSNotFound) { root=[library substringToIndex:range.location]; break; }
            }
        }
        // Derive the active RootHide prefix from this injected library, not a
        // hardcoded .jbroot UUID or an App-specific container path.
        if (root) {
            NSString *path=[root stringByAppendingString:@"/usr/lib/libsandy.dylib"];
            handle=dlopen(path.fileSystemRepresentation,RTLD_NOW|RTLD_LOCAL);
        }
        if (!handle) handle=dlopen("/usr/lib/libsandy.dylib",RTLD_NOW|RTLD_LOCAL);
        if (handle) apply=(ApplyProfile)dlsym(handle,"libSandy_applyProfile");
    }
    if (!apply) return -1;
    return apply("KeyboardGlass_ReadConfig");
}

static NSString *const NGDomain = @"com.ning.keyboardglass";
static NSString *const NGChanged = @"com.ning.keyboardglass/ReloadPrefs";
static inline NSArray<NSString *> *NGSkinIDs(void) {
    return @[@"default", @"clear", @"frost", @"crystal", @"ice", @"smoke", @"liquid"];
}
static inline NSDictionary<NSString *, NSNumber *> *NGBaseValues(NSString *skin) {
    NSMutableDictionary *v = [@{@"BodyRed":@1, @"BodyGreen":@1, @"BodyBlue":@1,
        @"BodyOpacity":@0.059, @"BodyBrightness":@1, @"GradientStrength":@0,
        @"GradientAngle":@90, @"HighlightThickness":@1, @"HighlightBrightness":@0.49,
        @"HighlightWidth":@2, @"InnerShadow":@0, @"OuterShadow":@0,
        @"EdgeSoftness":@0.4, @"CornerRadius":@14, @"CornerShape":@2} mutableCopy];
    if ([skin isEqual:@"clear"]) [v addEntriesFromDictionary:@{@"BodyOpacity":@0.025,@"HighlightBrightness":@0.3,@"HighlightThickness":@0.5}];
    if ([skin isEqual:@"frost"]) [v addEntriesFromDictionary:@{@"BodyOpacity":@0.2,@"BodyBlue":@0.99,@"HighlightBrightness":@0.25,@"HighlightWidth":@4,@"EdgeSoftness":@1.5}];
    if ([skin isEqual:@"crystal"]) [v addEntriesFromDictionary:@{@"BodyOpacity":@0.05,@"HighlightThickness":@1.6,@"HighlightBrightness":@0.8,@"HighlightWidth":@6,@"InnerShadow":@0.25,@"OuterShadow":@0.15}];
    if ([skin isEqual:@"ice"]) [v addEntriesFromDictionary:@{@"BodyRed":@0.7,@"BodyGreen":@0.87,@"BodyBlue":@1,@"BodyOpacity":@0.13,@"HighlightBrightness":@0.6,@"GradientStrength":@0.12}];
    if ([skin isEqual:@"smoke"]) [v addEntriesFromDictionary:@{@"BodyRed":@0.15,@"BodyGreen":@0.18,@"BodyBlue":@0.23,@"BodyOpacity":@0.3,@"HighlightBrightness":@0.3,@"InnerShadow":@0.2}];
    if ([skin isEqual:@"liquid"]) [v addEntriesFromDictionary:@{@"BodyOpacity":@0.059,@"HighlightThickness":@1.2,@"HighlightBrightness":@0.75,@"HighlightWidth":@5,@"InnerShadow":@0.24,@"OuterShadow":@0.08,@"GradientStrength":@0.12,@"EdgeSoftness":@0.6,@"CornerShape":@2.8}];
    return v;
}
static inline NSDictionary *NGLimits(void) {
    return @{@"BodyRed":@[@0,@1],@"BodyGreen":@[@0,@1],@"BodyBlue":@[@0,@1],
        @"BodyOpacity":@[@0,@1],@"BodyBrightness":@[@0,@1.5],
        @"GradientStrength":@[@0,@1],@"GradientAngle":@[@0,@360],
        @"HighlightThickness":@[@0,@4],@"HighlightBrightness":@[@0,@1],
        @"HighlightWidth":@[@0,@14],@"InnerShadow":@[@0,@1],@"OuterShadow":@[@0,@1],
        @"EdgeSoftness":@[@0,@5],@"CornerRadius":@[@0,@40],@"CornerShape":@[@2,@5]};
}
static inline double NGNumber(id value, double fallback, double lo, double hi) {
    if (![value isKindOfClass:NSNumber.class]) return fallback;
    double x = [value doubleValue];
    return isfinite(x) ? fmin(hi, fmax(lo, x)) : fallback;
}
// Each injected App consumes one immutable global snapshot, not its sandbox domain.
static NSDictionary *NGGlobalSnapshot;
static NSString *const NGSnapshotPath = @"/var/mobile/Library/Accessibility/KeyboardGlass-preferences.plist";
static inline NSDictionary *NGValidateSnapshot(id envelope) {
    if (![envelope isKindOfClass:NSDictionary.class] ||
        ![envelope[@"Schema"] isEqual:@1]) return nil;
    id config=envelope[@"Configuration"];
    if (![config isKindOfClass:NSDictionary.class]) return nil;
    if (![NGSkinIDs() containsObject:config[@"Skin"]] ||
        ![config[@"SystemAlpha"] isKindOfClass:NSNumber.class] ||
        ![config[@"Overrides"] isKindOfClass:NSDictionary.class]) return nil;
    // Optional for compatibility with snapshots published by 0.1.16 and earlier.
    if (config[@"HideCandidateControls"] && ![config[@"HideCandidateControls"] isKindOfClass:NSNumber.class]) return nil;
    double alpha=[config[@"SystemAlpha"] doubleValue];
    if (!isfinite(alpha) || alpha<0 || alpha>1) return nil;
    for (id key in config[@"Overrides"]) {
        if (![key isKindOfClass:NSString.class] ||
            ![config[@"Overrides"][key] isKindOfClass:NSDictionary.class]) return nil;
    }
    return config;
}
static inline BOOL NGLoadGlobalSnapshot(void) {
    NSError *error=nil;
    NSData *data=[NSData dataWithContentsOfFile:NGSnapshotPath options:0 error:&error];
    if (!data) {
        static CFAbsoluteTime lastAttempt=-100;
        CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();
        if (now-lastAttempt>=5) {
            lastAttempt=now;
            NGConfigAccessStatus=NGAcquireConfigReadAccess();
        }
        error=nil;
        data=[NSData dataWithContentsOfFile:NGSnapshotPath options:0 error:&error];
    }
    NGConfigReadError=error ? [NSString stringWithFormat:@"%@:%ld",error.domain,(long)error.code] : nil;
    id envelope=data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error] : nil;
    NSDictionary *config=NGValidateSnapshot(envelope);
    // A transient unreadable/corrupt update must not discard a known-good snapshot.
    if (!config) {
        if (data) NGConfigReadError=error ? [NSString stringWithFormat:@"%@:%ld",error.domain,(long)error.code] : @"invalid-schema";
        return NO;
    }
    NGConfigReadError=nil;
    NGGlobalSnapshot=[config copy];
    return YES;
}
// Settings-only migration. Keep legacy entries as a backup; '*' takes precedence
// even when empty, so cleared shared adjustments cannot resurrect old values.
static inline void NGMigrateSharedOverrides(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NGDomain);
    id saved=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Overrides"),(__bridge CFStringRef)NGDomain));
    if ([saved isKindOfClass:NSDictionary.class] && [saved[@"*"] isKindOfClass:NSDictionary.class]) return;
    id skin=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Skin"),(__bridge CFStringRef)NGDomain));
    if (![NGSkinIDs() containsObject:skin]) skin=@"default";
    NSMutableDictionary *all=[saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    id legacy=all[skin];
    all[@"*"]=[legacy isKindOfClass:NSDictionary.class] ? [legacy copy] : @{};
    CFPreferencesSetAppValue(CFSTR("Overrides"),(__bridge CFDictionaryRef)all,(__bridge CFStringRef)NGDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)NGDomain);
}
static inline BOOL NGPublishGlobalSnapshot(NSError **error) {
    NGMigrateSharedOverrides();
    CFPreferencesAppSynchronize((__bridge CFStringRef)NGDomain);
    id skin=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Skin"),(__bridge CFStringRef)NGDomain));
    id alpha=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("SystemAlpha"),(__bridge CFStringRef)NGDomain));
    id overrides=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Overrides"),(__bridge CFStringRef)NGDomain));
    id hide=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("HideCandidateControls"),(__bridge CFStringRef)NGDomain));
    NSDictionary *config=@{@"Skin":[NGSkinIDs() containsObject:skin] ? skin : @"default",
        @"HideCandidateControls":@([hide isKindOfClass:NSNumber.class] && [hide boolValue]),
        @"SystemAlpha":@(NGNumber(alpha,1,0,1)),
        @"Overrides":[overrides isKindOfClass:NSDictionary.class] ? overrides : @{}};
    NSDictionary *envelope=@{@"Schema":@1,@"Configuration":config};
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:envelope format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data) return NO;
    if (![data writeToFile:NGSnapshotPath options:NSDataWritingAtomic error:error]) return NO;
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:NGSnapshotPath error:error];
}
static inline id NGCopyPreference(NSString *key) {
    if (NGGlobalSnapshot) return NGGlobalSnapshot[key];
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)NGDomain));
}
static inline NSString *NGSelectedSkin(void) {
    id skin = NGCopyPreference(@"Skin");
    return [NGSkinIDs() containsObject:skin] ? skin : @"default";
}
// The '*' entry contains explicitly adjusted values shared by every skin.
// Legacy data has only per-skin entries; use the active skin until Settings migrates it.
static inline NSDictionary *NGSharedOverrides(id all, NSString *skin) {
    if (![all isKindOfClass:NSDictionary.class]) return @{};
    id shared=all[@"*"];
    if ([shared isKindOfClass:NSDictionary.class]) return shared;
    id legacy=all[skin];
    return [legacy isKindOfClass:NSDictionary.class] ? legacy : @{};
}
static inline NSDictionary *NGOverridesForSkin(NSString *skin) {
    return NGSharedOverrides(NGCopyPreference(@"Overrides"),skin);
}
static inline NSDictionary *NGEffectiveValues(NSString *skin) {
    NSMutableDictionary *v = [NGBaseValues(skin) mutableCopy];
    NSDictionary *saved = NGOverridesForSkin(skin), *limits = NGLimits();
    for (NSString *key in limits) {
        NSArray *range = limits[key];
        v[key] = @(NGNumber(saved[key], [v[key] doubleValue], [range[0] doubleValue], [range[1] doubleValue]));
    }
    return v;
}
