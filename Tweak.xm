#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <Security/Security.h>
#import <objc/runtime.h>

extern void executeFullEnvironmentRefresh(void);

// متغيرات ديناميكية بحتة تتغير كلياً في كل عملية تطهير
static NSString *currentRandomIDFA = nil;
static NSString *currentRandomIDFV = nil;
static NSString *currentFakeSystemVersion = nil;
static NSString *currentFakeModel = nil;
static NSString *currentFakeLocalizedModel = nil;
static NSString *currentFakeDeviceName = nil;
static float     currentFakeBatteryLevel = 0.50f;
static UIDeviceBatteryState currentFakeBatteryState = UIDeviceBatteryStateCharging;

// --- الثوابت وإعدادات الحسابات السبعة (معرفات جديدة بالكامل) ---
static NSString * const kKeychainAccount = @"com.tempnum.virtualnumber.deviceUUID";
static NSString * const kKeychainGroup   = @"3J96GNXKKU.*";
static NSString * const kAccount1_UUID   = @"9F8E7D6C-5B4A-3210-9876-FEDCBA098765";
static NSString * const kAccount2_UUID   = @"4A5B6C7D-8E9F-0123-4567-89ABCDEF0123";
static NSString * const kAccount3_UUID   = @"11223344-5566-7788-99AA-BBCCDDEEFF00";
static NSString * const kAccount4_UUID   = @"A1B2C3D4-E5F6-7890-ABCD-EF0123456789";
static NSString * const kAccount5_UUID   = @"55443322-1100-FFEE-DDCC-BBAA99887766";
static NSString * const kAccount6_UUID   = @"88776655-4433-2211-FFEE-DDCCBBAA9900";
static NSString * const kAccount7_UUID   = @"33221100-FFEE-DDCC-BBAA-998877665544";

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

// --- محرك توليد بصمة عشوائية جديدة كلياً في كل مرة (لا ثبات أبداً) ---
static void generateNewSpoofValues(void) {
    currentRandomIDFA = [[NSUUID UUID] UUIDString];
    currentRandomIDFV = [[NSUUID UUID] UUIDString];
    
    NSArray *majorVersions = @[@"15", @"16", @"17", @"18", @"19", @"26", @"27", @"28"];
    NSArray *minorVersions = @[@"0", @"1", @"2", @"3", @"4", @"5", @"6"];
    int randomMajor = arc4random_uniform((uint32_t)[majorVersions count]);
    int randomMinor = arc4random_uniform((uint32_t)[minorVersions count]);
    currentFakeSystemVersion = [NSString stringWithFormat:@"%@.%@", majorVersions[randomMajor], minorVersions[randomMinor]];
    
    NSArray *modelsList = @[@"iPhone", @"iPad", @"iPod touch"];
    currentFakeModel = modelsList[arc4random_uniform((uint32_t)[modelsList count])];
    currentFakeLocalizedModel = currentFakeModel;
    
    currentFakeDeviceName = [NSString stringWithFormat:@"iPhone-%d-%d", arc4random_uniform(89999) + 10000, arc4random_uniform(900) + 100];
    
    int randomBatteryPercent = arc4random_uniform(95) + 5;
    currentFakeBatteryLevel = (float)randomBatteryPercent / 100.0f;
    
    NSArray *batteryStates = @[@(UIDeviceBatteryStateUnplugged), @(UIDeviceBatteryStateCharging), @(UIDeviceBatteryStateFull)];
    currentFakeBatteryState = (UIDeviceBatteryState)[batteryStates[arc4random_uniform((uint32_t)[batteryStates count])] integerValue];
}

// --- منطق التبديل التسلسلي بين 7 حسابات (1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 1) ---
static NSString *getNextAccountUUID(void) {
    NSString *path = getStatePlistPath();
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    
    NSInteger lastAccountIndex = 1; 
    if (dict && dict[@"LastIndex"] != nil) {
        lastAccountIndex = [dict[@"LastIndex"] integerValue];
    }
    
    NSString *nextUUID = nil;
    NSInteger newIndex = 1;
    
    switch (lastAccountIndex) {
        case 1:
            nextUUID = kAccount2_UUID; newIndex = 2; break;
        case 2:
            nextUUID = kAccount3_UUID; newIndex = 3; break;
        case 3:
            nextUUID = kAccount4_UUID; newIndex = 4; break;
        case 4:
            nextUUID = kAccount5_UUID; newIndex = 5; break;
        case 5:
            nextUUID = kAccount6_UUID; newIndex = 6; break;
        case 6:
            nextUUID = kAccount7_UUID; newIndex = 7; break;
        default:
            nextUUID = kAccount1_UUID; newIndex = 1; break;
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
            if (currentPoints == 200 || currentPoints == 395) {
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
        NSDictionary *generalQuery = @{ (__bridge id)kSecClass: secClass };
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
        if (primaryAccessGroup) spec[(__bridge id)kSecAttrAccessGroup] = primaryAccessGroup;
        
        CFArrayRef result = NULL;
        if (SecItemCopyMatching((__bridge CFDictionaryRef)spec, (CFTypeRef *)&result) == errSecSuccess) {
            NSArray *items = (__bridge NSArray *)result;
            for (id itemRef in items) {
                NSDictionary *refQuery = @{ (__bridge id)kSecValueRef: itemRef };
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
    if (primaryAccessGroup) addQuery[(__bridge id)kSecAttrAccessGroup] = primaryAccessGroup;
    
    SecItemDelete((__bridge CFDictionaryRef)addQuery);
    SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
}

// --- دالة التنظيف الشامل وتوليد خصائص عشوائية جديدة كلياً ---
void executeFullEnvironmentRefresh() {
    @autoreleasepool {
        generateNewSpoofValues();
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
                    if ([libItemPath isEqualToString:statePath]) continue;
                    [fileManager removeItemAtPath:libItemPath error:&error];
                }
            } else {
                [fileManager removeItemAtPath:fullPath error:&error];
            }
            error = nil;
        }
        
        NSString *groupDirBase = [[[homeDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"Group Containers"];
        if ([fileManager fileExistsAtPath:groupDirBase]) {
            NSArray *groupFolders = [fileManager contentsOfDirectoryAtPath:groupDirBase error:nil];
            for (NSString *groupFolder in groupFolders) {
                NSString *groupPath = [groupDirBase stringByAppendingPathComponent:groupFolder];
                [fileManager removeItemAtPath:groupPath error:&error];
                error = nil;
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
    }
}

// --- تنفيذ التبديل والتنبيه ---
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
                        if (w.isKeyWindow) { activeWindow = w; break; }
                    }
                }
            }
        }
        
        UIViewController *rootVC = activeWindow ? activeWindow.rootViewController : nil;
        while (rootVC.presentedViewController) { rootVC = rootVC.presentedViewController; }
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔄 تم تبديل الحساب (من أصل 7) وتوليد بصمة جديدة"
                                                                   message:@"تم الوصول للحد المطلوب (200 أو 395 نقطة) وتطهير البيانات بنجاح.\nيرجى إغلاق التطبيق وفتحه مجدداً."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }]];
        
        if (rootVC) [rootVC presentViewController:alert animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            exit(0);
        });
    });
}

static void checkAndEnforceValidAccount(void) {
    NSString *currentUUID = getAppCurrentUUIDFromKeychain();
    if (![currentUUID isEqualToString:kAccount1_UUID] && 
        ![currentUUID isEqualToString:kAccount2_UUID] && 
        ![currentUUID isEqualToString:kAccount3_UUID] && 
        ![currentUUID isEqualToString:kAccount4_UUID] && 
        ![currentUUID isEqualToString:kAccount5_UUID] && 
        ![currentUUID isEqualToString:kAccount6_UUID] && 
        ![currentUUID isEqualToString:kAccount7_UUID]) {
        clearEntireKeychainAccounts();
        saveUUIDToKeychain(kAccount1_UUID);
        
        NSString *path = getStatePlistPath();
        NSDictionary *dict = @{ @"LastIndex": @(1), @"WaitingForPointsChange": @NO };
        [dict writeToFile:path atomically:YES];
    }
}

// --- معالجة فحص النقاط بشكل خفي تماماً وسريع في الخلفية ---
static void processStealthPointsAsync(NSData *data) {
    if (!data) return;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        checkAndEnforceValidAccount();

        NSError *jsonError = nil;
        NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (!jsonError && [jsonDict isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dataObj = jsonDict[@"data"];
            NSDictionary *pointsData = dataObj[@"pointsData"];
            NSNumber *pointsVal = pointsData[@"points"];
            
            if (pointsVal) {
                NSInteger currentPoints = [pointsVal integerValue];
                if (!shouldProcessPoints(currentPoints)) return;
                
                if (currentPoints == 200 || currentPoints == 395) {
                    performAccountSwitchAndAlert();
                }
            }
        }
    });
}

// --- بروتوكول الشبكة الخفي فائق السرعة ---
@interface StealthNetworkProtocol : NSURLProtocol
@end

@implementation StealthNetworkProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    if (url && [url containsString:@"tn.maildisposable.com/api/v1/users/additional/points/data"]) {
        if ([NSURLProtocol propertyForKey:@"StealthHandledKey" inRequest:request] == nil) {
            return YES;
        }
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"StealthHandledKey" inRequest:mutableReq];
    return mutableReq;
}

- (void)startLoading {
    NSMutableURLRequest *newReq = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"StealthHandledKey" inRequest:newReq];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:newReq completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        if (error) {
            [self.client URLProtocol:self didFailWithError:error];
            return;
        }
        
        if (response) {
            [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
        }
        
        if (data) {
            [self.client URLProtocol:self didLoadData:data];
            processStealthPointsAsync(data);
        }
        
        [self.client URLProtocolDidFinishLoading:self];
    }];
    
    [task resume];
}

- (void)stopLoading {}

@end

// --- هوكس التزوير الديناميكية بالكامل لـ UIDevice ---
%hook UIDevice
- (NSUUID *)identifierForVendor {
    if (currentRandomIDFV) {
        return [[NSUUID alloc] initWithUUIDString:currentRandomIDFV];
    }
    return %orig;
}

- (NSString *)systemVersion {
    if (currentFakeSystemVersion) { return currentFakeSystemVersion; }
    return %orig;
}

- (NSString *)model {
    if (currentFakeModel) { return currentFakeModel; }
    return %orig;
}

- (NSString *)localizedModel {
    if (currentFakeLocalizedModel) { return currentFakeLocalizedModel; }
    return %orig;
}

- (NSString *)name {
    if (currentFakeDeviceName) { return currentFakeDeviceName; }
    return %orig;
}

- (float)batteryLevel { return currentFakeBatteryLevel; }
- (UIDeviceBatteryState)batteryState { return currentFakeBatteryState; }
- (BOOL)isBatteryMonitoringEnabled { return YES; }
%end

// --- هوك الـ IDFA لـ ASIdentifierManager ---
%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    if (currentRandomIDFA) {
        return [[NSUUID alloc] initWithUUIDString:currentRandomIDFA];
    }
    return %orig;
}
%end

// --- إدراج البروتوكول الخفي تلقائياً ---
%hook NSURLSessionConfiguration
+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    NSMutableArray *protocols = [config.protocolClasses mutableCopy];
    if (!protocols) protocols = [NSMutableArray array];
    if (![protocols containsObject:[StealthNetworkProtocol class]]) {
        [protocols insertObject:[StealthNetworkProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    return config;
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    NSURLSessionConfiguration *config = %orig;
    NSMutableArray *protocols = [config.protocolClasses mutableCopy];
    if (!protocols) protocols = [NSMutableArray array];
    if (![protocols containsObject:[StealthNetworkProtocol class]]) {
        [protocols insertObject:[StealthNetworkProtocol class] atIndex:0];
        config.protocolClasses = protocols;
    }
    return config;
}
%end

%ctor {
    generateNewSpoofValues();
    checkAndEnforceValidAccount();
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [NSURLProtocol registerClass:[StealthNetworkProtocol class]];
    });
}
