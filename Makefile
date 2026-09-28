export THEOS_PACKAGE_SCHEME = rootless
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = pikminauto
pikminauto_FILES = $(wildcard Sources/*/*.mm)
pikminauto_CFLAGS = -fobjc-arc -std=gnu++17 -Wall -Wno-deprecated-declarations \
	-ISources/Support -ISources/IL2CPP -ISources/Game -ISources/Model \
	-ISources/Rpc -ISources/Passes -ISources/App
pikminauto_FRAMEWORKS = Foundation UIKit QuartzCore CoreLocation

include $(THEOS)/makefiles/tweak.mk
