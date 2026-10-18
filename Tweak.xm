#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>
#import <AdSupport/AdSupport.h>
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// --- الثوابت وأسماء الحاويات الأربع المعزولة تماماً ---
static NSString * const kContainer1 = @"Container1";
static NSString * const kContainer2 = @"Container2";
static NSString * const kContainer3 = @"Container3";
static NSString * const kContainer4 = @"Container4";

// --- متغيرات النقاط الحية للوحة الإرشادية ---
static NSMutableDictionary *gAccountPointsMap = nil;

// --- دوال مساعدة لجلب النافذة الرئيسية بأمان تام ---
static UIWindow *getSafeKeyWindow(void) {
    UIWindow *foundWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) {
                        foundWindow = w;
                        break;
                    }
                }
                if (!foundWindow && windowScene.windows.count > 0) {
                    foundWindow = windowScene.windows.firstObject;
                }
            }
            if (foundWindow) break;
        }
    }
    if (!foundWindow) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        foundWindow = [UIApplication sharedApplication].keyWindow;
        #pragma clang diagnostic pop
    }
    return foundWindow;
}

// --- مسار ملف الحالة العام (لحفظ الحاوية النشطة والنقاط فقط) ---
static NSString *getGlobalStatePath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    return [[paths firstObject] stringByAppendingPathComponent:@"GlobalContainerState.plist"];
}

// --- معرفة الحاوية النشطة حالياً ---
static NSString *getActiveContainerName(void) {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:getGlobalStatePath()];
    NSString *current = dict[@"ActiveContainer"];
    if (!current) return kContainer1;
    return current;
}

// --- إرجاع المسار المعزول الخاص بالحاوية النشطة ---
static NSString *getIsolatedHomeDirectory(void) {
    NSString *realHome = NSHomeDirectory();
    NSString *containerName = getActiveContainerName();
    NSString *isolatedPath = [[realHome stringByAppendingPathComponent:@"ContainersSandbox"] stringByAppendingPathComponent:containerName];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:isolatedPath]) {
        [fm createDirectoryAtPath:isolatedPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return isolatedPath;
}

// --- مسار ملف NSUserDefaults الخاص بالحاوية الحالية ---
static NSString *getIsolatedUserDefaultsPath(void) {
    NSString *isolatedHome = getIsolatedHomeDirectory();
    NSString *prefDir = [isolatedHome stringByAppendingPathComponent:@"Library/Preferences"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:prefDir]) {
        [fm createDirectoryAtPath:prefDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return [prefDir stringByAppendingPathComponent:@"IsolatedUserDefaults.plist"];
}

// --- واجهة اللوحة العائمة لعرض الحاويات والنقاط وأزرار الباك أب ---
@interface AccountStatusOverlayView : UIView <UIDocumentPickerDelegate>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailsLabel;
@property (nonatomic, strong) UIButton *backupButton;
@property (nonatomic, strong) UIButton *restoreButton;
@end

@implementation AccountStatusOverlayView
+ (instancetype)sharedInstance {
    static AccountStatusOverlayView *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AccountStatusOverlayView alloc] initWithFrame:CGRectMake([UIScreen mainScreen].bounds.size.width - 185, 45, 180, 150)];
    });
    return sharedInstance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
        self.layer.cornerRadius = 8;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor greenColor].CGColor;
        self.clipsToBounds = YES;
        
        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(4, 2, 172, 18)];
        self.titleLabel.textColor = [UIColor greenColor];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:10];
        self.titleLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:self.titleLabel];
        
        self.detailsLabel = [[UILabel alloc] initWithFrame:CGRectMake(4, 21, 172, 85)];
        self.detailsLabel.textColor = [UIColor whiteColor];
        self.detailsLabel.font = [UIFont systemFontOfSize:8.0];
        self.detailsLabel.numberOfLines = 0;
        self.detailsLabel.textAlignment = NSTextAlignmentRight;
        [self addSubview:self.detailsLabel];
        
        self.backupButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.backupButton.frame = CGRectMake(4, 110, 84, 35);
        [self.backupButton setTitle:@"حفظ للجهاز" forState:UIControlStateNormal];
        [self.backupButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        self.backupButton.backgroundColor = [UIColor greenColor];
        self.backupButton.titleLabel.font = [UIFont boldSystemFontOfSize:9];
        self.backupButton.layer.cornerRadius = 4;
        [self.backupButton addTarget:self action:@selector(makeBackupTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.backupButton];
        
        self.restoreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.restoreButton.frame = CGRectMake(92, 110, 84, 35);
        [self.restoreButton setTitle:@"استعادة ملف" forState:UIControlStateNormal];
        [self.restoreButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.restoreButton.backgroundColor = [UIColor systemBlueColor];
        self.restoreButton.titleLabel.font = [UIFont boldSystemFontOfSize:9];
        self.restoreButton.layer.cornerRadius = 4;
        [self.restoreButton addTarget:self action:@selector(restoreBackupTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:self.restoreButton];
    }
    return self;
}

- (void)updateContent {
    NSString *currContainer = getActiveContainerName();
    self.titleLabel.text = [NSString stringWithFormat:@"الحاوية النشطة: %@", currContainer];
    
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:getGlobalStatePath()];
    NSDictionary *pointsMap = dict[@"PointsMap"] ?: @{};
    
    self.detailsLabel.text = [NSString stringWithFormat:@"حاوية ١: %@ نقطة\nحاوية ٢: %@ نقطة\nحاوية ٣: %@ نقطة\nحاوية ٤: %@ نقطة",
                              pointsMap[kContainer1] ?: @(0),
                              pointsMap[kContainer2] ?: @(0),
                              pointsMap[kContainer3] ?: @(0),
                              pointsMap[kContainer4] ?: @(0)];
}

- (void)makeBackupTapped {
    NSString *statePath = getGlobalStatePath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:statePath]) return;
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd_HH-mm-ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    NSString *tempFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Containers_Backup_%@.plist", timestamp]];
    [[NSFileManager defaultManager] copyItemAtPath:statePath toPath:tempFilePath error:nil];
    
    NSURL *fileURL = [NSURL fileURLWithPath:tempFilePath];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    
    UIWindow *keyWindow = getSafeKeyWindow();
    UIViewController *rootVC = keyWindow.rootViewController;
    while (rootVC.presentedViewController) { rootVC = rootVC.presentedViewController; }
    
    if (rootVC) {
        if ([activityVC respondsToSelector:@selector(popoverPresentationController)]) {
            activityVC.popoverPresentationController.sourceView = self.backupButton;
        }
        [rootVC presentViewController:activityVC animated:YES completion:nil];
    }
}

- (void)restoreBackupTapped {
    UIWindow *keyWindow = getSafeKeyWindow();
    UIViewController *rootVC = keyWindow.rootViewController;
    while (rootVC.presentedViewController) { rootVC = rootVC.presentedViewController; }
    
    UIDocumentPickerViewController *documentPicker = nil;
    if (@available(iOS 14.0, *)) {
        documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"com.apple.property-list"]]];
    } else {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"com.apple.property-list"] inMode:UIDocumentPickerModeImport];
        #pragma clang diagnostic pop
    }
    documentPicker.delegate = self;
    
    if (rootVC) {
        [rootVC presentViewController:documentPicker animated:YES completion:nil];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *selectedURL = [urls firstObject];
    if (!selectedURL) return;
    
    [selectedURL startAccessingSecurityScopedResource];
    NSData *data = [NSData dataWithContentsOfURL:selectedURL];
    [selectedURL stopAccessingSecurityScopedResource];
    
    if (data) {
        NSString *destPath = getGlobalStatePath();
        [data writeToFile:destPath atomically:YES];
        
        UIWindow *keyWindow = getSafeKeyWindow();
        UIViewController *rootVC = keyWindow.rootViewController;
        while (rootVC.presentedViewController) { rootVC = rootVC.presentedViewController; }
        
        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"✅ تم الاستعادة بنجاح"
                                                                   message:@"تم استعادة إعدادات الحاويات، سيتم إعادة تشغيل التطبيق."
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [successAlert addAction:[UIAlertAction actionWithTitle:@"إعادة تشغيل" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }]];
        if (rootVC) {
            [rootVC presentViewController:successAlert animated:YES completion:nil];
        } else {
            exit(0);
        }
    }
}
@end

// --- إظهار النافذة العائمة ---
void setupOverlayWindow(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = getSafeKeyWindow();
        if (keyWindow) {
            AccountStatusOverlayView *overlay = [AccountStatusOverlayView sharedInstance];
            [keyWindow addSubview:overlay];
            [overlay updateContent];
        }
    });
}

// --- التبديل التسلسلي بين الحاويات الأربع ---
NSString *getNextContainerName(void) {
    NSString *path = getGlobalStatePath();
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    if (!dict) dict = [NSMutableDictionary dictionary];
    
    NSString *currentContainer = dict[@"ActiveContainer"] ?: kContainer1;
    NSString *nextContainer = kContainer1;
    
    if ([currentContainer isEqualToString:kContainer1]) nextContainer = kContainer2;
    else if ([currentContainer isEqualToString:kContainer2]) nextContainer = kContainer3;
    else if ([currentContainer isEqualToString:kContainer3]) nextContainer = kContainer4;
    else nextContainer = kContainer1;
    
    dict[@"ActiveContainer"] = nextContainer;
    [dict writeToFile:path atomically:YES];
    
    return nextContainer;
}

static BOOL isAlertShown = NO;

// --- معالجة النقاط والتبديل التسلسلي ---
void handlePointsLogic(NSInteger currentPoints) {
    NSString *currentContainer = getActiveContainerName();
    
    NSString *path = getGlobalStatePath();
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    if (!dict) dict = [NSMutableDictionary dictionary];
    
    NSMutableDictionary *pointsMap = [dict[@"PointsMap"] mutableCopy];
    if (!pointsMap) pointsMap = [NSMutableDictionary dictionary];
    pointsMap[currentContainer] = @(currentPoints);
    dict[@"PointsMap"] = pointsMap;
    [dict writeToFile:path atomically:YES];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[AccountStatusOverlayView sharedInstance] updateContent];
    });

    if (isAlertShown) return;
    
    NSInteger lastProcessed = [dict[@"LastProcessedPoints"] integerValue];
    
    if (currentPoints >= 395) {
        if (lastProcessed != 395) {
            dict[@"LastProcessedPoints"] = @(395);
            [dict writeToFile:path atomically:YES];
            
            isAlertShown = YES;
            NSString *nextContainer = getNextContainerName();
            
            dispatch_async(dispatch_get_main_queue(), ^{
                UIWindow *keyWindow = getSafeKeyWindow();
                UIViewController *rootVC = keyWindow.rootViewController;
                while (rootVC.presentedViewController) { rootVC = rootVC.presentedViewController; }
                
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔄 تم التبديل للحاوية التالية"
                                                                   message:[NSString stringWithFormat:@"تم الوصول إلى 395 نقطة.\nتم الانتقال إلى (%@) بمساراتها المستقلة.\n\nسيتم إغلاق التطبيق الآن...", nextContainer]
                                                            preferredStyle:UIAlertControllerStyleAlert];
                if (rootVC) {
                    [rootVC presentViewController:alert animated:YES completion:^{
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            exit(0);
                        });
                    }];
                } else {
                    exit(0);
                }
            });
        }
    } else {
        if (currentPoints < 395 && lastProcessed != -1) {
            dict[@"LastProcessedPoints"] = @(-1);
            [dict writeToFile:path atomically:YES];
        }
    }
}

void checkAndEnforceValidContainer(void) {
    NSString *path = getGlobalStatePath();
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if (![fm fileExistsAtPath:path]) {
        NSDictionary *defaultDict = @{ 
            @"ActiveContainer": kContainer1, 
            @"LastProcessedPoints": @(-1),
            @"PointsMap": @{}
        };
        [defaultDict writeToFile:path atomically:YES];
    }
}

// ==========================================
// 4. مراقبة واعتراض شبكة الإنترنت (رصد الـ 395 نقطة)
// ==========================================
NSData *modifyResponseDataIfNeeded(NSString *url, NSData *data) {
    if (!data || !url) return data;
    
    if ([url containsString:@"tn.maildisposable.com/api/v1/users/additional/points/data"]) {
        NSError *jsonError = nil;
        NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        if (!jsonError && [jsonDict isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dataObj = jsonDict[@"data"];
            NSDictionary *pointsData = dataObj[@"pointsData"];
            NSNumber *pointsVal = pointsData[@"points"];
            
            if (pointsVal) {
                NSInteger currentPoints = [pointsVal integerValue];
                handlePointsLogic(currentPoints);
            }
        }
    }
    return data;
}

@interface GodModeNetworkProtocol : NSURLProtocol
@end

@implementation GodModeNetworkProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    if (url && [url containsString:@"tn.maildisposable.com"]) {
        if ([url containsString:@"api/v1/users/additional/points/data"]) {
            if ([NSURLProtocol propertyForKey:@"GodModeHandled" inRequest:request] == nil) {
                return YES;
            }
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
        NSData *finalData = modifyResponseDataIfNeeded(newReq.URL.absoluteString, data);
        if (finalData) [self.client URLProtocol:self didLoadData:finalData];
        if (response) [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
        if (error) [self.client URLProtocol:self didFailWithError:error];
        else [self.client URLProtocolDidFinishLoading:self];
    }];
    [task resume];
}

- (void)stopLoading {}
@end

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

// ==========================================
// 1. عزل الـ NSUserDefaults بالكامل لكل حاوية
// ==========================================
%hook NSUserDefaults

- (id)objectForKey:(NSString *)defaultName {
    NSString *plistPath = getIsolatedUserDefaultsPath();
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (dict && dict[defaultName] != nil) {
        return dict[defaultName];
    }
    return %orig;
}

- (void)setObject:(id)value forKey:(NSString *)defaultName {
    NSString *plistPath = getIsolatedUserDefaultsPath();
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:plistPath];
    if (!dict) dict = [NSMutableDictionary dictionary];
    
    if (value) {
        dict[defaultName] = value;
    } else {
        [dict removeObjectForKey:defaultName];
    }
    [dict writeToFile:plistPath atomically:YES];
    %orig;
}

- (void)removeObjectForKey:(NSString *)defaultName {
    NSString *plistPath = getIsolatedUserDefaultsPath();
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithContentsOfFile:plistPath];
    if (dict && dict[defaultName] != nil) {
        [dict removeObjectForKey:defaultName];
        [dict writeToFile:plistPath atomically:YES];
    }
    %orig;
}

- (BOOL)synchronize {
    return YES;
}

%end

// ==========================================
// 2. عزل الـ Keychain بتوجيه نطاق الحاوية الحصرية
// ==========================================
static NSMutableDictionary *isolateKeychainAccessGroupForContainer(CFDictionaryRef query) {
    NSMutableDictionary *mutableQuery = [(__bridge NSDictionary *)query mutableCopy];
    if (!mutableQuery) return nil;
    
    NSString *containerName = getActiveContainerName();
    NSString *containerKeychainGroup = [NSString stringWithFormat:@"com.app.container.%@", containerName];
    mutableQuery[(__bridge id)kSecAttrAccessGroup] = containerKeychainGroup;
    
    return mutableQuery;
}

%hookf(OSStatus, SecItemAdd, CFDictionaryRef attributes, CFTypeRef *result) {
    NSMutableDictionary *modQuery = isolateKeychainAccessGroupForContainer(attributes);
    return %orig((__bridge CFDictionaryRef)modQuery, result);
}

%hookf(OSStatus, SecItemCopyMatching, CFDictionaryRef query, CFTypeRef *result) {
    NSMutableDictionary *modQuery = isolateKeychainAccessGroupForContainer(query);
    return %orig((__bridge CFDictionaryRef)modQuery, result);
}

%hookf(OSStatus, SecItemUpdate, CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    NSMutableDictionary *modQuery = isolateKeychainAccessGroupForContainer(query);
    return %orig((__bridge CFDictionaryRef)modQuery, attributesToUpdate);
}

%hookf(OSStatus, SecItemDelete, CFDictionaryRef query) {
    NSMutableDictionary *modQuery = isolateKeychainAccessGroupForContainer(query);
    return %orig((__bridge CFDictionaryRef)modQuery);
}

// ==========================================
// 3. عزل مسارات الملفات والمجلدات لكل حاوية
// ==========================================
%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if ([path hasPrefix:NSHomeDirectory()]) {
        NSString *isolated = [path stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:getIsolatedHomeDirectory()];
        return %orig(isolated, isDirectory);
    }
    return %orig;
}

- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSFileAttributeKey,id> *)attributes error:(NSError **)error {
    if ([path hasPrefix:NSHomeDirectory()]) {
        NSString *isolated = [path stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:getIsolatedHomeDirectory()];
        return %orig(isolated, createIntermediates, attributes, error);
    }
    return %orig;
}
%end

%ctor {
    gAccountPointsMap = [NSMutableDictionary dictionary];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        checkAndEnforceValidContainer();
        setupOverlayWindow();
    });
}
