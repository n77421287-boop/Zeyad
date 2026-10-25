#import <UIKit/UIKit.h>
#import <mach/mach_time.h>
#import <time.h>
#import <sys/time.h>
#import <dlfcn.h>
#import <substrate.h>
#import <QuartzCore/QuartzCore.h>

// تثبيت معامل السرعة على 90,000 ضعف تلقائياً ودائماً
static const double g_speedMultiplier = 90000.0;

// --- Anchor State for Monotonic Scaling ---
static uint64_t s_machBaseAnchor = 0;
static uint64_t s_machScaledAnchor = 0;

static struct timespec s_monotonicBaseAnchor;
static struct timespec s_monotonicScaledAnchor;

// تهيئة النقاط المرجعية عند التحميل
__attribute__((constructor)) static void initSpeedEngineAnchors() {
    s_machBaseAnchor = mach_absolute_time();
    s_machScaledAnchor = s_machBaseAnchor;
    
    clock_gettime(CLOCK_MONOTONIC, &s_monotonicBaseAnchor);
    s_monotonicScaledAnchor = s_monotonicBaseAnchor;
}

// ==========================================
// 1. LOW-LEVEL SYSTEM & KERNEL CLOCKS (MSHookFunction)
// ==========================================

static uint64_t (*orig_mach_absolute_time)(void);
uint64_t hooked_mach_absolute_time(void) {
    uint64_t currentRaw = orig_mach_absolute_time();
    uint64_t rawDelta = currentRaw - s_machBaseAnchor;
    uint64_t scaledDelta = (uint64_t)((double)rawDelta * g_speedMultiplier);
    return s_machScaledAnchor + scaledDelta;
}

static int (*orig_clock_gettime)(clockid_t clk_id, struct timespec *tp);
int hooked_clock_gettime(clockid_t clk_id, struct timespec *tp) {
    int result = orig_clock_gettime(clk_id, tp);
    if (result != 0) return result;
    
    if (clk_id == CLOCK_MONOTONIC || clk_id == CLOCK_UPTIME_RAW) {
        long long diffSec = tp->tv_sec - s_monotonicBaseAnchor.tv_sec;
        long long diffNsec = tp->tv_nsec - s_monotonicBaseAnchor.tv_nsec;
        double totalNsec = (double)(diffSec * 1000000000LL + diffNsec);
        double scaledNsec = totalNsec * g_speedMultiplier;
        
        tp->tv_sec = s_monotonicScaledAnchor.tv_sec + (time_t)(scaledNsec / 1000000000.0);
        tp->tv_nsec = s_monotonicScaledAnchor.tv_nsec + (long)((long long)scaledNsec % 1000000000LL);
        if (tp->tv_nsec >= 1000000000L) {
            tp->tv_sec += 1;
            tp->tv_nsec -= 1000000000L;
        }
    }
    return result;
}

static int (*orig_gettimeofday)(struct timeval *restrict tp, void *restrict tzp);
int hooked_gettimeofday(struct timeval *restrict tp, void *restrict tzp) {
    int result = orig_gettimeofday(tp, tzp);
    if (result != 0) return result;
    
    static struct timeval tvBase;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ tvBase = *tp; });
    
    double elapsed = (tp->tv_sec - tvBase.tv_sec) + (tp->tv_usec - tvBase.tv_usec) / 1000000.0;
    double scaledElapsed = elapsed * g_speedMultiplier;
    
    tp->tv_sec = tvBase.tv_sec + (time_t)scaledElapsed;
    tp->tv_usec = tvBase.tv_usec + (suseconds_t)((scaledElapsed - (time_t)scaledElapsed) * 1000000.0);
    return result;
}

static double (*orig_CACurrentMediaTime)(void);
double hooked_CACurrentMediaTime(void) {
    double original = orig_CACurrentMediaTime ? orig_CACurrentMediaTime() : 0;
    static double baseReal = 0;
    static double baseScaled = 0;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        baseReal = original;
        baseScaled = original;
    });
    return baseScaled + (original - baseReal) * g_speedMultiplier;
}

// ==========================================
// 2. FOUNDATION APIs (NSDate)
// ==========================================

%hook NSDate
+ (instancetype)date {
    NSDate *origDate = %orig;
    NSTimeInterval ti = [origDate timeIntervalSinceReferenceDate];
    return [NSDate dateWithTimeIntervalSinceReferenceDate:ti * g_speedMultiplier];
}
- (NSTimeInterval)timeIntervalSinceReferenceDate {
    return %orig * g_speedMultiplier;
}
%end

// ==========================================
// 3. APPLICATION LOOPS & UI TIMERS
// ==========================================

%hook CADisplayLink
- (void)setDuration:(CFTimeInterval)duration {
    %orig(duration / g_speedMultiplier);
}
- (CFTimeInterval)duration {
    return %orig / g_speedMultiplier;
}
- (void)setFrameInterval:(NSInteger)frameInterval {
    %orig(MAX(1, (NSInteger)(frameInterval / g_speedMultiplier)));
}
%end

%hook NSTimer
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)interval target:(id)target selector:(SEL)aSelector userInfo:(id)userInfo repeats:(BOOL)repeats {
    return %orig(interval / g_speedMultiplier, target, aSelector, userInfo, repeats);
}
- (void)setFireDate:(NSDate *)fireDate {
    if (fireDate) {
        NSTimeInterval remaining = [fireDate timeIntervalSinceNow] / g_speedMultiplier;
        fireDate = [NSDate dateWithTimeIntervalSinceNow:remaining];
    }
    %orig(fireDate);
}
%end

// ==========================================
// 4. GAME ENGINE HOOKS (SpriteKit)
// ==========================================

%hook SKScene
- (void)update:(NSTimeInterval)currentTime {
    static NSTimeInterval lastTime = 0;
    if (lastTime == 0) lastTime = currentTime;
    NSTimeInterval dt = (currentTime - lastTime) * g_speedMultiplier;
    lastTime = currentTime;
    %orig(currentTime);
}
%end

// استخدام MSHookFunction المعيارية بدلاً من fishhook
%ctor {
    MSHookFunction((void *)mach_absolute_time, (void *)hooked_mach_absolute_time, (void **)&orig_mach_absolute_time);
    MSHookFunction((void *)clock_gettime, (void *)hooked_clock_gettime, (void **)&orig_clock_gettime);
    MSHookFunction((void *)gettimeofday, (void *)hooked_gettimeofday, (void **)&orig_gettimeofday);
    MSHookFunction((void *)CACurrentMediaTime, (void *)hooked_CACurrentMediaTime, (void **)&orig_CACurrentMediaTime);
}
