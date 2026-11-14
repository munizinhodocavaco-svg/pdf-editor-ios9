ARCHS = armv7
TARGET = iphone:clang:9.3:9.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = RemoteAccess

RemoteAccess_FILES = main.m \
	AppDelegate.m \
	RootViewController.m \
	VNCServer.m \
	MJPEGServer.m
RemoteAccess_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CoreFoundation
RemoteAccess_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
RemoteAccess_LDFLAGS = -Wl,-segalign,4000
RemoteAccess_CODESIGN_FLAGS = -Sentitlements.plist
RemoteAccess_INSTALL_PATH = /Applications
RemoteAccess_INFO_PLIST = Info.plist

include $(THEOS_MAKE_PATH)/application.mk