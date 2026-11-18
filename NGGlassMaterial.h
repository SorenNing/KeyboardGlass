#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
NSBundle *NGGlassResources(void);
UIView *NGGlassMake(void);
BOOL NGGlassUpdate(UIView *material, UIVisualEffectView *host, void (^ready)(void));
void NGGlassPause(UIView *material);
#ifdef __cplusplus
}
#endif
