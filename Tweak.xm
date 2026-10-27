#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <AdSupport/AdSupport.h>
#import <dlfcn.h>
#import <objc/runtime.h>

// متغيرات الجلسة الثابتة
static NSString *sessionIP = nil;
static NSString *sessionIDFA = nil;
static NSString *const targetTimeZone = @"America/New_York";
static NSString *const targetLocale = @"en-US";
static NSString *const targetUserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 27_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Version/27.2";

static const double targetLatitude = 40.7128;
static const double targetLongitude = -74.0060;

// تطهير الكاش والكوكيز بأمان ت تام
static void purgePreviousSessionData() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        @try {
            NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
            for (NSHTTPCookie *cookie in [cookieStorage cookies]) {
                [cookieStorage deleteCookie:cookie];
            }
            [[NSURLCache sharedURLCache] removeAllCachedResponses];
            [[NSUserDefaults standardUserDefaults] synchronize];
        } @catch (NSException *exception) {
            // منع أي استثناء محتمل
        }
    });
}

static NSString *getSessionResidentialIP() {
    if (!sessionIP) {
        purgePreviousSessionData();
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

static NSURLRequest *modifyRequest(NSURLRequest *request) {
    if (!request) return nil;
    @try {
        NSMutableURLRequest *mutableReq = [request mutableCopy];
        if (!mutableReq) return request;
        
        NSString *selectedIP = getSessionResidentialIP();
        
        [mutableReq setValue:selectedIP forHTTPHeaderField:@"X-Forwarded-For"];
        [mutableReq setValue:selectedIP forHTTPHeaderField:@"Client-IP"];
        [mutableReq setValue:selectedIP forHTTPHeaderField:@"X-Real-IP"];
        [mutableReq setValue:selectedIP forHTTPHeaderField:@"True-Client-IP"];
        [mutableReq setValue:selectedIP forHTTPHeaderField:@"X-Cluster-Client-IP"];
        
        [mutableReq setValue:targetLocale forHTTPHeaderField:@"Accept-Language"];
        [mutableReq setValue:@"US" forHTTPHeaderField:@"X-App-Country"];
        [mutableReq setValue:targetUserAgent forHTTPHeaderField:@"User-Agent"];
        
        return [mutableReq copy];
    } @catch (NSException *e) {
        return request;
    }
}

// 1. تجاوز الشبكة (NSURLSession)
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(modifyRequest(request));
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    return %orig(modifyRequest(request), completionHandler);
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    return %orig(modifyRequest(request), bodyData);
}
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    return %orig(modifyRequest(request), bodyData, completionHandler);
}
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request {
    return %orig(modifyRequest(request));
}
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *, NSURLResponse *, NSError *))completionHandler {
    return %orig(modifyRequest(request), completionHandler);
}
%end

// 2. تخدير الوقت
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

// 3. تخدير اللغة
%hook NSLocale
+ (id)currentLocale {
    return [[NSLocale alloc] initWithLocaleIdentifier:targetLocale];
}
+ (id)preferredLanguages {
    return @[targetLocale, @"en"];
}
%end

// 4. محاكاة الموقع (GPS)
%hook CLLocationManager
- (CLLocation *)location {
    return [[CLLocation alloc] initWithLatitude:targetLatitude longitude:targetLongitude];
}
- (void)startUpdatingLocation {
    %orig;
    @try {
        if ([self delegate] && [[self delegate] respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            CLLocation *fakeLocation = [[CLLocation alloc] initWithLatitude:targetLatitude longitude:targetLongitude];
            [[self delegate] locationManager:self didUpdateLocations:@[fakeLocation]];
        }
    } @catch (NSException *e) {}
}
%end

// 5. محاكاة مزود الخدمة AT&T بأمان
%hook CTTelephonyNetworkInfo
- (id)subscriberCellularProvider {
    id provider = %orig;
    if (provider) {
        @try {
            // تعديل خصائص المزود القائم مباشرة إن وجد لتجنب الكراش
            [provider setValue:@"AT&T" forKey:@"carrierName"];
            [provider setValue:@"310" forKey:@"mobileCountryCode"];
            [provider setValue:@"410" forKey:@"mobileNetworkCode"];
            [provider setValue:@"us" forKey:@"isoCountryCode"];
        } @catch (NSException *e) {}
    }
    return provider;
}
%end

// 6. تزييف الـ IDFA بأمان تام دون فئات وهمية
%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    getSessionResidentialIP();
    return sessionIDFA ? [[NSUUID alloc] initWithUUIDString:sessionIDFA] : %orig;
}
- (BOOL)isAdvertisingTrackingEnabled {
    return YES;
}
%end

%ctor {
    @autoreleasepool {
        dlopen("/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony", RTLD_NOW);
        getSessionResidentialIP(); // تهيئة الجلسة مبكراً بأمان
    }
}
