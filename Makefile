TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e
DEBUG = 0
FINALPACKAGE = 1
FOR_RELEASE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GhostIdentity
GhostIdentity_FILES = Tweak.xm
GhostIdentity_CFLAGS = -fobjc-arc -O2 -fvisibility=hidden
GhostIdentity_FRAMEWORKS = Foundation UIKit AdSupport CFNetwork Security SystemConfiguration
GhostIdentity_LDFLAGS = -lsubstrate

include $(THEOS_MAKE_PATH)/tweak.mk
