// One labeled slider row inside the system's grouped card. No extra card layers.
@interface PSTableCell : UITableViewCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier;
@end
@interface NGGlassSliderCell : PSTableCell
@property(nonatomic,strong) PSSpecifier *ngSpecifier;
@property(nonatomic,strong) UILabel *ngTitle;
@property(nonatomic,strong) UILabel *ngValue;
@property(nonatomic,strong) UISlider *ngSlider;
@end
@implementation NGGlassSliderCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self=[super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self) {
        self.ngTitle=[UILabel new]; self.ngTitle.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        self.ngTitle.adjustsFontForContentSizeCategory=YES;
        self.ngValue=[UILabel new]; self.ngValue.font=[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        self.ngValue.textColor=UIColor.secondaryLabelColor; self.ngValue.textAlignment=NSTextAlignmentRight;
        self.ngSlider=[UISlider new]; self.ngSlider.tintColor=UIColor.systemBlueColor;
        [self.ngSlider addTarget:self action:@selector(ngChanged:) forControlEvents:UIControlEventValueChanged];
        for (UIView *v in @[self.ngTitle,self.ngValue,self.ngSlider]) [self.contentView addSubview:v];
        self.selectionStyle=UITableViewCellSelectionStyleNone;
        [self refreshCellContentsWithSpecifier:specifier];
    }
    return self;
}
- (NGKeyboardGlassPrefsController *)ngController {
    for (UIResponder *r=self.nextResponder;r;r=r.nextResponder)
        if ([r isKindOfClass:NGKeyboardGlassPrefsController.class]) return (id)r;
    return nil;
}
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    self.ngSpecifier=specifier;
    self.textLabel.text=nil; self.detailTextLabel.text=nil;
    self.ngTitle.text=[specifier name];
    self.ngSlider.minimumValue=[[specifier propertyForKey:@"min"] floatValue];
    self.ngSlider.maximumValue=[[specifier propertyForKey:@"max"] floatValue];
    self.ngSlider.accessibilityLabel=self.ngTitle.text;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w=self.contentView.bounds.size.width,h=self.contentView.bounds.size.height;
    BOOL rtl=self.effectiveUserInterfaceLayoutDirection==UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat valueWidth=70,pad=20;
    self.ngTitle.frame=CGRectMake(rtl ? pad+valueWidth+8 : pad,10,MAX(0,w-2*pad-valueWidth-8),25);
    self.ngValue.frame=CGRectMake(rtl ? pad : w-pad-valueWidth,10,valueWidth,25);
    self.ngSlider.frame=CGRectMake(pad,40,MAX(0,w-2*pad),MAX(31,h-48));
    if (!self.ngSlider.tracking) {
        NGKeyboardGlassPrefsController *controller=[self ngController];
        id value=controller ? [controller readPreferenceValue:self.ngSpecifier] : [self.ngSpecifier propertyForKey:@"default"];
        self.ngSlider.value=[value floatValue];
    }
    self.ngValue.text=[NSString stringWithFormat:@"%.2f",self.ngSlider.value];
}
- (void)ngChanged:(UISlider *)slider {
    NGKeyboardGlassPrefsController *controller=[self ngController];
    if (!controller) return;
    [controller setPreferenceValue:@(slider.value) specifier:self.ngSpecifier];
    self.ngValue.text=[NSString stringWithFormat:@"%.2f",slider.value];
}
@end
