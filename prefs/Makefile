#include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = KeyboardGlassPrefs
KeyboardGlassPrefs_FILES = RootListController.m KGThemePickerCell.m
KeyboardGlassPrefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I.
KeyboardGlassPrefs_FRAMEWORKS = UIKit Foundation
KeyboardGlassPrefs_PRIVATE_FRAMEWORKS = Preferences
KeyboardGlassPrefs_INSTALL_PATH = /Library/PreferenceBundles
KeyboardGlassPrefs_RESOURCE_FILES = Resources/Root.plist Resources/icon.png Resources/icon@2x.png Resources/icon@3x.png

include $(THEOS_MAKE_PATH)/bundle.mk
