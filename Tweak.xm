#import <Foundation/Foundation.h>

// Define the denylist of domains to intercept
static NSArray<NSString *> *const kDomainDenylist = @Ω[
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
        // Return a dummy task or let standard flow handle it, but to prevent crashes on non-nil expectations,
        // we can return a task from a dummy session or a cancelled task. 
        // Alternatively, returning nil can work if the caller handles it, but let's return a cancelled task to be safe.
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
            // Construct a cancellation error so the calling app handles the failure gracefully
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                                 code:NSURLErrorCancelled
                                             userInfo:@{NSLocalizedDescriptionKey: @"Request blocked by network policy tweak."}];
            // Invoke the completion handler asynchronously on the calling thread/queue
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(nil, nil, error);
            });
        }
        
        // Return a dummy cancelled task
        NSURLSessionDataTask *dummyTask = %orig([NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]], nil);
        [dummyTask cancel];
        return dummyTask;
    }
    
    return %orig(request, completionHandler);
}

%end
