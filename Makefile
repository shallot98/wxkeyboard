TARGET := iphone:clang:latest:16.5
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
INSTALL_TARGET_PROCESSES := com.tencent.wetype
PACKAGE_VERSION := 1.0.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := WeTypeVerticalSwipeToggle

WeTypeVerticalSwipeToggle_FILES := Tweak.xm
WeTypeVerticalSwipeToggle_CFLAGS += -fobjc-arc
WeTypeVerticalSwipeToggle_FRAMEWORKS := UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
