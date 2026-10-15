ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = NetworkSniffer

NetworkSniffer_FILES = NetworkSniffer.m
NetworkSniffer_CFLAGS = -fobjc-arc \
    -Wno-deprecated-declarations \
    -Wno-unused-function \
    -Wno-unused-variable \
    -Wno-objc-method-access \
    -Wno-nullability-completeness \
    -Wno-strict-prototypes

NetworkSniffer_LDFLAGS = -lz \
    -framework Security \
    -framework CFNetwork \
    -framework WebKit \
    -framework UIKit \
    -framework Foundation

NetworkSniffer_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/library.mk
