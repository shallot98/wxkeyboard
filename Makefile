TARGET := iphone:clang:16.5
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := rootless
INSTALL_TARGET_PROCESSES := com.tencent.wetype com.tencent.wetype.keyboard
PACKAGE_VERSION := 1.2.3

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := WeTypeVerticalSwipeToggle

WeTypeVerticalSwipeToggle_FILES := Tweak.xm
WeTypeVerticalSwipeToggle_CFLAGS += -fobjc-arc
WeTypeVerticalSwipeToggle_FRAMEWORKS := UIKit CoreFoundation CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "if command -v uicache >/dev/null 2>&1; then found=0; for app in /var/containers/Bundle/Application/*/WeType.app; do if [ -d \"$$app\" ]; then uicache -p \"$$app\" || true; found=1; fi; done; if [ $$found -eq 0 ] && [ -d /Applications/WeType.app ]; then uicache -p /Applications/WeType.app || true; fi; fi"
	install.exec "for name in WeType WeTypeKeyboard com.tencent.wetype.keyboard 'UIKitApplication\:com.tencent.wetype' 'UIKitApplication\:com.tencent.wetype.keyboard'; do killall -9 \"$$name\" 2>/dev/null || true; done"
	install.exec "if command -v ps >/dev/null 2>&1; then ps -e | awk '/[Ww]e[Tt]ype/ {print $$1}' | while read pid; do [ -n \"$$pid\" ] && kill -9 \"$$pid\" 2>/dev/null || true; done; fi"
