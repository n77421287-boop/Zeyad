#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <mach/mach_time.h>

// ==========================================
// 1. تعريف واجهات أبل السرية لإنشاء الأحداث (مثل iGameGod)
// ==========================================
@interface UITouch (Private)
- (void)setPhase:(UITouchPhase)phase;
- (void)setLocationInWindow:(CGPoint)location;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setIsTap:(BOOL)isTap;
- (void)setTapCount:(NSUInteger)tapCount;
@end

@interface UIEvent (Private)
- (void)_addTouch:(UITouch *)touch forFocusedForcedPanGestureRecognizer:(id)recognizer;
- (void)_clearTouches;
@end

// ==========================================
// 2. بنية البيانات للحدث المسجل
// ==========================================
@interface RecordedEvent : NSObject <NSCoding>
@property (nonatomic, assign) CGPoint point;
@property (nonatomic, assign) NSInteger phase;
@property (nonatomic, assign) NSTimeInterval timeOffset;
@end

@implementation RecordedEvent
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeCGPoint:_point forKey:@"point"];
    [coder encodeInteger:_phase forKey:@"phase"];
    [coder encodeDouble:_timeOffset forKey:@"timeOffset"];
}
- (id)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _point = [coder decodeCGPointForKey:@"point"];
        _phase = [coder decodeIntegerForKey:@"phase"];
        _timeOffset = [coder decodeDoubleForKey:@"timeOffset"];
    }
    return self;
}
@end

// ==========================================
// 3. إدارة الماكرو واللمس بنظام iGameGod
// ==========================================
@interface MacroManager : NSObject
@property (nonatomic, strong) UIWindow *floatingWindow;
@property (nonatomic, strong) UIWindow *toastWindow;
@property (nonatomic, strong) UILabel *toastLabel;

@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UISwitch *autoStartSwitch;

@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) BOOL persistentAutoStart;

@property (nonatomic, strong) NSMutableArray<RecordedEvent *> *recordedEvents;
@property (nonatomic, assign) NSTimeInterval lastEventTimestamp;
@property (nonatomic, strong) dispatch_queue_t macroQueue;

+ (instancetype)sharedInstance;
- (void)setupUI;
- (void)showTouchIndicatorAtPoint:(CGPoint)point;
- (void)showToast:(NSString *)message;
- (void)ensureUIVisible;
- (void)startRecording;
- (void)stopAll;
- (void)saveMacroAndSettings;
- (void)clearMacro;
- (void)startPlaybackLoop;
@end

@implementation MacroManager

+ (instancetype)sharedInstance {
    static MacroManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[MacroManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _recordedEvents = [NSMutableArray array];
        _macroQueue = dispatch_queue_create("com.igamegod.macro.queue", DISPATCH_QUEUE_SERIAL);
        [self loadDataFromFile];
    }
    return self;
}

- (NSString *)filePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    return [documentsDirectory stringByAppendingPathComponent:@"automacro_config.plist"];
}

- (void)saveMacroAndSettings {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSData *eventsData = [NSKeyedArchiver archivedDataWithRootObject:_recordedEvents];
#pragma clang diagnostic pop

    [dict setObject:eventsData forKey:@"events"];
    [dict setObject:@(_persistentAutoStart) forKey:@"autoStart"];
    
    [dict writeToFile:[self filePath] atomically:YES];
}

- (void)loadDataFromFile {
    NSString *path = [self filePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if (dict) {
            NSData *eventsData = [dict objectForKey:@"events"];
            if (eventsData) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                NSArray *loaded = [NSKeyedUnarchiver unarchiveObjectWithData:eventsData];
#pragma clang diagnostic pop
                if (loaded) {
                    [_recordedEvents setArray:loaded];
                }
            }
            NSNumber *autoStartNum = [dict objectForKey:@"autoStart"];
            if (autoStartNum) {
                _persistentAutoStart = [autoStartNum boolValue];
            }
        }
    }
}

- (void)clearMacro {
    [_recordedEvents removeAllObjects];
    _persistentAutoStart = NO;
    [[NSFileManager defaultManager] removeItemAtPath:[self filePath] error:nil];
}

- (void)showTouchIndicatorAtPoint:(CGPoint)point {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *targetScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                targetScene = (UIWindowScene *)scene;
                break;
            }
        }
        
        UIWindow *indicatorWin = nil;
        if (targetScene) {
            indicatorWin = [[UIWindow alloc] initWithWindowScene:targetScene];
        } else {
            indicatorWin = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        
        indicatorWin.frame = [UIScreen mainScreen].bounds;
        indicatorWin.windowLevel = UIWindowLevelStatusBar + 99998;
        indicatorWin.userInteractionEnabled = NO;
        
        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        vc.view.userInteractionEnabled = NO;
        indicatorWin.rootViewController = vc;
        
        CGFloat size = 35.0;
        UIView *circle = [[UIView alloc] initWithFrame:CGRectMake(point.x - (size/2), point.y - (size/2), size, size)];
        circle.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.65];
        circle.layer.cornerRadius = size / 2;
        circle.layer.borderWidth = 1.5;
        circle.layer.borderColor = [UIColor whiteColor].CGColor;
        
        [vc.view addSubview:circle];
        indicatorWin.hidden = NO;
        [indicatorWin makeKeyAndVisible];
        
        [UIView animateWithDuration:0.35 animations:^{
            circle.transform = CGAffineTransformMakeScale(1.4, 1.4);
            circle.alpha = 0.0;
        } completion:^(BOOL finished) {
            indicatorWin.hidden = YES;
        }];
    });
}

- (void)showToast:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.toastWindow) {
            UIWindowScene *targetScene = nil;
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                    targetScene = (UIWindowScene *)scene;
                    break;
                }
            }
            
            if (targetScene) {
                self.toastWindow = [[UIWindow alloc] initWithWindowScene:targetScene];
            } else {
                self.toastWindow = [[UIWindow alloc] initWithFrame:CGRectMake(50, 200, 314, 50)];
            }
            
            self.toastWindow.windowLevel = UIWindowLevelStatusBar + 100000;
            self.toastWindow.userInteractionEnabled = NO;
            
            UIViewController *toastVC = [[UIViewController alloc] init];
            toastVC.view.backgroundColor = [UIColor clearColor];
            toastVC.view.userInteractionEnabled = NO;
            self.toastWindow.rootViewController = toastVC;
            
            self.toastLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 100, 294, 45)];
            self.toastLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
            self.toastLabel.textColor = [UIColor cyanColor];
            self.toastLabel.font = [UIFont boldSystemFontOfSize:13];
            self.toastLabel.textAlignment = NSTextAlignmentCenter;
            self.toastLabel.layer.cornerRadius = 10;
            self.toastLabel.clipsToBounds = YES;
            self.toastLabel.layer.borderWidth = 1.0;
            self.toastLabel.layer.borderColor = [UIColor cyanColor].CGColor;
            
            [toastVC.view addSubview:self.toastLabel];
        }
        
        self.toastLabel.text = message;
        self.toastWindow.hidden = NO;
        [self.toastWindow makeKeyAndVisible];
        
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideToast) object:nil];
        [self performSelector:@selector(hideToast) withObject:nil afterDelay:2.0];
    });
}

- (void)hideToast {
    if (self.toastWindow) {
        self.toastWindow.hidden = YES;
    }
}

- (void)ensureUIVisible {
    if (!self.floatingWindow) {
        [self setupUI];
    } else {
        self.floatingWindow.hidden = NO;
        [self.floatingWindow makeKeyAndVisible];
    }
}

- (void)setupUI {
    if (self.floatingWindow) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *targetScene = nil;
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                targetScene = (UIWindowScene *)scene;
                screenBounds = ((UIWindowScene *)scene).coordinateSpace.bounds;
                break;
            }
        }
        
        CGFloat windowWidth = 220;
        CGFloat windowHeight = 300;
        CGFloat originX = screenBounds.size.width - windowWidth - 20;
        CGFloat originY = screenBounds.size.height - windowHeight - 80;
        
        if (targetScene) {
            self.floatingWindow = [[UIWindow alloc] initWithWindowScene:targetScene];
        } else {
            self.floatingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(originX, originY, windowWidth, windowHeight)];
        }
        
        self.floatingWindow.frame = CGRectMake(originX, originY, windowWidth, windowHeight);
        self.floatingWindow.windowLevel = UIWindowLevelStatusBar + 99999;
        self.floatingWindow.userInteractionEnabled = YES;
        
        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        vc.view.userInteractionEnabled = YES;
        self.floatingWindow.rootViewController = vc;
        
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, windowWidth, windowHeight)];
        container.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.92];
        container.layer.cornerRadius = 14;
        container.layer.borderWidth = 1.5;
        container.layer.borderColor = [UIColor cyanColor].CGColor;
        container.clipsToBounds = YES;
        container.userInteractionEnabled = YES;
        
        UIView *dragBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, windowWidth, 30)];
        dragBar.backgroundColor = [[UIColor darkGrayColor] colorWithAlphaComponent:0.6];
        dragBar.userInteractionEnabled = YES;
        
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, windowWidth - 20, 30)];
        titleLabel.text = @"≡ اسحب هنا لتحريك النافذة";
        titleLabel.textColor = [UIColor lightGrayColor];
        titleLabel.font = [UIFont systemFontOfSize:11];
        titleLabel.textAlignment = NSTextAlignmentCenter;
        [dragBar addSubview:titleLabel];
        
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [dragBar addGestureRecognizer:pan];
        
        self->_recordButton = [self createButtonWithTitle:@"🔴 تسجيل" action:@selector(recordTapped:) color:[UIColor systemRedColor]];
        self->_recordButton.frame = CGRectMake(10, 40, windowWidth - 20, 35);
        
        self->_stopButton = [self createButtonWithTitle:@"⏹️ إيقاف" action:@selector(stopTapped:) color:[UIColor systemOrangeColor]];
        self->_stopButton.frame = CGRectMake(10, 80, windowWidth - 20, 35);
        
        self->_playButton = [self createButtonWithTitle:@"▶️ تشغيل وتكرار" action:@selector(playTapped:) color:[UIColor systemGreenColor]];
        self->_playButton.frame = CGRectMake(10, 120, windowWidth - 20, 35);
        
        UIButton *saveBtn = [self createButtonWithTitle:@"💾 حفظ" action:@selector(saveTapped:) color:[UIColor systemBlueColor]];
        saveBtn.frame = CGRectMake(10, 160, 95, 30);
        
        UIButton *clearBtn = [self createButtonWithTitle:@"🗑️ حذف" action:@selector(clearTapped:) color:[UIColor systemGrayColor]];
        clearBtn.frame = CGRectMake(115, 160, 95, 30);
        
        UILabel *autoLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 200, 140, 30)];
        autoLabel.text = @"تشغيل تلقائي دائم:";
        autoLabel.textColor = [UIColor whiteColor];
        autoLabel.font = [UIFont systemFontOfSize:12];
        
        self->_autoStartSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(windowWidth - 70, 200, 50, 30)];
        [self->_autoStartSwitch setOn:self.persistentAutoStart];
        [self->_autoStartSwitch addTarget:self action:@selector(autoSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        
        UIButton *hideBtn = [self createButtonWithTitle:@"إخفاء الواجهة" action:@selector(hideTapped:) color:[UIColor darkGrayColor]];
        hideBtn.frame = CGRectMake(10, 245, windowWidth - 20, 35);
        hideBtn.titleLabel.font = [UIFont systemFontOfSize:11];
        
        [container addSubview:dragBar];
        [container addSubview:self->_recordButton];
        [container addSubview:self->_stopButton];
        [container addSubview:self->_playButton];
        [container addSubview:saveBtn];
        [container addSubview:clearBtn];
        [container addSubview:autoLabel];
        [container addSubview:self->_autoStartSwitch];
        [container addSubview:hideBtn];
        
        [vc.view addSubview:container];
        [self.floatingWindow makeKeyAndVisible];
        
        if (self.persistentAutoStart && self.recordedEvents.count > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self startPlaybackLoop];
            });
        }
    });
}

- (UIButton *)createButtonWithTitle:(NSString *)title action:(SEL)action color:(UIColor *)color {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 6;
    btn.userInteractionEnabled = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.floatingWindow];
    CGRect center = self.floatingWindow.frame;
    center.origin.x += translation.x;
    center.origin.y += translation.y;
    self.floatingWindow.frame = center;
    [pan setTranslation:CGPointZero inView:self.floatingWindow];
}

- (void)recordTapped:(id)sender { 
    [self startRecording];
    [self showToast:@"🔴 الحالة: بدأ تسجيل اللمسات..."];
}

- (void)stopTapped:(id)sender { 
    [self stopAll];
    [self showToast:@"⏹️ الحالة: تم إيقاف التسجيل والتشغيل"];
}

- (void)playTapped:(id)sender { 
    if (self.recordedEvents.count == 0) {
        [self showToast:@"⚠️ تنبيه: لا توجد حركات مسجلة للتشغيل!"];
        return;
    }
    [self startPlaybackLoop];
    [self showToast:@"▶️ الحالة: بدأ التشغيل وتكرار اللمسات"];
}

- (void)saveTapped:(id)sender { 
    [self saveMacroAndSettings];
    [self showToast:@"💾 الحالة: تم حفظ الحركات بنجاح"];
}

- (void)clearTapped:(id)sender { 
    [self clearMacro];
    [self showToast:@"🗑️ الحالة: تم مسح وحذف التسجيلات"];
}

- (void)autoSwitchChanged:(UISwitch *)sender {
    _persistentAutoStart = sender.isOn;
    [self saveMacroAndSettings];
    if (_persistentAutoStart) {
        [self showToast:@"⚙️ تشغيل تلقائي دائم: [مفعل]"];
    } else {
        [self showToast:@"⚙️ تشغيل تلقائي دائم: [معطل]"];
    }
}

- (void)hideTapped:(id)sender { 
    self.floatingWindow.hidden = YES;
    [self showToast:@"👁️ تم إخفاء الواجهة"];
}

- (void)startRecording {
    [self stopAll];
    _isRecording = YES;
    [_recordedEvents removeAllObjects];
    _lastEventTimestamp = CACurrentMediaTime();
}

- (void)stopAll {
    _isRecording = NO;
    _isPlaying = NO;
}

- (void)recordTouchAtPoint:(CGPoint)point phase:(NSInteger)phase {
    if (!_isRecording) return;
    
    if (phase == 0) {
        [self showTouchIndicatorAtPoint:point];
    }
    
    NSTimeInterval now = CACurrentMediaTime();
    NSTimeInterval delta = now - _lastEventTimestamp;
    _lastEventTimestamp = now;
    
    RecordedEvent *ev = [[RecordedEvent alloc] init];
    ev.point = point;
    ev.phase = phase;
    ev.timeOffset = delta;
    
    [_recordedEvents addObject:ev];
}

// ==========================================
// 4. محرك حقن اللمس المتطور بنظام iGameGod
// ==========================================
- (void)injectTouchAtPoint:(CGPoint)point phase:(UITouchPhase)phase {
    UIWindow *keyWindow = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow && ![w isEqual:self.floatingWindow]) {
            keyWindow = w;
            break;
        }
    }
    if (!keyWindow) keyWindow = [[UIApplication sharedApplication].windows firstObject];
    if (!keyWindow) return;

    if (phase == UITouchPhaseBegan) {
        [self showTouchIndicatorAtPoint:point];
    }

    UIView *hitView = [keyWindow hitTest:point withEvent:nil];
    if (!hitView) hitView = keyWindow;

    UITouch *touch = [[UITouch alloc] init];
    [touch setWindow:keyWindow];
    [touch setView:hitView];
    [touch setTapCount:1];
    [touch setIsTap:YES];
    [touch setTimestamp:CACurrentMediaTime()];
    [touch setLocationInWindow:point];
    [touch setPhase:phase];

    UIEvent *event = [[UIApplication sharedApplication] _touchesEvent];
    if (event) {
        [event _clearTouches];
        [event _addTouch:touch forFocusedForcedPanGestureRecognizer:nil];
        [[UIApplication sharedApplication] sendEvent:event];
    }
}

- (void)startPlaybackLoop {
    if (_isPlaying || _recordedEvents.count == 0) return;
    _isPlaying = YES;
    
    dispatch_async(_macroQueue, ^{
        while (self.isPlaying) {
            for (RecordedEvent *ev in self.recordedEvents) {
                if (!self.isPlaying) break;
                
                NSTimeInterval remaining = ev.timeOffset;
                while (remaining > 0 && self.isPlaying) {
                    NSTimeInterval slice = (remaining > 0.02) ? 0.02 : remaining;
                    usleep((useconds_t)(slice * 1000000.0));
                    remaining -= slice;
                }
                
                if (!self.isPlaying) break;
                
                UITouchPhase touchPhase = UITouchPhaseMoved;
                if (ev.phase == 0) touchPhase = UITouchPhaseBegan;
                else if (ev.phase == 1) touchPhase = UITouchPhaseMoved;
                else if (ev.phase == 2) touchPhase = UITouchPhaseEnded;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self injectTouchAtPoint:ev.point phase:touchPhase];
                });
            }
            usleep(20000);
        }
    });
}

@end

// ==========================================
// 5. الخطافات (Hooks)
// ==========================================
%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    UIWindow *floatingWin = [MacroManager sharedInstance].floatingWindow;
    if (floatingWin && !floatingWin.hidden) {
        for (UITouch *touch in event.allTouches) {
            if ([touch.window isEqual:floatingWin]) {
                %orig;
                return;
            }
        }
    }
    
    %orig;
    if (event.type == UIEventTypeTouches) {
        MacroManager *manager = [MacroManager sharedInstance];
        if (manager.isRecording) {
            UITouch *touch = [[event.allTouches allObjects] firstObject];
            if (touch && ![[touch window] isEqual:floatingWin]) {
                CGPoint pt = [touch locationInView:self];
                NSInteger phase = 1;
                if (touch.phase == UITouchPhaseBegan) phase = 0;
                else if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) phase = 2;
                
                [manager recordTouchAtPoint:pt phase:phase];
            }
        }
    }
}
%end

%hook UIApplication
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL orig = %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[MacroManager sharedInstance] setupUI];
    });
    return orig;
}
%end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[MacroManager sharedInstance] ensureUIVisible];
}
%end
