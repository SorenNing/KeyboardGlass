#import "RootListController.h"

#define KG_DOMAIN @"com.ning.keyboardglass"
#define KG_CHANGED @"com.ning.keyboardglass.changed"
#define KG_THEMES_DIR @"/var/jb/Library/KeyboardGlass/Themes"

@implementation KeyboardGlassRootListController

-(instancetype)init {
    if ((self = [super init])) self.title = @"KeyboardGlass";
    return self;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"KeyboardGlass";
    [[NSFileManager defaultManager] createDirectoryAtPath:KG_THEMES_DIR
                              withIntermediateDirectories:YES attributes:nil error:NULL];
}

-(id)preferencesPlistName {
    return @"Root";
}

-(id)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];
    }
    return _specifiers;
}

-(id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *domain = [specifier propertyForKey:@"defaults"] ?: KG_DOMAIN;
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)domain);
    if (value) return (__bridge_transfer id)value;
    return [specifier propertyForKey:@"default"];
}

-(void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    NSString *domain = [specifier propertyForKey:@"defaults"] ?: KG_DOMAIN;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)domain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)KG_CHANGED, NULL, NULL, true);
}

#pragma mark - 主题目录按钮

-(void)kgAlertWithTitle:(NSString *)title message:(NSString *)message copyPath:(NSString *)path {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    if (path.length) {
        [alert addAction:[UIAlertAction actionWithTitle:@"复制路径" style:UIAlertActionStyleDefault
                                                handler:^(__unused UIAlertAction *action) {
            UIPasteboard.generalPasteboard.string = path;
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

-(void)openThemesFolder:(PSSpecifier *)specifier {
    [[NSFileManager defaultManager] createDirectoryAtPath:KG_THEMES_DIR
                              withIntermediateDirectories:YES attributes:nil error:NULL];

    NSArray<NSString *> *candidates = @[
        [NSString stringWithFormat:@"filza://view%@", KG_THEMES_DIR],
        [NSString stringWithFormat:@"shareddocuments://%@", KG_THEMES_DIR],
    ];

    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *string in candidates) {
        NSURL *url = [NSURL URLWithString:string];
        if (url) [urls addObject:url];
    }
    [self tryOpenFolderURLs:urls index:0 path:KG_THEMES_DIR];
}

-(void)tryOpenFolderURLs:(NSArray<NSURL *> *)urls index:(NSUInteger)index path:(NSString *)path {
    if (index >= urls.count) {
        [self kgAlertWithTitle:@"主题目录"
                        message:[NSString stringWithFormat:@"没能打开文件管理器，请用 Filza 进入：\n%@", path]
                       copyPath:path];
        return;
    }

    [UIApplication.sharedApplication openURL:urls[index] options:@{} completionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) return;
            [self tryOpenFolderURLs:urls index:index + 1 path:path];
        });
    }];
}

-(void)listThemes:(PSSpecifier *)specifier {
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:KG_THEMES_DIR error:NULL];
    NSMutableString *msg = [NSMutableString stringWithString:@"已发现的主题目录：\n\n"];
    BOOL any = NO;
    for (NSString *item in items) {
        if ([item hasPrefix:@"."]) continue;
        NSString *full = [KG_THEMES_DIR stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir] && isDir) {
            [msg appendFormat:@"• %@\n", item];
            any = YES;
        }
    }
    if (!any) [msg appendString:@"（还没有主题，先建一个主题文件夹放入 PNG）"];
    [self kgAlertWithTitle:@"当前主题列表" message:msg copyPath:nil];
}

@end
