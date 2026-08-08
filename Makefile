ARCHS = arm64
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = Preferences AppStore

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = iOS26Spoofer
iOS26Spoofer_FILES = Tweak.x
iOS26Spoofer_CFLAGS = -fobjc-arc
iOS26Spoofer_FRAMEWORKS = UIKit Foundation
iOS26Spoofer_PRIVATE_FRAMEWORKS = MobileGestalt

include $(THEOS_MAKE_PATH)/tweak.mk
