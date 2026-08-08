ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = Preferences AppStore SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iOS26Spoofer
iOS26Spoofer_FILES = Tweak.x
iOS26Spoofer_CFLAGS = -fobjc-arc
iOS26Spoofer_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
