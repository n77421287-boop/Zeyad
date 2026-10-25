#import <Foundation/Foundation.h>

// Define the denylist of domains to intercept
static NSArray<NSString *> *const kDomainDenylist = @[
    @"report.appmetrica.yandex.net",
    @"api.get-sms-code.com",
    @"qbwkvc-skadsdkless.appsflyerssdk.com",
    @"qbwkvc-dynamic-report-api.appsflyerssdk.com",
    @"app-analytics-services.com",
    @"api2.amplitude.com",
    @"firebaselogging-pa.googleapis.com"
];

// Helper function to check if a given URL matches any domain in the denylist via partial matching
static BOOL sollteBlockieren(NSURL *url) {
    if (!url) return NO;
    
    // Extract host, fallback to absolute string if host is nil
    NSString *host = url.host ?: url.absoluteString;
    if (!host) return NO;
    
    for (NSString *denylistedDomain in kDomainDenylist) {
        // Partial match / containment logic as requested
        if ([host rangeOfString:denylistedDomain options:NSCaseInsensitiveSearch].location != NSNotFound) {
            NSLog(@"[TweakBlocker] 🚫 BLOCKED request to host: %@ (Matched rule: %@)", host, denylistedDomain);
            return YES;
        }
    }
    
    return NO;
}

%hook NSURLSession

// 1. Hook: dataTaskWithRequest:
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (sollteBlockieren(request.URL)) {
        NSURLSessionDataTask *dummyTask = %orig([NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]]);
        [dummyTask cancel];
        return dummyTask;
    }
    return %orig;
}

// 2. Hook: dataTaskWithRequest:completionHandler:
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    if (sollteBlockieren(request.URL)) {
        if (completionHandler) {
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                 code:NSURLErrorCancelled
                                             userInfo:@{NSLocalizedDescriptionKey: @"Request blocked by network policy tweak."}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(nil, nil, error);
            });
        }
        
        NSURLSessionDataTask *dummyTask = %orig([NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]], nil);
        [dummyTask cancel];
        return dummyTask;
    }
    
    return %orig(request, completionHandler);
}

%end
