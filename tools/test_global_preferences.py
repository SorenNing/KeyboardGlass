"""Run on macOS: separate producer/consumer processes; no device/UI claim."""
from pathlib import Path
import subprocess,tempfile,json
P=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as t:
 d=Path(t);snapshot=d/'global.plist'
 header=(P/'GlassPreferences.h').read_text().replace('com.ning.keyboardglass"','com.ning.keyboardglass.test"').replace('/var/mobile/Library/Accessibility/KeyboardGlass-preferences.plist',str(snapshot))
 (d/'GlassPreferences.h').write_text(header)
 source=r'''#import "GlassPreferences.h"
int main(int argc,const char *argv[]) {
 @autoreleasepool {
  if(argc!=2) return 2;
  NSString *mode=[NSString stringWithUTF8String:argv[1]];
  if([mode isEqual:@"produce"]) {
   CFPreferencesSetAppValue(CFSTR("Skin"),CFSTR("clear"),(__bridge CFStringRef)NGDomain);
   CFPreferencesSetAppValue(CFSTR("HideCandidateControls"),kCFBooleanTrue,(__bridge CFStringRef)NGDomain);
   CFPreferencesSetAppValue(CFSTR("MaterialBlurEnabled"),kCFBooleanTrue,(__bridge CFStringRef)NGDomain);
   CFPreferencesSetAppValue(CFSTR("MaterialBlurStrength"),(__bridge CFNumberRef)@0.65,(__bridge CFStringRef)NGDomain);
   CFPreferencesSetAppValue(CFSTR("SystemAlpha"),(__bridge CFNumberRef)@0.42,(__bridge CFStringRef)NGDomain);
   NSDictionary *overrides=@{@"clear":@{@"CornerRadius":@31,@"CornerShape":@3.2}};
   CFPreferencesSetAppValue(CFSTR("Overrides"),(__bridge CFDictionaryRef)overrides,(__bridge CFStringRef)NGDomain);
   NSError *error=nil;NSCAssert(NGPublishGlobalSnapshot(&error),@"publish failed %@",error);
   CFPreferencesSetAppValue(CFSTR("Skin"),CFSTR("liquid"),(__bridge CFStringRef)NGDomain);
   NGMigrateSharedOverrides();
   id migrated=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("Overrides"),(__bridge CFStringRef)NGDomain));
   NSCAssert([migrated[@"*"][@"CornerRadius"] doubleValue]==31,@"skin switch lost shared radius");
   CFPreferencesSetAppValue(CFSTR("Skin"),CFSTR("clear"),(__bridge CFStringRef)NGDomain);
   NSCAssert(NGSharedOverrides(@{@"clear":@{@"CornerRadius":@19}},@"clear").count==1,@"legacy read failed");
   NSCAssert(NGSharedOverrides(@{@"*":@{},@"clear":@{@"CornerRadius":@19}},@"clear").count==0,@"cleared override resurrected");
  } else if([mode isEqual:@"consume"]) {
   // A private domain may contain conflicting defaults. The snapshot must win.
   CFPreferencesSetAppValue(CFSTR("Skin"),CFSTR("default"),(__bridge CFStringRef)NGDomain);
   NSCAssert(NGLoadGlobalSnapshot(),@"snapshot unavailable");
   NSCAssert([NGSelectedSkin() isEqual:@"clear"],@"skin not shared");
   NSCAssert([NGCopyPreference(@"HideCandidateControls") boolValue],@"candidate toggle not shared");
   NSCAssert([NGCopyPreference(@"MaterialBlurEnabled") boolValue],@"blur toggle not shared");
   NSCAssert(fabs([NGCopyPreference(@"MaterialBlurStrength") doubleValue]-.65)<1e-6,@"blur strength not shared");
   NSCAssert((NGValidateSnapshot(@{@"Schema":@1,@"Configuration":@{@"Skin":@"clear",@"SystemAlpha":@1,@"Overrides":@{},@"MaterialBlurStrength":@2}})==nil),@"invalid blur strength accepted");
   NSCAssert(NGValidateSnapshot(@{@"Schema":@1,@"Configuration":@{@"Skin":@"clear",@"SystemAlpha":@1,@"Overrides":@{}}})!=nil,@"legacy snapshot rejected");
   NSCAssert(fabs([NGCopyPreference(@"SystemAlpha") doubleValue]-.42)<1e-6,@"alpha not shared");
   NSCAssert([NGEffectiveValues(NGSelectedSkin())[@"CornerRadius"] doubleValue]==31,@"radius not shared");
   NSCAssert([NGEffectiveValues(@"liquid")[@"CornerRadius"] doubleValue]==31,@"new skin reset adjusted radius");
   NSCAssert(fabs([NGEffectiveValues(@"liquid")[@"HighlightBrightness"] doubleValue]-.75)<1e-6,@"untouched preset field lost");
   NSCAssert([@"corrupt" writeToFile:NGSnapshotPath atomically:YES encoding:NSUTF8StringEncoding error:nil],@"corrupt fixture failed");
   NSCAssert(!NGLoadGlobalSnapshot(),@"bad plist accepted");
   NSCAssert([NGSelectedSkin() isEqual:@"clear"],@"lost last good config");
   NSCAssert(!NGValidateSnapshot(@{@"Schema":@1,@"Configuration":@{@"Skin":@"clear",@"SystemAlpha":@2,@"Overrides":@{}}}),@"range validation failed");
   NSCAssert(NGNumber(@(NAN),1,0,1)==1,@"NaN accepted");
   NSCAssert([NSFileManager.defaultManager removeItemAtPath:NGSnapshotPath error:nil],@"missing-file fixture failed");
   NSCAssert(!NGLoadGlobalSnapshot(),@"missing file accepted");
   NSCAssert(NGConfigReadError.length>0,@"read failure was not diagnosed");
   NSCAssert([NGSelectedSkin() isEqual:@"clear"],@"read failure lost last good config");
  } else return 3;
 }
 return 0;
}
'''
 f=d/'check.m';f.write_text(source);exe=d/'check'
 subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations','-framework','Foundation',str(f),'-o',str(exe)],check=True)
 subprocess.run([str(exe),'produce'],check=True)
 subprocess.run([str(exe),'consume'],check=True)
print('PASS: separate-process global skin/alpha/radius; private defaults ignored; corrupt update retained; range and NaN validation. Device sandbox access still requires verification.')
