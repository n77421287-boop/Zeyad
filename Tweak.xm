// Tweak.xm
// CHPUBG – Ultimate Privacy & Anti-Ban (Whitelist + Ad-Spoof + 0.50s Clean)
// iOS arm64 / arm64e – Theos / Logos

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <AdSupport/AdSupport.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <sys/stat.h>
#import <stdio.h>
#import <unistd.h>
#import <stdlib.h>
#import <string.h>
#import <dispatch/dispatch.h>

// ⬇️ سرعة المسح: كل نصف ثانية ⬇️
#define CLEAN_INTERVAL 0.50 

// المفتاح الوحيد المسموح له بالمرور في الـ Keychain (مفتاح الحساب)
static NSString * const kAccountKey = @"com.tempnum.virtualnumber.deviceUUID";

// ------------------------------------------------------------
// 1. مساعدات عامة وحماية العمليات
// ------------------------------------------------------------
static NSString *randomUUIDString(void) {
    return [[NSUUID UUID] UUIDString];
}

static BOOL isUserApplicationProcess(void) {
    static BOOL result;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] bundlePath];
        NSString *exe  = [NSProcessInfo processInfo].processName;
        NSArray<NSString *> *systemProcs = @[@"SpringBoard", @"backboardd", @"launchd", @"securityd", @"sharingd", @"lsd", @"cfprefsd", @"distnoted", @"keybagd", @"amfid"];
        if ([systemProcs containsObject:exe]) { result = NO; return; }
        result = [path containsString:@"/Application/"] || [path containsString:@"/Bundle/Application/"];
    });
    return result;
}

// ------------------------------------------------------------
// 2. تنظيف الملفات المؤقتة (كل 0.5 ثانية)
// ------------------------------------------------------------
static void cleanPathsNow(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *home = NSHomeDirectory();
    NSArray *paths = @[
        [home stringByAppendingPathComponent:@"Library/Caches"],
        [home stringByAppendingPathComponent:@"tmp"],
        [home stringByAppendingPathComponent:@"Library/Logs"]
    ];
    for (NSString *path in paths) {
        NSArray *contents = [fm contentsOfDirectoryAtPath:path error:nil];
        for (NSString *item in contents) {
            [fm removeItemAtPath:[path stringByAppendingPathComponent:item] error:nil];
        }
    }
}

static void startCleanerTimer(void) {
    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    if (!timer) return;
    uint64_t interval = (uint64_t)(CLEAN_INTERVAL * NSEC_PER_SEC);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 0), interval, 0);
    dispatch_source_set_event_handler(timer, ^{ @autoreleasepool { cleanPathsNow(); } });
    dispatch_resume(timer);
}

// ------------------------------------------------------------
// 3. اعتراض NSUserDefaults (تزوير المعرفات والحفاظ على الحساب)
// ------------------------------------------------------------
%hook NSUserDefaults

- (id)objectForKey:(NSString *)defaultName {
    // تزوير معرف التطبيق لتبدو كجهاز جديد
    if ([defaultName isEqualToString:@"GT_APP_ID"]) {
        static NSString *fakeAppId;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{ fakeAppId = randomUUIDString(); });
        return fakeAppId; 
    }
    // نسمح بقراءة auth_token بشكل طبيعي حتى لا يطردك من الحساب
    return %orig;
}

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    // منع حفظ إعدادات وبصمات Firebase
    if ([defaultName containsString:@"firebase-sessions"] || 
        [defaultName isEqualToString:@"GT_LAST_CLOSED_TIME"]) {
        return; 
    }
    %orig;
}

%end

// ------------------------------------------------------------
// 4. نظام القائمة البيضاء في Keychain (حظر شامل إلا مفتاح الحساب)
// ------------------------------------------------------------
static BOOL isAccountKey(NSDictionary *dict) {
    if (!dict) return NO;
    NSString *account = dict[(__bridge NSString *)kSecAttrAccount];
    return [account isEqualToString:kAccountKey];
}

// 1. اعتراض البحث (Copy)
OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
OSStatus my_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    NSDictionary *dict = (__bridge NSDictionary *)query;
    if (isAccountKey(dict)) {
        return orig_SecItemCopyMatching(query, result); 
    }
    if (result) *result = NULL;
    return errSecItemNotFound;
}

// 2. اعتراض الإضافة (Add)
OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *);
OSStatus my_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    NSDictionary *dict = (__bridge NSDictionary *)attributes;
    if (isAccountKey(dict)) {
        return orig_SecItemAdd(attributes, result); 
    }
    if (result) *result = NULL;
    return errSecSuccess; 
}

// 3. اعتراض التحديث (Update)
OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
OSStatus my_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSDictionary *dict = (__bridge NSDictionary *)query;
    if (isAccountKey(dict)) {
        return orig_SecItemUpdate(query, attributesToUpdate);
    }
    return errSecSuccess; 
}

// 4. اعتراض الحذف (Delete)
OSStatus (*orig_SecItemDelete)(CFDictionaryRef);
OSStatus my_SecItemDelete(CFDictionaryRef query) {
    NSDictionary *dict = (__bridge NSDictionary *)query;
    if (isAccountKey(dict)) {
        return orig_SecItemDelete(query);
    }
    return errSecSuccess; 
}

// ------------------------------------------------------------
// 5. تزوير بصمة الجهاز ومعرف الإعلانات (UDID & IDFA)
// ------------------------------------------------------------
%hook UIDevice
- (NSUUID *)identifierForVendor {
    static NSUUID *fake;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ fake = [[NSUUID alloc] initWithUUIDString:randomUUIDString()]; });
    return fake;
}
- (NSUUID *)advertisingIdentifier {
    return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"];
}
%end

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    return [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"];
}
- (BOOL)isAdvertisingTrackingEnabled {
    return YES; // نوهم التطبيق أن التتبع مفعل
}
%end

// ------------------------------------------------------------
// 6. التشغيل
// ------------------------------------------------------------
%ctor {
    @autoreleasepool {
        if (!isUserApplicationProcess()) return;

        cleanPathsNow();
        startCleanerTimer();

        // تفعيل اعتراض الـ Keychain
        MSHookFunction((void *)SecItemCopyMatching, (void *)my_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching);
        MSHookFunction((void *)SecItemAdd, (void *)my_SecItemAdd, (void **)&orig_SecItemAdd);
        MSHookFunction((void *)SecItemUpdate, (void *)my_SecItemUpdate, (void **)&orig_SecItemUpdate);
        MSHookFunction((void *)SecItemDelete, (void *)my_SecItemDelete, (void **)&orig_SecItemDelete);
    }
}
