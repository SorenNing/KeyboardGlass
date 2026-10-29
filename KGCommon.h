// KeyboardGlass 共享状态（KeyboardGlass.m 定义，KeyCaps.m 引用）
#import <Foundation/Foundation.h>

extern BOOL kgEnabled;
extern BOOL kgHideKeyCaps;
extern BOOL kgHideKeyShadows;
extern CGFloat kgBackgroundAlpha;

extern void KGLog(NSString *format, ...);
