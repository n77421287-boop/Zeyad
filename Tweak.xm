#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <Security/Security.h>

static NSArray *tokens = nil;
static NSArray *fixedIDFAs = nil;
static NSArray *fixedIDFVs = nil;

#define CURRENT_ACCOUNT_INDEX_KEY (@"Tweak_CurrentAccountIndex_Key")

static void initializeDataIfNeeded() {
    if (!tokens) {
        tokens = @[
            @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiI2YWYwODM1MGUyM2RhNmVlZGZiZjUyNzAiLCJpYXQiOjE3OTQxNDcxNTJ9.D9mShMyfrI5Vpw2KxQHn3pN69Vs9lXi3GNqf4qSJc9s",
            @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiI2YWYwODM5NWQxYTNhMWRmYTE4OGU3NmEiLCJpYXQiOjE3OTQxNDcyMjF9.3_G6e-xk_uoNAC36dCIyqd4eOIHdyOm533iEHjh5zKw",
            @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiI2YWYwODQwNGQ2ZDZiMGFmMTI1ZDlhMjkiLCJpYXQiOjE3OTQxNDczMzJ9.s_LEynp6QrdYrIkV46f63CNx3L2If6koKBYHtwT-SS4",
            @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiI2YWYwODQ2NDJjYjcwZTY2YmY4NzMxZDQiLCJpYXQiOjE3OTQxNDc0Mjh9.0o5vLTIccYak9hhldkzz8_0mABjfvbuq8ot0K446XUI",
            @"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiI2YWYwODQ5NDMyMWQ0ZDgyMTE1MGJiM2IiLCJpYXQiOjE3OTQxNDc0NzZ9.S5PnwRYaiYhFBCyboJEwxCMUEuWtnY_jF_9yXlFeHoc"
        ];
        
        fixedIDFAs = @[
            @"E78A4B29-4F12-4C3D-8891-A2B3C4D5E6F7",
            @"3F9C2E1A-8B44-4E56-9123-5F6E7D8C9B0A",
            @"8A1B2C3D-4E5F-6A7B-8C9D-0E1F2A3B4C5D",
            @"C5D4E3F2-B1A0-9F8E-7D6C-5B4A39281706",
            @"1A2B3C4D-5E6F-7A8B-9C0D-1E2F3A4B5C6D"
        ];
        
        fixedIDFVs = @[
            @"7C4B29E1-2F88-4A3D-91EE-B4C5D6E7F8A9",
            @"9D2E1A3F-448B-56E5-2391-6E7F8C9A0B1C",
            @"2B3C4D5A-1E6F-7B8A-9D8C-1F2E3D4C5B6A",
            @"4E3F2D1C-0A9F-8E7D-6C5B-4A39281706BF",
            @"3C4D5E6F-8A7B-9C0D-1E2F-3A4B5C6D7E8F"
        ];
    }
}

// دالة حديثة وآمنة لجلب النافذة الرئيسية دون استخدام keyWindow الملغاة
static UIWindow *getCurrentWindow() {
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in scene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
        }
    }
    return [[[UIApplication sharedApplication] windows] firstObject];
}

static void clearAndBlockKeychain() {
    NSArray *secClasses = @[
        (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecClassInternetPassword,
        (__bridge id)kSecClassCertificate,
        (__bridge id)kSecClassKey,
        (__bridge id)kSecClassIdentity
    ];
    for (id secClass in secClasses) {
        NSDictionary *spec = @{ (__bridge id)kSecClass: secClass };
        SecItemDelete((__bridge CFDictionaryRef)spec);
    }
}

static void switchToNextAccount() {
    initializeDataIfNeeded();
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger currentIndex = [defaults integerForKey:CURRENT_ACCOUNT_INDEX_KEY];
    
    NSInteger nextIndex = (currentIndex + 1) % [tokens count];
    [defaults setInteger:nextIndex forKey:CURRENT_ACCOUNT_INDEX_KEY];
    
    NSString *selectedToken = tokens[nextIndex];
    
    NSDictionary *dict = [defaults dictionaryRepresentation];
    for (NSString *key in [dict allKeys]) {
        if (![key isEqualToString:CURRENT_ACCOUNT_INDEX_KEY]) {
            [defaults removeObjectForKey:key];
        }
    }
    
    [defaults setObject:selectedToken forKey:@"auth_token"];
    [defaults setBool:YES forKey:@"onboarding_completed"];
    [defaults synchronize];
    
    clearAndBlockKeychain();
    
    NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSString *tmpPath = NSTemporaryDirectory();
    [[NSFileManager defaultManager] removeItemAtPath:cachePath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = getCurrentWindow();
        if (keyWindow) {
            UIView *flashView = [[UIView alloc] initWithFrame:keyWindow.bounds];
            flashView.backgroundColor = [UIColor blackColor];
            flashView.alpha = 0.0;
            [keyWindow addSubview:flashView];
            
            [UIView animateWithDuration:0.15 animations:^{
                flashView.alpha = 0.4;
            } completion:^(BOOL finished) {
                [UIView animateWithDuration:0.15 animations:^{
                    flashView.alpha = 0.0;
                } completion:^(BOOL finished2) {
                    [flashView removeFromSuperview];
                    
                    UIViewController *oldRoot = keyWindow.rootViewController;
                    keyWindow.rootViewController = oldRoot;
                }];
            }];
        }
    });
}

@interface FloatingButtonWindow : UIWindow
@end

@implementation FloatingButtonWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *btn = [self viewWithTag:9988];
    CGPoint btnPoint = [self convertPoint:point toView:btn];
    if ([btn pointInside:btnPoint withEvent:event]) {
        return YES;
    }
    return NO;
}
@end

@interface AccountSwitcherButtonManager : NSObject
@property (strong, nonatomic) FloatingButtonWindow *floatingWindow;
+ (instancetype)sharedInstance;
- (void)setupFloatingButton;
@end

@implementation AccountSwitcherButtonManager

+ (instancetype)sharedInstance {
    static AccountSwitcherButtonManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AccountSwitcherButtonManager alloc] init];
    });
    return sharedInstance;
}

- (void)setupFloatingButton {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.floatingWindow) return;
        
        CGRect frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 75, 45, 65, 32);
        self.floatingWindow = [[FloatingButtonWindow alloc] initWithFrame:frame];
        self.floatingWindow.windowLevel = UIWindowLevelAlert + 9999;
        self.floatingWindow.hidden = NO;
        self.floatingWindow.backgroundColor = [UIColor clearColor];
        
        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        
        UIButton *floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
        floatingButton.frame = vc.view.bounds;
        floatingButton.tag = 9988;
        [floatingButton setTitle:@"🔄 حساب" forState:UIControlStateNormal];
        [floatingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        floatingButton.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        floatingButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:0.9];
        floatingButton.layer.cornerRadius = 8;
        floatingButton.layer.shadowColor = [[UIColor blackColor] CGColor];
        floatingButton.layer.shadowOpacity = 0.4;
        floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
        
        [floatingButton addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
        
        [vc.view addSubview:floatingButton];
        self.floatingWindow.rootViewController = vc;
        [self.floatingWindow makeKeyAndVisible];
        
        UIWindow *mainWin = getCurrentWindow();
        if (mainWin && mainWin != self.floatingWindow) {
            [mainWin makeKeyWindow];
        }
    });
}

- (void)buttonTapped {
    switchToNextAccount();
}

@end

%ctor {
    initializeDataIfNeeded();
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:@"auth_token"]) {
        NSInteger currentIndex = [defaults integerForKey:CURRENT_ACCOUNT_INDEX_KEY];
        [defaults setObject:tokens[currentIndex] forKey:@"auth_token"];
        [defaults setBool:YES forKey:@"onboarding_completed"];
        [defaults synchronize];
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[AccountSwitcherButtonManager sharedInstance] setupFloatingButton];
    });
    
    [[NSNotificationCenter defaultCenter] addObserverForName:UIWindowDidBecomeVisibleNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        [[AccountSwitcherButtonManager sharedInstance] setupFloatingButton];
    }];
}

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    initializeDataIfNeeded();
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger currentIndex = [defaults integerForKey:CURRENT_ACCOUNT_INDEX_KEY];
    return [[NSUUID alloc] initWithUUIDString:fixedIDFAs[currentIndex]];
}
%end

%hook UIDevice
- (NSUUID *)identifierForVendor {
    initializeDataIfNeeded();
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger currentIndex = [defaults integerForKey:CURRENT_ACCOUNT_INDEX_KEY];
    return [[NSUUID alloc] initWithUUIDString:fixedIDFVs[currentIndex]];
}
%end

%hook SecItem
OSStatus SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    return errSecSuccess;
}
OSStatus SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    return errSecItemNotFound;
}
OSStatus SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    return errSecSuccess;
}
OSStatus SecItemDelete(CFDictionaryRef query) {
    return errSecSuccess;
}
%end
