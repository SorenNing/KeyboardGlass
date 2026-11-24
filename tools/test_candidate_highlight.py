"""Production highlight helpers against Foundation view stand-ins, not UIKit."""
from pathlib import Path
import subprocess,tempfile
P=Path(__file__).resolve().parents[1]
s=(P/'CandidateHighlight.h').read_text().split('static void NGInstallCandidateHighlightHooks(void)')[0]
prefix=r'''#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
@interface UIColor:NSObject
+ (instancetype)clearColor;
@end
@implementation UIColor
+ (instancetype)clearColor { static UIColor *c; if(!c)c=[self new]; return c; }
@end
@interface UIView:NSObject
@property(nonatomic,getter=isHidden) BOOL hidden;
@property(nonatomic,strong) NSString *text;
@property(nonatomic,strong) NSString *textColor;
@property(nonatomic,strong) id backgroundImage;
@property(nonatomic,strong) id color;
@property(nonatomic) BOOL selected;
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) id window;
- (BOOL)isDescendantOfView:(UIView *)view;
- (void)setNeedsLayout;
@end
@implementation UIView
- (BOOL)isDescendantOfView:(UIView *)view { for(UIView *v=self;v;v=v.superview)if(v==view)return YES;return NO; }
- (void)setNeedsLayout {}
@end
@interface UICollectionViewCell:UIView
@end
@implementation UICollectionViewCell
@end
@interface TUICandidateBaseCell:UICollectionViewCell
- (void)updateBackground:(id)image color:(id)color;
- (void)updateColors;
@end
@implementation TUICandidateBaseCell
- (void)updateBackground:(id)image color:(id)color { self.backgroundImage=image;self.color=color; }
- (void)updateColors { [self updateBackground:@"current-native-image" color:@"current-native-color"]; }
@end
@interface TUICandidateCell:TUICandidateBaseCell
@end
@implementation TUICandidateCell
@end
@interface TUICandidateGrid:UIView
@property(nonatomic,strong) UIView *selectedRowHighlightView;
@end
@implementation TUICandidateGrid
@end
static BOOL NGHideCandidateHighlight;
static BOOL NGHasVoidMethod(Class cls,SEL selector) {
 Method m=class_getInstanceMethod(cls,selector);if(!m || method_getNumberOfArguments(m)!=2)return NO;
 char *ret=method_copyReturnType(m);BOOL ok=strcmp(ret,"v")==0;free(ret);return ok;
}
'''
suffix=r'''
static void originalPaint(id cell,SEL cmd,id image,id color) { (void)cmd;[cell updateBackground:image color:color]; }
static void originalLayout(id view,SEL cmd) { (void)view;(void)cmd; }
static void originalRow(id view,SEL cmd) { (void)cmd;[[view selectedRowHighlightView] setHidden:NO]; }
int main(void) { @autoreleasepool {
 TUICandidateCell *cell=[TUICandidateCell new];cell.window=@1;cell.text=@"candidate";cell.textColor=@"purple";cell.selected=YES;
 NGOriginalCellBackgroundUpdate=originalPaint;NGOriginalHighlightCellLayout=originalLayout;
 NGCellBackgroundUpdate(cell,@selector(updateBackground:color:),@"native",@"gray");
 NSCAssert([cell.color isEqual:@"gray"],@"default-off changed background");
 NGHideCandidateHighlight=YES;NGCellBackgroundUpdate(cell,@selector(updateBackground:color:),@"native",@"gray");
 NSCAssert(!cell.backgroundImage && cell.color==UIColor.clearColor,@"cell background not removed");
 NSCAssert(cell.selected && [cell.text isEqual:@"candidate"] && [cell.textColor isEqual:@"purple"],@"selection or labels changed");
 TUICandidateBaseCell *other=[TUICandidateBaseCell new];
 NGCellBackgroundUpdate(other,@selector(updateBackground:color:),@"other",@"other-gray");
 NSCAssert([other.color isEqual:@"other-gray"],@"noncandidate base cell changed");
 TUICandidateGrid *grid=[TUICandidateGrid new];grid.window=@1;
 UIView *highlight=[UIView new];highlight.superview=grid;grid.selectedRowHighlightView=highlight;
 NGOriginalSelectedRowUpdate=originalRow;NGOriginalHighlightGridLayout=originalLayout;
 NGSelectedRowUpdate(grid,@selector(updateSelectedRowHighlightView));
 NSCAssert(highlight.hidden,@"row highlight not hidden");
 NGHighlightCellLayout(cell,@selector(layoutSubviews));
 NGHideCandidateHighlight=NO;NGRefreshCandidateHighlight();
 NSCAssert(!highlight.hidden && [cell.backgroundImage isEqual:@"current-native-image"],@"disable did not request current native repaint");
 UIView *unrelated=[UIView new];grid.selectedRowHighlightView=unrelated;NGHideCandidateHighlight=YES;
 NGApplySelectedRowHighlight(grid);NSCAssert(!unrelated.hidden,@"unrelated view hidden");
 NSLog(@"PASS: default off, candidate-only paint, labels/selection preserved, row hiding, reuse-safe native repaint and unrelated-view protection. Stand-in only.");
 }return 0;}
'''
with tempfile.TemporaryDirectory() as t:
 f=Path(t)/'highlight.m';exe=Path(t)/'highlight';f.write_text(prefix+s+suffix)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-function','-framework','Foundation',str(f),'-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
