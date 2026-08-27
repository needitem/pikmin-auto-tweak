export THEOS_PACKAGE_SCHEME = rootless
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = pikminauto
pikminauto_FILES = Tweak.xm
pikminauto_CFLAGS = -fobjc-arc -Wno-unused-function -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-but-set-variable
pikminauto_FRAMEWORKS = Foundation UIKit QuartzCore CoreLocation

include $(THEOS)/makefiles/tweak.mk
