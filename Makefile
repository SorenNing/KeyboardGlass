TARGET = iphone:clang:16.5:15.0
ARCHS = arm64e
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KeyboardGlass
KeyboardGlass_FILES = KeyboardGlass.m KeyCaps.m
KeyboardGlass_CFLAGS = -fobjc-arc -Wall
KeyboardGlass_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	install -d "$(THEOS_STAGING_DIR)/DEBIAN"
	install -m 0755 pkg-deb/postinst "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
	install -d "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"
	install -m 644 prefs/KeyboardGlass.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/KeyboardGlass.plist"
	ldid -S -Cadhoc "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/KeyboardGlassPrefs.bundle/KeyboardGlassPrefs" && echo "signed prefs bundle"
