#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

// دالة لتوليد IP ضمن النطاق المطلوب 101.167 الخاص بأستراليا مع ضمان صحة الأرقام
static NSString *generateAustraliaIP() {
    int thirdOctet = arc4random_uniform(254) + 1;  // من 1 إلى 254
    int fourthOctet = arc4random_uniform(254) + 1; // من 1 إلى 254
    return [NSString stringWithFormat:@"101.167.%d.%d", thirdOctet, fourthOctet];
}

// دالة مركزية لاستلام الطلب وحقن الـ Headers
static NSURLRequest *modifyRequest(NSURLRequest *request) {
    if (!request) return nil;
    
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    if (!mutableReq) return request;
    
    NSString *auIP = generateAustraliaIP();
    
    [mutableReq setValue:auIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:auIP forHTTPHeaderField:@"Client-IP"];
    [mutableReq setValue:auIP forHTTPHeaderField:@"X-Real-IP"];
    [mutableReq setValue:auIP forHTTPHeaderField:@"True-Client-IP"];
    [mutableReq setValue:auIP forHTTPHeaderField:@"X-Cluster-Client-IP"];
    
    return [mutableReq copy];
}

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

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request {
    return %orig(modifyRequest(request));
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    return %orig(modifyRequest(request), completionHandler);
}

%end

// ==========================================
// 1. خداع التوقيت الزمني (Time Zone) ليصبح توقيت أستراليا (سيدني)
// ==========================================
%hook NSTimeZone

+ (NSTimeZone *)localTimeZone {
    return [NSTimeZone timeZoneWithName:@"Australia/Sydney"];
}

+ (NSTimeZone *)systemTimeZone {
    return [NSTimeZone timeZoneWithName:@"Australia/Sydney"];
}

%end

// ==========================================
// 2. خداع إعدادات اللغة والبلد (Locale) لتصبح أسترالية
// ==========================================
%hook NSLocale

+ (id)currentLocale {
    return [[NSLocale alloc] initWithLocaleIdentifier:@"en_AU"];
}

+ (id)autoupdatingCurrentLocale {
    return [[NSLocale alloc] initWithLocaleIdentifier:@"en_AU"];
}

%end

// ==========================================
// 3. خداع نظام الموقع الجغرافي (GPS) لإحداثيات سيدني، أستراليا
// الإحداثيات: Latitude: -33.8688, Longitude: 151.2093
// ==========================================
%hook CLLocationManager

- (CLLocation *)location {
    CLLocationCoordinate2D sydneyCoord = CLLocationCoordinate2DMake(-33.8688, 151.2093);
    CLLocation *fakeLocation = [[CLLocation alloc] initWithCoordinate:sydneyCoord
                                                             altitude:300.0
                                                   horizontalAccuracy:5.0
                                                     verticalAccuracy:5.0
                                                            timestamp:[NSDate date]];
    return fakeLocation;
}

- (void)startUpdatingLocation {
    %orig;
    if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        CLLocationCoordinate2D sydneyCoord = CLLocationCoordinate2DMake(-33.8688, 151.2093);
        CLLocation *fakeLocation = [[CLLocation alloc] initWithCoordinate:sydneyCoord
                                                                 altitude:300.0
                                                       horizontalAccuracy:5.0
                                                         verticalAccuracy:5.0
                                                                timestamp:[NSDate date]];
        [self.delegate locationManager:self didUpdateLocations:@[fakeLocation]];
    }
}

%end
