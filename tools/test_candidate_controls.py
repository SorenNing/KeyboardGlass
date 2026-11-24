"""macOS Foundation stand-in: exercises production save/restore; not UIKit UI."""
from pathlib import Path
import subprocess,tempfile
P=Path(__file__).resolve().parents[1]
s=(P/'CandidateControls.h').read_text()
state=s[s.index('@interface NGControlVisibilityState'):s.index('static NSHashTable<UIView *> *NGCandidateContainers;')]
logic=s[s.index('static void NGRestoreCandidateControls'):s.index('static BOOL NGIsCandidateLine')]
prefix='''#import <Foundation/Foundation.h>
@interface UIView : NSObject
@property(nonatomic) BOOL hidden;
@property(nonatomic) BOOL userInteractionEnabled;
@property(nonatomic,weak) UIView *superview;
- (BOOL)isDescendantOfView:(UIView *)scope;
@end
@implementation UIView
- (BOOL)isDescendantOfView:(UIView *)scope {
 for(UIView *v=self;v;v=v.superview) if(v==scope) return YES;
 return NO;
}
@end
'''
suffix='''
int main(void) { @autoreleasepool {
 UIView *scope=[UIView new],*glyph=[UIView new],*line=[UIView new],*button=[UIView new],*other=[UIView new];
 glyph.superview=scope;line.superview=scope;button.superview=scope;
 glyph.hidden=NO;line.hidden=YES;button.userInteractionEnabled=YES;
 NGSaveControl(glyph,YES);NGSaveControl(glyph,YES);NGSaveControl(line,YES);NGSaveControl(button,NO);
 NSCAssert(glyph.hidden && line.hidden && !button.userInteractionEnabled,@"enable failed");
 NGRestoreCandidateControls(other);
 NSCAssert(glyph.hidden && !button.userInteractionEnabled,@"unrelated scope changed");
 NGRestoreCandidateControls(scope);
 NSCAssert(!glyph.hidden && line.hidden && button.userInteractionEnabled,@"native state not restored");
 NGSaveControl(glyph,YES);NGRestoreCandidateControls(nil);
 NSCAssert(!glyph.hidden && NGControlStates.count==0,@"repeat toggle lost state");
 NSLog(@"PASS: production hide/restore, repeated enable, native-hidden line, scoped restore, disabled hit target and toggle-off.");
 } return 0; }
'''
with tempfile.TemporaryDirectory() as t:
 f=Path(t)/'candidate.m';exe=Path(t)/'candidate';f.write_text(prefix+state+logic+suffix)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-framework','Foundation',str(f),'-o',str(exe)],check=True)
 subprocess.run([str(exe)],check=True)
