#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <AdSupport/AdSupport.h>

// متغيرات الجلسة الثابتة
static NSString *sessionIP = nil;
static NSString *sessionIDFA = nil; // المعرّف الإعلاني الوهمي والثابت للجلسة
static NSString *const targetTimeZone = @"America/New_York";
static NSString *const targetLocale = @"en-US";
static NSString *const targetUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 27_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Version/27.2";

// إحداثيات نيويورك الافتراضية
static const double targetLatitude = 40.7128;
static const double targetLongitude = -74.0060;

// دالة لتطهير وعزل الكاش والكوكيز لبدء الجلسة بنظافة تامة
static void purgePreviousSessionData() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 1. مسح جميع الكوكيز المرتبطة بالجلسات السابقة
        NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
            [cookieStorage deleteCookie:cookie];
        }
        
        // 2. تفريغ كاش الـ NSURLCache بالكامل
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        
        // 3. مسح الـ NSUserDefaults المؤقتة
        [[NSUserDefaults standardUserDefaults] synchronize];
    });
}

// دالة لاختيار آي بي سكني ثابت وتوليد IDFA وهمي للجلسة
static NSString *getSessionResidentialIP() {
    if (!sessionIP) {
        // تنفيذ التطهير الشامل للبيانات المؤقتة عند بدء جلسة جديدة
        purgePreviousSessionData();
        
        // توليد معرّف إعلاني عشوائي فريد ونظيف خاص بهذه الجلسة (IDFA Spoofing)
        sessionIDFA = [[NSUUID UUID] UUIDString];
        
        NSArray *verifiedIPs = @[
            @"12.144.80.12",
            @"12.144.80.25",
            @"12.144.81.104",
            @"12.155.20.45",
            @"12.155.20.88",
            @"12.210.15.30",
            @"12.210.15.99",
            @"12.88.105.30",
            @"12.230.45.10",
            @"12.230.45.55"
        ];
        
        uint32_t randomIndex = arc4random_uniform((uint32_t)[verifiedIPs count]);
        sessionIP = verifiedIPs[randomIndex];
    }
    return sessionIP;
}

// دالة تعديل الطلبات وحقن الترويسات (IP + Geo + User-Agent)
static NSURLRequest *modifyRequest(NSURLRequest *request) {
    if (!request) return nil;
    
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    if (!mutableReq) return request;
    
    // 1. استدعاء الجلسة لضمان تهيئة الـ IP والـ IDFA الخاص بها
    NSString *selectedIP = getSessionResidentialIP();
    
    // 2. حقن الـ IP الثابت للجلسة
    [mutableReq setValue:selectedIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:selectedIP forHTTPHeaderField:@"Client-IP"];
    [mutableReq setValue:selectedIP forHTTPHeaderField:@"X-Real-IP"];
    [mutableReq setValue:selectedIP forHTTPHeaderField:@"True-Client-IP"];
    [mutableReq setValue:selectedIP forHTTPHeaderField:@"X-Cluster-Client-IP"];
    
    // 3. حقن الترويسات الجغرافية واللغوية
    [mutableReq setValue:targetLocale forHTTPHeaderField:@"Accept-Language"];
    [mutableReq setValue:@"US" forHTTPHeaderField:@"X-App-Country"];
    
    // 4. حقن الـ User-Agent المخصص
    [mutableReq setValue:targetUserAgent forHTTPHeaderField:@"User-Agent"];
    
    return [mutableReq copy];
}

// --- الجزء الخاص بتخطي SSL Pinning ---
%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(modifyRequest(request));
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    return %orig(modifyRequest(request), completionHandler);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    return %orig(modifyRequest(request), bodyData);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    return %orig(modifyRequest(request), bodyData, completionHandler);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL {
    return %orig(modifyRequest(request), fileURL);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    return %orig(modifyRequest(request), fileURL, completionHandler);
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request {
    return %orig(modifyRequest(request));
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    return %orig(modifyRequest(request), completionHandler);
}

%end

// تجاوز فحص الشهادات الأمنية (SSL Pinning Bypass)
%hook NSURLConnection

+ (BOOL)canUseNewConnections {
    return YES;
}

%end

// تخدير توقيت النظام
%hook NSTimeZone
+ (NSTimeZone *)localTimeZone {
    NSTimeZone *tz = [NSTimeZone timeZoneWithName:targetTimeZone];
    return tz ? tz : %orig;
}
+ (NSTimeZone *)systemTimeZone {
    NSTimeZone *tz = [NSTimeZone timeZoneWithName:targetTimeZone];
    return tz ? tz : %orig;
}
%end

// تخدير لغة الجهاز
%hook NSLocale
+ (id)currentLocale {
    return [[NSLocale alloc] initWithLocaleIdentifier:targetLocale];
}
+ (id)preferredLanguages {
    return @[targetLocale, @"en"];
}
%end

// محاكاة مزود الخدمة الأمريكي AT&T (CoreTelephony Hook)
%ctor {
    dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
}

%subclass CTCarrierDummy : NSObject
- (NSString *)carrierName { return @"AT&T"; }
- (NSString *)mobileCountryCode { return @"310"; }
- (NSString *)mobileNetworkCode { return @"410"; }
- (NSString *)isoCountryCode { return @"us"; }
- (BOOL)allowsVOIP { return YES; }
%end

%hook CTTelephonyNetworkInfo
- (id)subscriberCellularProvider {
    return [[%c(CTCarrierDummy) alloc] init];
}
%end

// تزييف الإحداثيات الجغرافية GPS / CoreLocation
%hook CLLocationManager

- (CLLocation *)location {
    return [[CLLocation alloc] initWithLatitude:targetLatitude longitude:targetLongitude];
}

- (void)startUpdatingLocation {
    %orig;
    if ([self delegate] && [[self delegate] respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        CLLocation *fakeLocation = [[CLLocation alloc] initWithLatitude:targetLatitude longitude:targetLongitude];
        [[self delegate] locationManager:self didUpdateLocations:@[fakeLocation]];
    }
}

%end

// --- تزييف المعرّف الإعلاني (IDFA Spoofing) عبر ASIdentifierManager ---
%subclass ASIdentifierManagerDummy : NSObject
- (NSUUID *)advertisingIdentifier {
    getSessionResidentialIP();
    return [[NSUUID alloc] initWithUUIDString:sessionIDFA];
}
- (BOOL)isAdvertisingTrackingEnabled {
    return YES;
}
%end

%hook ASIdentifierManager
+ (id)sharedManager {
    return [[%c(ASIdentifierManagerDummy) alloc] init];
}
- (id)advertisingIdentifier {
    getSessionResidentialIP();
    return [[NSUUID alloc] initWithUUIDString:sessionIDFA];
}
- (BOOL)isAdvertisingTrackingEnabled {
    return YES;
}
%end
