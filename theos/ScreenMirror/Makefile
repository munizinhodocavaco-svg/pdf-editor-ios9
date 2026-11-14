ARCHS = armv7
TARGET = iphone:clang:9.3:9.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = ScreenMirror
ScreenMirror_FILES = main.m ScreenMirror.m
ScreenMirror_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
ScreenMirror_LDFLAGS = -framework Foundation -framework UIKit -framework CoreGraphics -framework IOKit
ScreenMirror_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/tool.mk

after-install::
	install.exec "killall -9 ScreenMirror 2>/dev/null; true"