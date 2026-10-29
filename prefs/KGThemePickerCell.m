#import "KGThemePickerCell.h"

#define KG_DOMAIN @"com.ning.keyboardglass"
#define KG_CHANGED @"com.ning.keyboardglass.changed"
#define KG_THEMES_DIR @"/var/jb/Library/KeyboardGlass/Themes"

@implementation KGThemePickerCell {
    UILabel *_valueLabel;
}

- (instancetype)initWithStyle:(long)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier])) {
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = [UIFont systemFontOfSize:15];
        _valueLabel.textColor = UIColor.secondaryLabelColor;
        _valueLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_valueLabel];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(kgPickTheme)];
        [self.contentView addGestureRecognizer:tap];
    }
    return self;
}

- (NSString *)kgCurrentTheme {
    CFPreferencesAppSynchronize((__bridge CFStringRef)KG_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("ActiveTheme"), (__bridge CFStringRef)KG_DOMAIN);
    NSString *out = v ? [(id)CFBridgingRelease(v) copy] : nil;
    return out;
}

- (void)kgSync {
    NSString *theme = [self kgCurrentTheme];
    _valueLabel.text = theme.length ? theme : @"未选择";
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    _valueLabel.frame = CGRectMake(w * 0.45, 12, w * 0.5, 24);
    [self kgSync];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self kgSync];
}

- (void)kgPickTheme {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择主题"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"不使用主题" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        CFPreferencesSetAppValue(CFSTR("ActiveTheme"), (__bridge CFPropertyListRef)@"",
                                 (__bridge CFStringRef)KG_DOMAIN);
        CFPreferencesAppSynchronize((__bridge CFStringRef)KG_DOMAIN);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             (__bridge CFStringRef)KG_CHANGED, NULL, NULL, true);
        [self kgSync];
    }]];

    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:KG_THEMES_DIR error:NULL];
    for (NSString *item in items) {
        if ([item hasPrefix:@"."]) continue;
        NSString *full = [KG_THEMES_DIR stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir] || !isDir) continue;

        [sheet addAction:[UIAlertAction actionWithTitle:item style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            CFPreferencesSetAppValue(CFSTR("ActiveTheme"), (__bridge CFPropertyListRef)item,
                                     (__bridge CFStringRef)KG_DOMAIN);
            CFPreferencesAppSynchronize((__bridge CFStringRef)KG_DOMAIN);
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 (__bridge CFStringRef)KG_CHANGED, NULL, NULL, true);
            [self kgSync];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    // iPad 需要锚点
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.contentView;
        sheet.popoverPresentationController.sourceRect = self.contentView.bounds;
    }

    [[self.windowOrNil rootViewController] presentViewController:sheet animated:YES completion:nil];
}

- (UIWindow *)windowOrNil {
    UIWindow *window = self.window;
    if (window) return window;
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow) return w;
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

@end
