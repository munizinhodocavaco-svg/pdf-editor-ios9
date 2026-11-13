# Theos Makefile - PDF LM para iOS 9.3 / ARMv7 (iPad 2)
TARGET = iphone:clang:9.3:9.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = PDFEditor

PDFEditor_FILES = PDFEditor/main.m \
	PDFEditor/AppDelegate.m \
	PDFEditor/DocumentListViewController.m \
	PDFEditor/NetworkViewController.m \
	PDFEditor/RootViewController.m \
	PDFEditor/PDFPageView.m \
	PDFEditor/Annotation.m \
	PDFEditor/AnnotationStore.m \
	PDFEditor/WebServer.m \
	PDFEditor/ColorPickerViewController.m \
	PDFEditor/Log.m
PDFEditor_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
PDFEditor_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
PDFEditor_LDFLAGS = -Wl,-segalign,4000 -lc
PDFEditor_CODESIGN_FLAGS = -Sentitlements.plist
PDFEditor_INSTALL_PATH = /Applications

include $(THEOS)/makefiles/application.mk
