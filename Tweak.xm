#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <mach/mach_time.h>

// ==========================================
// 1. تعريفات واجهات ومجموعات IOHIDEvent الخاصة
// ==========================================
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern "C" {
    IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
    void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);
    
    IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(
        CFAllocatorRef allocator,
        uint64_t timestamp,
        uint32_t fingerID,
        uint32_t phase,
        CGFloat x, CGFloat y, CGFloat z,
        CGFloat pressure, CGFloat twist,
        boolean_t range, boolean_t touch,
        uint32_t flags
    );
}

typedef NS_ENUM(uint32_t, IOHIDDigitizerEventPhase) {
    kIOHIDDigitizerEventPhaseUndefined = 0,
    kIOHIDDigitizerEventPhaseRanges    = 1,
    kIOHIDDigitizerEventPhaseTouch     = 2,
    kIOHIDDigitizerEventPhaseStationary= 4,
    kIOHIDDigitizerEventPhaseDown      = 5,
    kIOHIDDigitizerEventPhaseUp        = 6,
    kIOHIDDigitizerEventPhaseCancel    = 7
};

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
// 3. إدارة التسجيل والتشغيل والواجهة عبر الملفات
// ==========================================
@interface MacroManager : NSObject
@property (nonatomic, strong) UIWindow *floatingWindow;
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
@property (nonatomic, assign) IOHIDEventSystemClientRef hidClient;

+ (instancetype)sharedInstance;
- (void)setupUI;
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
        _macroQueue = dispatch_queue_create("com.macro.engine.queue", DISPATCH_QUEUE_SERIAL);
        _hidClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        
        // قراءة الإعدادات والتسجيل من الملفات حصرياً
        [self loadDataFromFile];
    }
    return self;
}

// مسار ملف الحفظ الموحد في مجلد المستندات
- (NSString *)filePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    return [documentsDirectory stringByAppendingPathComponent:@"automacro_config.plist"];
}

// حفظ الأحداث وحالة التشغيل التلقائي معاً في ملف واحد
- (void)saveMacroAndSettings {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    NSData *eventsData = [NSKeyedArchiver archivedDataWithRootObject:_recordedEvents];
    [dict setObject:eventsData forKey:@"events"];
    [dict setObject:@(_persistentAutoStart) forKey:@"autoStart"];
    
    [dict writeToFile:[self filePath] atomically:YES];
}

// تحميل البيانات والإعدادات من الملف
- (void)loadDataFromFile {
    NSString *path = [self filePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
        if (dict) {
            NSData *eventsData = [dict objectForKey:@"events"];
            if (eventsData) {
                NSArray *loaded = [NSKeyedUnarchiver unarchiveObjectWithData:eventsData];
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

// بناء واجهة المستخدم العائمة
- (void)setupUI {
    if (self.floatingWindow) return;
    
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    
    if (scene) {
        self.floatingWindow = [[UIWindow alloc] initWithWindowScene:scene];
    } else {
        self.floatingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(20, 100, 220, 270)];
    }
    
    self.floatingWindow.frame = CGRectMake(20, 100, 220, 270);
    self.floatingWindow.windowLevel = UIWindowLevelAlert + 9999;
    self.floatingWindow.hidden = NO;
    
    UIView *container = [[UIView alloc] initWithFrame:self.floatingWindow.bounds];
    container.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.75];
    container.layer.cornerRadius = 14;
    container.layer.borderWidth = 1.5;
    container.layer.borderColor = [UIColor cyanColor].CGColor;
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [container addGestureRecognizer:pan];
    
    _recordButton = [self createButtonWithTitle:@"🔴 تسجيل" action:@selector(recordTapped:) color:[UIColor systemRedColor]];
    _recordButton.frame = CGRectMake(10, 10, 200, 35);
    
    _stopButton = [self createButtonWithTitle:@"⏹️ إيقاف" action:@selector(stopTapped:) color:[UIColor systemOrangeColor]];
    _stopButton.frame = CGRectMake(10, 50, 200, 35);
    
    _playButton = [self createButtonWithTitle:@"▶️ تشغيل وتكرار" action:@selector(playTapped:) color:[UIColor systemGreenColor]];
    _playButton.frame = CGRectMake(10, 90, 200, 35);
    
    UIButton *saveBtn = [self createButtonWithTitle:@"💾 حفظ الحركات" action:@selector(saveTapped:) color:[UIColor systemBlueColor]];
    saveBtn.frame = CGRectMake(10, 130, 95, 30);
    
    UIButton *clearBtn = [self createButtonWithTitle:@"🗑️ حذف" action:@selector(clearTapped:) color:[UIColor systemGrayColor]];
    clearBtn.frame = CGRectMake(115, 130, 95, 30);
    
    UILabel *autoLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 170, 140, 30)];
    autoLabel.text = @"تشغيل تلقائي دائم:";
    autoLabel.textColor = [UIColor whiteColor];
    autoLabel.font = [UIFont systemFontOfSize:12];
    
    _autoStartSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(160, 170, 50, 30)];
    [_autoStartSwitch setOn:_persistentAutoStart];
    [_autoStartSwitch addTarget:self action:@selector(autoSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    
    UIButton *hideBtn = [self createButtonWithTitle:@"إخفاء الواجهة" action:@selector(hideTapped:) color:[UIColor darkGrayColor]];
    hideBtn.frame = CGRectMake(10, 215, 200, 30);
    hideBtn.titleLabel.font = [UIFont systemFontOfSize:10];
    
    [container addSubview:_recordButton];
    [container addSubview:_stopButton];
    [container addSubview:_playButton];
    [container addSubview:saveBtn];
    [container addSubview:clearBtn];
    [container addSubview:autoLabel];
    [container addSubview:_autoStartSwitch];
    [container addSubview:hideBtn];
    
    [self.floatingWindow addSubview:container];
    
    // التشغيل التلقائي عند الإقلاع اعتماداً على ما تم قراءته من الملف
    if (_persistentAutoStart && _recordedEvents.count > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startPlaybackLoop];
        });
    }
}

- (UIButton *)createButtonWithTitle:(NSString *)title action:(SEL)action color:(UIColor *)color {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 6;
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

#pragma mark - إجراءات الأزرار
- (void)recordTapped:(id)sender { [self startRecording]; }
- (void)stopTapped:(id)sender { [self stopAll]; }
- (void)playTapped:(id)sender { [self startPlaybackLoop]; }
- (void)saveTapped:(id)sender { [self saveMacroAndSettings]; }
- (void)clearTapped:(id)sender { [self clearMacro]; }

- (void)autoSwitchChanged:(UISwitch *)sender {
    _persistentAutoStart = sender.isOn;
    // حفظ التغيير فوراً في الملف
    [self saveMacroAndSettings];
}

- (void)hideTapped:(id)sender { self.floatingWindow.hidden = YES; }

- (void)startRecording {
    [self stopAll];
    _isRecording = YES;
    [_recordedEvents removeAllObjects];
    _lastEventTimestamp = CACurrentMediaTime();
}

- (void)stopAll {
    _isRecording = NO;
    _isPlaying = false;
}

- (void)recordTouchAtPoint:(CGPoint)point phase:(NSInteger)phase {
    if (!_isRecording) return;
    
    NSTimeInterval now = CACurrentMediaTime();
    NSTimeInterval delta = now - _lastEventTimestamp;
    _lastEventTimestamp = now;
    
    RecordedEvent *ev = [[RecordedEvent alloc] init];
    ev.point = point;
    ev.phase = phase;
    ev.timeOffset = delta;
    
    [_recordedEvents addObject:ev];
}

#pragma mark - محاكاة اللمس
- (void)injectTouchAtPoint:(CGPoint)point phase:(IOHIDDigitizerEventPhase)phase {
    if (!_hidClient) return;
    
    uint64_t machTime = mach_absolute_time();
    IOHIDEventRef event = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, machTime, 1, phase,
        point.x, point.y, 0, 1.0, 0, true, true, 0
    );
    
    if (event) {
        IOHIDEventSystemClientDispatchEvent(_hidClient, event);
        CFRelease(event);
    }
}

- (void)startPlaybackLoop {
    if (_isPlaying || _recordedEvents.count == 0) return;
    _isPlaying = YES;
    
    dispatch_async(_macroQueue, ^{
        while (self.isPlaying) {
            for (RecordedEvent *ev in self.recordedEvents) {
                if (!self.isPlaying) break;
                
                if (ev.timeOffset > 0 && ev.timeOffset < 5.0) {
                    usleep((useconds_t)(ev.timeOffset * 1000000.0));
                }
                
                IOHIDDigitizerEventPhase hidPhase = kIOHIDDigitizerEventPhaseTouch;
                if (ev.phase == 0) hidPhase = kIOHIDDigitizerEventPhaseDown;
                else if (ev.phase == 1) hidPhase = kIOHIDDigitizerEventPhaseTouch;
                else if (ev.phase == 2) hidPhase = kIOHIDDigitizerEventPhaseUp;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self injectTouchAtPoint:ev.point phase:hidPhase];
                });
            }
            usleep(50000);
        }
    });
}

@end

// ==========================================
// 4. الخطافات (Hooks)
// ==========================================
%hook UIWindow
- (void)sendEvent:(UIEvent *)event {
    %orig;
    if (event.type == UIEventTypeTouches) {
        MacroManager *manager = [MacroManager sharedInstance];
        if (manager.isRecording) {
            UITouch *touch = [[event.allTouches allObjects] firstObject];
            if (touch) {
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
