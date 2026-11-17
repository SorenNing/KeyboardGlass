#import <UIKit/UIKit.h>
// Only UIKBBackdropView / UIKBBackgroundView are registered as backgrounds.
void NGSurfaceRefresh(UIView *host);
void NGSurfaceHostingRefresh(id item);
void NGSurfaceWindowRefresh(UIView *view);
void NGSurfaceCandidateRefresh(UIView *view);
BOOL NGSurfaceMaterialAvailable(void);
BOOL NGSurfaceHasCoverage(UIView *view);
