#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
NSBundle *NGGlassResources(void);
BOOL NGGlassAvailable(void);
UIView *NGGlassMake(void);
void NGGlassUpdate(UIView *material, UIVisualEffectView *host, BOOL force);
void NGGlassPause(UIView *material);
#ifdef __cplusplus
}
#endif
