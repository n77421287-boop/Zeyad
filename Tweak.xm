#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <Security/Security.h>
#import <objc/runtime.h>

extern void executeFullEnvironmentRefresh(void);

// متغيرات عامة لحفظ الـ IDFA و الـ IDFV المتجددة
static NSString *currentRandomIDFA = nil;
static NSString *currentRandomIDFV = nil;

// --- الثوابت وإعدادات الحسابات الثلاثة ---
static NSString * const kKeychainAccount = @"com.tempnum.virtualnumber.deviceUUID";
static NSString * const kKeychainGroup   = @"3J96GNXKKU.*";
static NSString * const kAccount1_UUID   = @"1A82BF91-3EA4-4CA5-AD39-593553C1E15C"; // الحساب الأول
static NSString * const kAccount2_UUID   = @"2BEE80E2-E20A-432B-879D-A98E2B8BC10A"; // الحساب الثاني
static NSString * const kAccount3_UUID   = @"3F4D0093-0107-44B6-9D43-63FBCE2A5956"; // الحساب الثالث

static BOOL isSwitchAlertShown = NO;

// --- مسار حالة التبديل ---
static NSString *getStatePlistPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *libraryDirectory = [paths firstObject];
    return [libraryDirectory stringByAppendingPathComponent:@"AccountSwitchState.plist"];
}

// --- إدارة الـ Keychain المدمجة للحسابات ---
static NSString *getAppCurrentUUIDFromKeychain(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecAttrAccessGroup: kKeychainGroup,
        (__bridge id)kSecReturnData: (__bridge id)kCFBooleanTrue,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne
    };
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) == noErr) {
        NSData *data = (__bridge_transfer NSData *)result;
        return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    }
    return nil;
}

static void clearEntireKeychainAccounts(void) {
    NSArray *secClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];
    
    for (id secClass in secClasses) {
        NSDictionary *spec = @{
            (__bridge id)kSecClass: secClass,
            (__bridge id)kSecAttrAccessGroup: kKeychainGroup
        };
        SecItemDelete((__bridge CFDictionaryRef)spec);
    }
}

static void saveUUIDToKeychain(NSString *uuidString) {
    NSData *data = [uuidString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *addQuery = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: kKeychainAccount,
        (__bridge id)kSecAttrAccessGroup: kKeychainGroup,
        (__bridge id)kSecValueData: data
    };
    SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
}

// --- منطق التبديل التسلسلي (1 -> 2 -> 3 -> 1) ---
static NSString *getNextAccountUUID(void) {
    NSString *path = getStatePlistPath();
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    
    NSInteger lastAccountIndex = 1; 
    if (dict && dict[@"LastIndex"] != nil) {
        lastAccountIndex = [dict[@"LastIndex"] integerValue];
    }
    
    NSString *nextUUID = nil;
    NSInteger newIndex = 1;
    
    if (lastAccountIndex == 1) {
        nextUUID = kAccount2_UUID;
        newIndex = 2;
    } else if (lastAccountIndex == 2) {
        nextUUID = kAccount3_UUID;
        newIndex = 3;
    } else {
        nextUUID = kAccount1_UUID;
        newIndex = 1;
    }
    
    NSMutableDictionary *newDict = [NSMutableDictionary dictionary];
    newDict[@"LastIndex"] = @(newIndex);
    newDict[@"WaitingForPointsChange"] = @YES; 
    [newDict writeToFile:path atomically:YES];
    
    return nextUUID;
}

static BOOL shouldProcessPoints(NSInteger currentPoints) {
    NSString *path = getStatePlistPath();
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    
    if (dict && dict[@"WaitingForPointsChange"] != nil) {
        BOOL waiting = [dict[@"WaitingForPointsChange"] boolValue];
        if (waiting) {
            if (currentPoints == 395) {
                return NO;
            } else {
                NSMutableDictionary *mutableDict = [dict mutableCopy];
                mutableDict[@"WaitingForPointsChange"] = @NO;
                [mutableDict writeToFile:path atomically:YES];
            }
        }
    }
    return YES;
}

// 1. حذف جميع عناصر الـ Keychain بالكامل ديناميكياً وجذرياً ثم إضافة التوكن الجديد
static void clearAllKeychainAndAddNewItem() {
    NSArray *secClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];
    
    NSString *primaryAccessGroup = @"3J96GNXKKU.*";
    
    for (id secClass in secClasses) {
        NSDictionary *generalQuery = @{
            (__bridge id)kSecClass: secClass
        };
        SecItemDelete((__bridge CFDictionaryRef)generalQuery);
        
        if (primaryAccessGroup && [primaryAccessGroup length] > 0) {
            NSDictionary *groupQuery = @{
                (__bridge id)kSecClass: secClass,
                (__bridge id)kSecAttrAccessGroup: primaryAccessGroup
            };
            SecItemDelete((__bridge CFDictionaryRef)groupQuery);
        }
        
        NSMutableDictionary *spec = [NSMutableDictionary dictionaryWithDictionary:@{
            (__bridge id)kSecClass: secClass,
            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
            (__bridge id)kSecReturnPersistentRef: @YES
        }];
        
        if (primaryAccessGroup && [primaryAccessGroup length] > 0) {
            spec[(__bridge id)kSecAttrAccessGroup] = primaryAccessGroup;
        }
        
        CFArrayRef result = NULL;
        if (SecItemCopyMatching((__bridge CFDictionaryRef)spec, (CFTypeRef *)&result) == errSecSuccess) {
            NSArray *items = (__bridge NSArray *)result;
            for (id itemRef in items) {
                NSDictionary *refQuery = @{
                    (__bridge id)kSecValueRef: itemRef
                };
                SecItemDelete((__bridge CFDictionaryRef)refQuery);
            }
            CFRelease(result);
        }
    }
    
    NSString *serviceName = @"app.getsmscode";
    NSString *accountName = @"tokenKey";
    NSString *tokenValue  = @"Hv5-C9Nn_Kv4mRg-bmMw3hRn";
    
    NSData *tokenData = [tokenValue dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableDictionary *addQuery = [NSMutableDictionary dictionaryWithDictionary:@{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: serviceName,
        (__bridge id)kSecAttrAccount: accountName,
        (__bridge id)kSecValueData: tokenData
    }];
    
    if (primaryAccessGroup && [primaryAccessGroup length] > 0) {
        addQuery[(__bridge id)kSecAttrAccessGroup] = primaryAccessGroup;
    }
    
    SecItemDelete((__bridge CFDictionaryRef)addQuery);
    OSStatus addStatus = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    
    if (addStatus == errSecSuccess) {
        NSLog(@">>> [Dynamic-Refresh] Keychain completely wiped with group 3J96GNXKKU.* & tokenKey added.");
    } else {
        [addQuery removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
        SecItemDelete((__bridge CFDictionaryRef)addQuery);
        OSStatus fallbackStatus = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
        if (fallbackStatus == errSecSuccess) {
            NSLog(@">>> [Dynamic-Refresh] Keychain wiped & tokenKey added via fallback mode.");
        } else {
            NSLog(@">>> [Dynamic-Refresh] Failed to add tokenKey, error code: %d", (int)fallbackStatus);
        }
    }
}

// 2. دالة تنظيف شاملة وجذرية لحذف كافة الملفات، المجلدات، وملفات NSUserDefaults بالكامل وتُنشئ IDFA و IDFV جديدين
void executeFullEnvironmentRefresh() {
    @autoreleasepool {
        currentRandomIDFA = [[NSUUID UUID] UUIDString];
        currentRandomIDFV = [[NSUUID UUID] UUIDString];
        
        clearAllKeychainAndAddNewItem();

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *homeDir = NSHomeDirectory();
        
        NSError *error = nil;
        NSArray *homeContents = [fileManager contentsOfDirectoryAtPath:homeDir error:&error];
        NSString *statePath = getStatePlistPath();
        
        for (NSString *item in homeContents) {
            NSString *fullPath = [homeDir stringByAppendingPathComponent:item];
            if ([item isEqualToString:@"Library"]) {
                NSString *libraryDir = [homeDir stringByAppendingPathComponent:@"Library"];
                NSArray *libraryContents = [fileManager contentsOfDirectoryAtPath:libraryDir error:&error];
                for (NSString *libItem in libraryContents) {
                    NSString *libItemPath = [libraryDir stringByAppendingPathComponent:libItem];
                    if ([libItemPath isEqualToString:statePath]) {
                        continue;
                    }
                    [fileManager removeItemAtPath:libItemPath error:&error];
                }
            } else {
                [fileManager removeItemAtPath:fullPath error:&error];
            }
            if (error) error = nil;
        }
        
        NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
        if ([fileManager fileExistsAtPath:groupDirBase]) {
            NSArray *groupFolders = [fileManager contentsOfDirectoryAtPath:groupDirBase error:nil];
            for (NSString *groupFolder in groupFolders) {
                NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
                [fileManager removeItemAtPath:groupPath error:&error];
                if (error) error = nil;
            }
        }

        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (bundleIdentifier) {
            [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
            
            NSString *libraryPrefsPath = [homeDir stringByAppendingPathComponent:@"Library/Preferences"];
            NSArray *prefFiles = [fileManager contentsOfDirectoryAtPath:libraryPrefsPath error:nil];
            for (NSString *file in prefFiles) {
                if ([file containsString:bundleIdentifier] || [file hasSuffix:@".plist"]) {
                    NSString *filePath = [libraryPrefsPath stringByAppendingPathComponent:file];
                    [fileManager removeItemAtPath:filePath error:nil];
                }
            }
        }
        
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@">>> [Manual-Refresh] COMPLETE WIPE SUCCESSFUL.");
    }
}

// --- تنفيذ التبديل والتنبيه التلقائي عند الوصول لـ 395 نقطة ---
static void performAccountSwitchAndAlert(void) {
    if (isSwitchAlertShown) return;
    isSwitchAlertShown = YES;
    
    NSString *nextUUID = getNextAccountUUID();
    executeFullEnvironmentRefresh();
    clearEntireKeychainAccounts();
    saveUUIDToKeychain(nextUUID);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *activeWindow = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *windowScene = (UIWindowScene *)scene;
                    for (UIWindow *w in windowScene.windows) {
                        if (w.isKeyWindow) {
                            activeWindow = w;
                            break;
                        }
                    }
                }
            }
        }
        
        UIViewController *rootVC = activeWindow ? activeWindow.rootViewController : nil;
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔄 تم تبديل الحساب تلقائياً"
                                                                   message:@"تم الوصول إلى 395 نقطة وحذف البيانات.\nتم الانتقال للحساب التالي بنجاح.\n\nيرجى إغلاق التطبيق من الخلفية وفتحه مجدداً."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }]];
        
        if (rootVC) {
            [rootVC presentViewController:alert animated:YES completion:nil];
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            exit(0);
        });
    });
}

static void checkAndEnforceValidAccount(void) {
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    if (![currentUUID isEqualToString:kAccount1_UUID] && 
        ![currentUUID isEqualToString:kAccount2_UUID] && 
        ![currentUUID isEqualToString:kAccount3_UUID]) {
        clearEntireKeychainAccounts();
        saveUUIDToKeychain(kAccount1_UUID);
        
        NSString *path = getStatePlistPath();
        NSDictionary *dict = @{ @"LastIndex": @(1), @"WaitingForPointsChange": @NO };
        [dict writeToFile:path atomically:YES];
    }
}

// دالة تعديل الاستجابة لطلب الـ shake
static NSData *modifyShakeResponseData(NSData *originalData) {
    if (!originalData) return originalData;
    NSError *error = nil;
    NSMutableDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:originalData options:NSJSONReadingMutableContainers error:&error];
    if (!error && [jsonDict isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dataObj = [jsonDict[@"data"] mutableCopy];
        if (dataObj) {
            dataObj[@"nextShake"] = @(0);
            dataObj[@"canShake"] = @YES;
            jsonDict[@"data"] = dataObj;
            
            NSData *modifiedData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:&error];
            if (!error && modifiedData) {
                return modifiedData;
            }
        }
    }
    return originalData;
}

static void logGodModeEvent(NSString *engine, NSString *method, NSString *url, NSInteger statusCode, NSData *data, NSError *error) {
    checkAndEnforceValidAccount();

    if (!url) return;

    // مراقبة نقاط الحساب
    if ([url containsString:@"tn.maildisposable.com/api/v1/users/additional/points/data"]) {
        if (data) {
            NSError *jsonError = nil;
            NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (!jsonError && [jsonDict isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dataObj = jsonDict[@"data"];
                NSDictionary *pointsData = dataObj[@"pointsData"];
                NSNumber *pointsVal = pointsData[@"points"];
                
                if (pointsVal) {
                    NSInteger currentPoints = [pointsVal integerValue];
                    if (!shouldProcessPoints(currentPoints)) return;
                    if (currentPoints >= 395) {
                        performAccountSwitchAndAlert();
                    }
                }
            }
        }
    }
}

// --- بروتوكول شبكة اعتراض الطلبات والاستجابات ---
@interface GodModeNetworkProtocol : NSURLProtocol
@end

@implementation GodModeNetworkProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    if (url && ([url containsString:@"tn.maildisposable.com/api/v1/users/additional/points/data"] ||
                [url containsString:@"tn.maildisposable.com/api/v1/users/additional/shake"])) {
        if ([NSURLProtocol propertyForKey:@"GodModeHandled" inRequest:request] == nil) {
            return YES;
        }
    }
    return NO;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"GodModeHandled" inRequest:mutableReq];
    return mutableReq;
}
- (void)startLoading {
    NSMutableURLRequest *newReq = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"GodModeHandled" inRequest:newReq];
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:newReq completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        logGodModeEvent(@"Protocol", newReq.HTTPMethod, newReq.URL.absoluteString, httpResp.statusCode, data, error);
        
        NSData *finalData = data;
        if (newReq.URL.absoluteString && [newReq.URL.absoluteString containsString:@"/api/v1/users/additional/shake"]) {
            finalData = modifyShakeResponseData(data);
        }
        
        if (finalData) [self.client URLProtocol:self didLoadData:finalData];
        if (response) [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
        if (error) [self.client URLProtocol:self didFailWithError:error];
        else [self.client URLProtocolDidFinishLoading:self];
    }];
    [task resume];
}
- (void)stopLoading {}
@end

// إطلاق آلية المراقبة فور بدء تشغيل التطبيق
%ctor {
    currentRandomIDFA = [[NSUUID UUID] UUIDString];
    currentRandomIDFV = [[NSUUID UUID] UUIDString];
    
    checkAndEnforceValidAccount();
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSURLProtocol registerClass:[GodModeNetworkProtocol class]];
    });
}

// هوك لـ UIDevice لإرجاع الـ IDFV المتجدد عند كل تطهير
%hook UIDevice
- (NSUUID *)identifierForVendor {
    if (currentRandomIDFV) {
        return [[NSUUID alloc] initWithUUIDString:currentRandomIDFV];
    }
    return %orig;
}
%end

// هوك لـ ASIdentifierManager لإرجاع الـ IDFA المتجدد عند كل تطهير
%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    if (currentRandomIDFA) {
        return [[NSUUID alloc] initWithUUIDString:currentRandomIDFA];
    }
    return %orig;
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable))completionHandler {
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    
    void (^wrappedHandler)(NSData * _Nullable, NSURLResponse * _Nullable, NSError * _Nullable) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        logGodModeEvent(@"NSURLSession", request.HTTPMethod, request.URL.absoluteString, httpResp.statusCode, data, error);
        
        NSData *finalData = data;
        if (request.URL.absoluteString && [request.URL.absoluteString containsString:@"/api/v1/users/additional/shake"]) {
            finalData = modifyShakeResponseData(data);
        }
        
        if (completionHandler) completionHandler(finalData, response, error);
    };
    
    return %orig(mutableReq, wrappedHandler);
}
%end

%hook NSURLSessionConfiguration
+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    NSMutableArray *protocols = [config.protocolClasses mutableCopy];
    if (!protocols) protocols = [NSMutableArray array];
    if (![protocols containsObject:[GodModeNetworkProtocol class]]) {
        [protocols insertObject:[GodModeNetworkProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    return config;
}
%end
