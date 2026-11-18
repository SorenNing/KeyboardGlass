#pragma once
#import <Foundation/Foundation.h>
#import "NGGlassMaterial.h"

// Keep the upstream renderer unmodified. NGGlassResources resolves this bundle
// next to NingKeyboardGlass.dylib, including its RootHide-relocated location.
#define SWIFTPM_MODULE_BUNDLE NGGlassResources()
