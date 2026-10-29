#import "KGThemePickerCell.h"

#define KG_DOMAIN @"com.ning.keyboardglass"
#define KG_CHANGED @"com.ning.keyboardglass.changed"
#define KG_THEMES_DIR @"/var/jb/Library/KeyboardGlass/Themes"

@implementation KGThemePickerCell {
    UILabel *_valueLabel;
    id _specifier;
}

- (instancetype)initWithStyle:(long)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier])) {
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        self.selectionStyle = UITableViewCellSelectionStyleDefault;
        _specifier = specifier;

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = [UIFont systemFontOfSize:15];
        _valueLabel.textColor = UIColor.secondaryLabelColor;
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_valueLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_valueLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_valueLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-34],
        ]];
    }
    return self;
}

+ (NSArray<NSString *> *)kgAllThemeNames {
    // 多根目录扫描（与 tweak 一致），/var/jb 优先
    NSArray *roots = @[KG_THEMES_DIR,
                       @"/var/mobile/Library/KeyboardGlass/Themes",
                       @"/Library/KeyboardGlass/Themes"];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *root in roots) {
        for (NSString *item in [fm contentsOfDirectoryAtPath:root error:NULL]) {
            if ([item hasPrefix:@"."]) continue;
            NSString *full = [root stringByAppendingPathComponent:item];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:full isDirectory:&isDir] && isDir && ![seen containsObject:item]) {
                [seen addObject:item];
                [out addObject:item];
            }
        }
    }
    return out;
}

- (NSString *)kgCurrentTheme {
    CFPreferencesAppSynchronize((__bridge CFStringRef)KG_DOMAIN);
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("ActiveTheme"), (__bridge CFStringRef)KG_DOMAIN);
    return v ? [(id)CFBridgingRelease(v) copy] : nil;
}

- (void)kgSync {
    NSString *theme = [self kgCurrentTheme];
    NSArray *all = [KGThemePickerCell kgAllThemeNames];
    if (theme.length) {
        _valueLabel.text = theme;
    } else if (all.count) {
        _valueLabel.text = [NSString stringWithFormat:@"自动（%@）", all.firstObject];
    } else {
        _valueLabel.text = @"未发现主题";
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self kgSync];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self kgSync];
}

- (void)kgApplyTheme:(NSString *)name {
    CFPreferencesSetAppValue(CFSTR("ActiveTheme"), (__bridge CFPropertyListRef)(name ?: @""),
                             (__bridge CFStringRef)KG_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)KG_DOMAIN);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)KG_CHANGED, NULL, NULL, true);
    [self kgSync];
}

// 点行弹出选择（PSListController 里 didSelectRowAtIndexPath 转发到这里）
- (void)kgPickTheme {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择主题"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *all = [KGThemePickerCell kgAllThemeNames];
    if (!all.count) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"没有发现主题目录" style:UIAlertActionStyleCancel handler:nil]];
        sheet.message = @"请先把主题文件夹放进 /var/jb/Library/KeyboardGlass/Themes/";
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"自动（第一个主题）" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [self kgApplyTheme:nil];
    }]];

    for (NSString *item in all) {
        [sheet addAction:[UIAlertAction actionWithTitle:item style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self kgApplyTheme:item];
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.contentView;
        sheet.popoverPresentationController.sourceRect = self.contentView.bounds;
    }

    UIWindow *window = self.window;
    if (!window) {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (w.isKeyWindow) { window = w; break; }
        }
        if (!window) window = UIApplication.sharedApplication.windows.firstObject;
    }
    UIViewController *presenter = window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    [presenter presentViewController:sheet animated:YES completion:nil];
}

@end
