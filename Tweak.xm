#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/ASIdentifierManager.h>
#import <AppTrackingTransparency/ATTrackingManager.h>

// ==========================================
// 1. حظر التتبع الشخصي (تصفير المعرفات)
// ==========================================

%hook ASIdentifierManager
// إرجاع Zero UUID كـ IDFA (يجبر شبكات الإعلانات على عرض إعلانات عامة غير متتبعة)
- (NSUUID *)advertisingIdentifier {
    return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"];
}
- (BOOL)isAdvertisingTrackingEnabled {
    return NO;
}
%end

%hook UIDevice
// إرجاع Zero UUID كـ IDFV لمنع التتبع بين تطبيقات نفس المطور
- (NSUUID *)identifierForVendor {
    return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"];
}
%end

%hook ATTrackingManager
// إرجاع حالة التتبع كـ Denied (مرفوض) دائماً
+ (ATTrackingManagerAuthorizationStatus)trackingAuthorizationStatus {
    return ATTrackingManagerAuthorizationStatusDenied;
}
// منع ظهور نافذة طلب التتبع وتثبيت حالة الرفض
+ (void)requestTrackingAuthorizationWithCompletionHandler:(void (^)(ATTrackingManagerAuthorizationStatus status))completion {
    if (completion) {
        completion(ATTrackingManagerAuthorizationStatusDenied);
    }
}
%end


// ==========================================
// 2. حظر مكتبات تحليلات سلوك المستخدم فقط
// ==========================================

// --- AppsFlyer ---
%hook AppsFlyerLib
- (void)start { }
- (void)logEvent:(id)name withValues:(id)values { }
- (void)logEvent:(id)name withValues:(id)values completionHandler:(id)handler { }
%end

// --- Adjust ---
%hook Adjust
+ (void)trackEvent:(id)event { }
+ (void)appDidLaunch:(id)config { }
%end

// --- Firebase Analytics & Crashlytics ---
%hook FIRAnalytics
+ (void)logEventWithName:(NSString *)name parameters:(NSDictionary *)parameters { }
%end

// --- Mixpanel ---
%hook Mixpanel
- (void)track:(NSString *)event { }
- (void)track:(NSString *)event properties:(NSDictionary *)properties { }
%end

// --- Facebook SDK Tracking ---
%hook FBSDKAppEvents
+ (void)logEvent:(id)eventName { }
+ (void)logEvent:(id)eventName valueToSum:(double)valueToSum parameters:(id)parameters { }
%end

%hook FBSDKSettings
// منع التتبع الإعلاني الموجه عبر فيسبوك مع إبقاء الإعلانات العادية
+ (void)setAdvertiserTrackingEnabled:(BOOL)enabled {
    %orig(NO);
}
%end
