#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

// دالة لتوليد IP ضمن النطاق المطلوب 172.59 مع ضمان صحة الأرقام (تجنب 0 و 255)
static NSString *generateValidAtlantaIP() {
    int thirdOctet = arc4random_uniform(254) + 1;  // من 1 إلى 254
    int fourthOctet = arc4random_uniform(254) + 1; // من 1 إلى 254
    return [NSString stringWithFormat:@"172.59.%d.%d", thirdOctet, fourthOctet];
}

// دالة مركزية لاستلام الطلب وحقن الـ Headers
static NSURLRequest *modifyRequest(NSURLRequest *request) {
    if (!request) return nil;
    
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    if (!mutableReq) return request;
    
    NSString *validIP = generateValidAtlantaIP();
    
    [mutableReq setValue:validIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:validIP forHTTPHeaderField:@"Client-IP"];
    [mutableReq setValue:validIP forHTTPHeaderField:@"X-Real-IP"];
    [mutableReq setValue:validIP forHTTPHeaderField:@"True-Client-IP"];
    [mutableReq setValue:validIP forHTTPHeaderField:@"X-Cluster-Client-IP"];
    
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
// 1. خداع التوقيت الزمني (Time Zone) لأتلانتا
// ==========================================
%hook NSTimeZone

+ (NSTimeZone *)localTimeZone {
    return [NSTimeZone timeZoneWithName:@"America/New_York"];
}

+ (NSTimeZone *)systemTimeZone {
    return [NSTimeZone timeZoneWithName:@"America/New_York"];
}

%end

// ==========================================
// 2. خداع إعدادات اللغة والبلد (Locale) لأمريكا
// ==========================================
%hook NSLocale

+ (id)currentLocale {
    return [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
}

+ (id)autoupdatingCurrentLocale {
    return [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
}

%end

// ==========================================
// 3. خداع نظام الموقع الجغرافي (GPS) لإحداثيات أتلانتا
// ==========================================
%hook CLLocationManager

- (CLLocation *)location {
    CLLocationCoordinate2D atlantaCoord = CLLocationCoordinate2DMake(33.7490, -84.3880);
    CLLocation *fakeLocation = [[CLLocation alloc] initWithCoordinate:atlantaCoord
                                                             altitude:300.0
                                                   horizontalAccuracy:5.0
                                                     verticalAccuracy:5.0
                                                            timestamp:[NSDate date]];
    return fakeLocation;
}

- (void)startUpdatingLocation {
    %orig;
    if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        CLLocationCoordinate2D atlantaCoord = CLLocationCoordinate2DMake(33.7490, -84.3880);
        CLLocation *fakeLocation = [[CLLocation alloc] initWithCoordinate:atlantaCoord
                                                                 altitude:300.0
                                                       horizontalAccuracy:5.0
                                                         verticalAccuracy:5.0
                                                                timestamp:[NSDate date]];
        [self.delegate locationManager:self didUpdateLocations:@[fakeLocation]];
    }
}

%end
