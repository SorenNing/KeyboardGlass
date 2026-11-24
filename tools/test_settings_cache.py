"""macOS Foundation test of the production getter with a framework stand-in.
This tests cache/reentry/reload behavior, not UIKit or Preferences rendering.
"""
from pathlib import Path
import subprocess,tempfile
P=Path(__file__).resolve().parents[1]
s=(P/'Preferences/NGKeyboardGlassPrefs.m').read_text()
getter=s[s.index('- (NSArray *)specifiers {'):s.index('- (id)readPreferenceValue:')]
prefix=r'''#import <Foundation/Foundation.h>
@interface PSListController : NSObject
@property(nonatomic,strong) NSArray *stored;
@property(nonatomic,strong) NSArray *rows;
@property(nonatomic,assign) NSInteger loads;
- (NSArray *)specifiers;
- (void)setSpecifiers:(NSArray *)rows;
- (NSInteger)numberOfGroups;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target bundle:(NSBundle *)bundle;
@end
@implementation PSListController
- (NSArray *)specifiers { return self.stored; }
- (void)setSpecifiers:(NSArray *)rows {
 self.stored=rows;
 NSCAssert([self specifiers]==rows,@"setter reentry lost cache");
}
- (NSInteger)numberOfGroups {
 NSInteger count=0;for(NSDictionary *row in self.stored) if([row[@"cell"] isEqual:@"PSGroupCell"]) count++;
 return count;
}
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target { self.loads++;return self.rows; }
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target bundle:(NSBundle *)bundle { self.loads++;return self.rows; }
@end
@interface NGCacheTest : PSListController
@property(nonatomic,strong) NSArray *ngSpecifiers;
@property(nonatomic,assign) BOOL ngLoading;
- (NSBundle *)bundle;
@end
@implementation NGCacheTest
- (NSBundle *)bundle { return NSBundle.mainBundle; }
'''
suffix=r'''
@end
int main(int argc,const char *argv[]) {
 @autoreleasepool {
  NSCAssert(argc==2,@"root argument required");
  NSDictionary *root=[NSDictionary dictionaryWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
  NGCacheTest *controller=[NGCacheTest new];controller.rows=root[@"items"];
  NSCAssert(controller.rows.count==43,@"input rows missing");
  NSCAssert(controller.specifiers.count==43,@"getter missing rows");
  NSCAssert(controller.stored.count==43,@"superclass storage not initialized");
  NSCAssert(controller.numberOfGroups==24,@"group state missing");
  NSCAssert(controller.specifiers.count==43 && controller.loads==1,@"cache did not stick");
  controller.ngSpecifiers=nil;
  NSCAssert(controller.specifiers.count==43 && controller.loads==2,@"reload did not repopulate");
  NSCAssert(!controller.ngLoading,@"reentry guard stuck");
  NSLog(@"PASS: production getter caches 43 rows, synchronizes 24 groups, handles setter reentry and reload. Framework stand-in; not UIKit validation.");
 }
 return 0;
}
'''
with tempfile.TemporaryDirectory() as t:
 f=Path(t)/'cache.m';exe=Path(t)/'cache';f.write_text(prefix+getter+suffix)
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations','-framework','Foundation',str(f),'-o',str(exe)],check=True)
 subprocess.run([str(exe),str(P/'Preferences/Root.plist')],check=True)
