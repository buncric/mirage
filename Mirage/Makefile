INSTALL_TARGET_PROCESSES = SpringBoard
export TARGET = iphone:clang:16.5:12.4
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = MiragePrefs

MiragePrefs_FILES = $(wildcard AVS*.*m)
MiragePrefs_FRAMEWORKS = UIKit
MiragePrefs_PRIVATE_FRAMEWORKS = Preferences
MiragePrefs_INSTALL_PATH = /Library/PreferenceBundles
MiragePrefs_EXTRA_FRAMEWORKS = AltList
MiragePrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
