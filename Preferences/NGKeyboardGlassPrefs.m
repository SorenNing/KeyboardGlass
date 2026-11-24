#import <UIKit/UIKit.h>
#import "../GlassPreferences.h"

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
@end
@interface PSViewController : UIViewController
@end
@interface PSListController : PSViewController
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target bundle:(NSBundle *)bundle;
- (NSArray *)specifiers;
- (void)setSpecifiers:(NSArray *)specifiers;
- (void)reloadSpecifiers;
- (NSInteger)numberOfGroups;
@end
@interface NGKeyboardGlassPrefsController : PSListController
@property(nonatomic, strong) NSArray *ngSpecifiers;
@property(nonatomic, assign) BOOL ngLoading;
@property(nonatomic, strong) id ngActiveObserver;
- (void)ngRebuildSpecifierState;
- (void)ngRefreshVisibleSettings;
@end
@implementation NGKeyboardGlassPrefsController
- (NSBundle *)bundle {
    return [NSBundle bundleForClass:NGKeyboardGlassPrefsController.class];
}
- (void)setSpecifiers:(NSArray *)rows {
    if (self.ngLoading) { [super setSpecifiers:rows]; return; }
    self.ngLoading=YES;
    @try {
        self.ngSpecifiers=rows;
        [super setSpecifiers:rows];
    } @finally { self.ngLoading=NO; }
}
- (NSArray *)specifiers {
    if (!self.ngSpecifiers && !self.ngLoading) {
        self.ngLoading = YES;
        @try {
            NSBundle *bundle = [self bundle];
            NSString *path = [bundle pathForResource:@"Root" ofType:@"plist"];
            NSArray *rows;
            if ([self respondsToSelector:@selector(loadSpecifiersFromPlistName:target:bundle:)]) {
                rows = [self loadSpecifiersFromPlistName:@"Root" target:self bundle:bundle];
            } else {
                rows = [self loadSpecifiersFromPlistName:@"Root" target:self];
            }
            // Keep the inherited specifier/group bookkeeping synchronized with
            // our cache through the framework setter, without guessing ivar offsets.
            self.ngSpecifiers = rows;
            [super setSpecifiers:rows];
            NSString *report = [NSString stringWithFormat:@"[KeyboardGlass Settings] time=%@ bundle=%@ Root=%@ parsed=%lu stored=%lu groups=%ld\n",
                NSDate.date, bundle.bundlePath, path, (unsigned long)rows.count,
                (unsigned long)[super specifiers].count, (long)[super numberOfGroups]];
            NSLog(@"%@", report);
            NSString *logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/KeyboardGlass-settings.log"];
            [report writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } @finally { self.ngLoading = NO; }
    }
    return self.ngSpecifiers;
}
- (void)ngRebuildSpecifierState {
    self.ngSpecifiers=nil;
    [super reloadSpecifiers];
    (void)[self specifiers];
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NGDomain);
    NSString *key = [specifier propertyForKey:@"key"];
    if (NGLimits()[key]) return NGEffectiveValues(NGSelectedSkin())[key];
    if ([key isEqual:@"HideCandidateControls"] || [key isEqual:@"MaterialBlurEnabled"]) {
        id value=NGCopyPreference(key);
        return @([value isKindOfClass:NSNumber.class] && [value boolValue]);
    }
    if ([key isEqual:@"MaterialBlurStrength"]) return @(NGNumber(NGCopyPreference(key),0.5,0,1));
    if ([key isEqual:@"Skin"]) return NGSelectedSkin();
    if ([key isEqual:@"SystemAlpha"]) return @(NGNumber(NGCopyPreference(key), 1, 0, 1));
    return [specifier propertyForKey:@"default"];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    __weak NGKeyboardGlassPrefsController *weakSelf=self;
    self.ngActiveObserver=[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            // Queue after the system Preferences resume handlers have run.
            dispatch_async(dispatch_get_main_queue(), ^{
                NGKeyboardGlassPrefsController *controller=weakSelf;
                if (controller.isViewLoaded && controller.view.window &&
                    controller.navigationController.topViewController==controller) {
                    [controller ngRefreshVisibleSettings];
                }
            });
        }];
}
- (void)dealloc {
    if (self.ngActiveObserver) [NSNotificationCenter.defaultCenter removeObserver:self.ngActiveObserver];
}
- (void)ngRefreshVisibleSettings {
    if (self.ngLoading) return;
    UITableView *table=[self.view isKindOfClass:UITableView.class] ? (UITableView *)self.view : nil;
    if (!table) {
        for (UIView *view in self.view.subviews) {
            if ([view isKindOfClass:UITableView.class]) { table=(UITableView *)view; break; }
        }
    }
    CGPoint offset=table ? table.contentOffset : CGPointZero;
    [self ngRebuildSpecifierState];
    [table reloadData];
    [table layoutIfNeeded];
    if (table) {
        CGFloat lo=-table.adjustedContentInset.top;
        CGFloat hi=MAX(lo,table.contentSize.height-table.bounds.size.height+table.adjustedContentInset.bottom);
        offset.y=MAX(lo,MIN(hi,offset.y));
        [table setContentOffset:offset animated:NO];
    }
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self ngRefreshVisibleSettings];
    // Publish existing values on upgrade without resetting any preferences.
    [self changed];
}
- (void)changed {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NGDomain);
    NSError *publishError=nil;
    BOOL published=NGPublishGlobalSnapshot(&publishError);
    NSString *status=[NSString stringWithFormat:@"[KeyboardGlass Settings] global-config=%@ path=%@ error=%@\n",
        published ? @"published" : @"failed", NGSnapshotPath, publishError];
    NSLog(@"%@",status);
    NSString *logPath=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/KeyboardGlass-settings-sync.log"];
    [status writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)NGChanged, NULL, NULL, true);
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    CFPreferencesAppSynchronize((__bridge CFStringRef)NGDomain);
    // Migrate the previously active skin before writing a new skin choice.
    NGMigrateSharedOverrides();
    if (NGLimits()[key]) {
        NSString *skin = NGSelectedSkin();
        id saved = NGCopyPreference(@"Overrides");
        NSMutableDictionary *all = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
        NSMutableDictionary *selected = [NGOverridesForSkin(skin) mutableCopy];
        NSArray *range = NGLimits()[key];
        selected[key] = @(NGNumber(value, [NGBaseValues(skin)[key] doubleValue], [range[0] doubleValue], [range[1] doubleValue]));
        all[@"*"] = selected;
        CFPreferencesSetAppValue(CFSTR("Overrides"), (__bridge CFPropertyListRef)all, (__bridge CFStringRef)NGDomain);
    } else if ([key isEqual:@"Skin"] && [NGSkinIDs() containsObject:value]) {
        CFPreferencesSetAppValue(CFSTR("Skin"), (__bridge CFPropertyListRef)value, (__bridge CFStringRef)NGDomain);
    } else if ([key isEqual:@"HideCandidateControls"] || [key isEqual:@"MaterialBlurEnabled"]) {
        if (![value isKindOfClass:NSNumber.class]) return;
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFNumberRef)@([value boolValue]), (__bridge CFStringRef)NGDomain);
    } else if ([key isEqual:@"MaterialBlurStrength"]) {
        CFPreferencesSetAppValue(CFSTR("MaterialBlurStrength"), (__bridge CFNumberRef)@(NGNumber(value,0.5,0,1)), (__bridge CFStringRef)NGDomain);
    } else if ([key isEqual:@"SystemAlpha"]) {
        CFPreferencesSetAppValue(CFSTR("SystemAlpha"), (__bridge CFNumberRef)@(NGNumber(value,1,0,1)), (__bridge CFStringRef)NGDomain);
    } else return;
    [self changed];
    if ([key isEqual:@"Skin"]) {
        [self ngRebuildSpecifierState];
    }
}
- (void)resetCurrentSkin {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NGDomain);
    id saved = NGCopyPreference(@"Overrides");
    NSMutableDictionary *all = [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    all[@"*"] = @{};
    CFPreferencesSetAppValue(CFSTR("Overrides"), (__bridge CFPropertyListRef)all, (__bridge CFStringRef)NGDomain);
    [self changed]; [self ngRebuildSpecifierState];
}
- (void)resetAll {
    for (NSString *key in @[@"Skin",@"Overrides",@"SystemAlpha",@"HideCandidateControls",@"MaterialBlurEnabled",@"MaterialBlurStrength",@"BlurEnabled",@"BlurStrength"]) {
        CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)NGDomain);
    }
    [self changed]; [self ngRebuildSpecifierState];
}
@end
