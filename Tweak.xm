// ═══════════════════════════════════════════════════════════════════════════
// GhostIdentity v3 — Zero Static Values
// Every value is generated dynamically at every request / every cycle
// ═══════════════════════════════════════════════════════════════════════════

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AdSupport/AdSupport.h>
#import <Security/Security.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <objc/runtime.h>
#import <objc/message.h>

#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <netdb.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <random>
#include <chrono>
#include <mutex>
#include <vector>
#include <string>
#include <algorithm>

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 1 — GhostEngine (Zero-Static-Value Random Generator)
// ═══════════════════════════════════════════════════════════════════════════

@interface GhostEngine : NSObject
+ (instancetype)shared;
- (NSString *)newUUID;
- (NSString *)newIDFA;
- (NSString *)newIDFV;
- (NSString *)newMAC;
- (NSString *)newSerial;
- (NSString *)newRandomIP;
- (NSString *)newRandomIPv6;
- (NSString *)newUserAgent;
- (NSString *)newSystemVersion;
- (NSString *)newDeviceName;
- (NSDictionary *)newHeaders;
- (NSTimeInterval)newRotationInterval;
@end

@implementation GhostEngine {
    std::mt19937_64 _rng;
    std::mutex _lock;
}

+ (instancetype)shared {
    static GhostEngine *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[GhostEngine alloc] init]; });
    return inst;
}

// ─── بذرة عشوائية من 5 مصادر مستقلة ─────────────────────────────────
- (uint64_t)gatherEntropy {
    uint64_t e1 = mach_absolute_time();
    uint64_t e2 = (uint64_t)[[NSDate date] timeIntervalSince1970];
    uint64_t e3 = (uint64_t)arc4random();
    uint64_t e4 = (uint64_t)arc4random();
    uint64_t e5 = (uint64_t)(uintptr_t)&_rng;
    uint64_t e6 = (uint64_t)getpid();
    uint64_t e7 = (uint64_t)clock();
    return e1 ^ (e2 << 13) ^ (e3 << 27) ^ (e4 << 41)
         ^ (e5 << 7)  ^ (e6 << 51) ^ (e7 << 19);
}

- (instancetype)init {
    if ((self = [super init])) {
        _rng.seed([self gatherEntropy]);
        // استهلاك أولي لتحسين التوزيع
        for (int i = 0; i < 32; i++) (void)_rng();
    }
    return self;
}

- (uint64_t)nextU64 {
    std::lock_guard<std::mutex> g(_lock);
    return _rng();
}

- (int)nextByte { return (int)([self nextU64] & 0xFF); }

- (NSUInteger)nextInRange:(NSUInteger)min max:(NSUInteger)max {
    if (max <= min) return min;
    return min + (NSUInteger)([self nextU64] % (max - min + 1));
}

// ─── UUID: إصدار عشوائي بين 1 و 6 لتنويع البصمة ─────────────────────
- (NSString *)newUUID {
    unsigned char b[16];
    uint64_t a = [self nextU64];
    uint64_t c = [self nextU64];
    memcpy(b, &a, 8);
    memcpy(b + 8, &c, 8);

    // إصدار عشوائي من {1, 4, 6}
    static const unsigned char versions[] = {1, 4, 6};
    unsigned char ver = versions[(size_t)([self nextU64] % 3)];
    b[6] = (b[6] & 0x0F) | (ver << 4);
    b[8] = (b[8] & 0x3F) | 0x80;

    // صيغة نصية عشوائية: أحرف كبيرة أو صغيرة
    BOOL upper = ([self nextU64] & 1) == 0;
    NSString *fmt = upper
        ? @"%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X"
        : @"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x";

    return [NSString stringWithFormat:fmt,
        b[0],b[1],b[2],b[3], b[4],b[5], b[6],b[7],
        b[8],b[9], b[10],b[11],b[12],b[13],b[14],b[15]];
}

- (NSString *)newIDFA { return [self newUUID]; }
- (NSString *)newIDFV { return [self newUUID]; }

// ─── MAC: OUI عشوائي + 3 بايت عشوائية + صيغة عشوائية ────────────────
- (NSString *)newMAC {
    unsigned char mac[6];
    for (int i = 0; i < 6; i++) mac[i] = (unsigned char)[self nextByte];
    mac[0] = (mac[0] & 0xFE) | 0x02;

    // 4 صيغ محتملة للمفاصل
    NSUInteger style = [self nextInRange:0 max:3];
    if (style == 0)
        return [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X",
                mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]];
    if (style == 1)
        return [NSString stringWithFormat:@"%02x-%02x-%02x-%02x-%02x-%02x",
                mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]];
    if (style == 2)
        return [NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X",
                mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]];
    return [NSString stringWithFormat:@"%02x.%02x.%02x.%02x.%02x.%02x",
            mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]];
}

// ─── Serial: طول عشوائي + مجموعة أحرف عشوائية البناء ────────────────
- (NSString *)newSerial {
    // طول عشوائي 8..16
    NSUInteger len = [self nextInRange:8 max:16];

    // نبني مجموعة أحرف ديناميكية (أحرف كبيرة + أرقام)
    static const char upperSet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    static const char digitSet[] = "0123456789";

    NSMutableString *s = [NSMutableString stringWithCapacity:len];
    for (NSUInteger i = 0; i < len; i++) {
        // 60% حرف، 40% رقم (نسبة عشوائية أيضاً)
        BOOL useLetter = ([self nextU64] % 100) < 60;
        if (useLetter) {
            NSUInteger idx = [self nextInRange:0 max:25];
            [s appendFormat:@"%c", upperSet[idx]];
        } else {
            NSUInteger idx = [self nextInRange:0 max:9];
            [s appendFormat:@"%c", digitSet[idx]];
        }
    }
    return s;
}

// ─── IPv4: عشوائي بالكامل مع استبعاد المحجوز ────────────────────────
- (NSString *)newRandomIP {
    int a, b, c, d;
    do {
        a = [self nextByte]; b = [self nextByte];
        c = [self nextByte]; d = [self nextByte];
    } while (
        a == 0 || a == 10 || a == 127 || a == 255 ||
        a == 172 || a == 192 || a == 224 || a == 100 ||
        a == 169 || a == 198 || a >= 224
    );
    return [NSString stringWithFormat:@"%d.%d.%d.%d", a, b, c, d];
}

// ─── IPv6: مطلوب في بعض الترويسات ───────────────────────────────────
- (NSString *)newRandomIPv6 {
    NSMutableString *s = [NSMutableString stringWithCapacity:40];
    for (int g = 0; g < 8; g++) {
        unsigned int v = (unsigned int)([self nextU64] & 0xFFFF);
        [s appendFormat:@"%x", v];
        if (g < 7) [s appendString:@":"];
    }
    return s;
}

// ─── User-Agent: بناء كامل ديناميكي ─────────────────────────────────
- (NSString *)newUserAgent {
    // إصدار iOS عشوائي 14..18 مع إصدار فرعي عشوائي
    NSUInteger major = [self nextInRange:14 max:18];
    NSUInteger minor = [self nextInRange:0 max:7];
    NSUInteger patch = [self nextInRange:0 max:3];

    // إصدار WebKit عشري عشوائي: 605.X.Y
    NSUInteger wkMajor = 605;
    NSUInteger wkMinor = [self nextInRange:1 max:9];
    NSUInteger wkPatch = [self nextInRange:0 max:99];

    // رقم build عشوائي: 15X### 
    NSUInteger buildLetter = [self nextInRange:0 max:25];
    NSUInteger buildNum = [self nextInRange:100 max:999];

    // نوع الجهاز: iPhone أو iPad
    BOOL isPad = ([self nextU64] & 1);
    NSString *deviceStr = isPad ? @"iPad" : @"iPhone";
    NSString *cpuStr = isPad ? @"CPU OS" : @"CPU iPhone OS";

    // إصدار Safari: 16..18
    NSUInteger safariMajor = [self nextInRange:16 max:18];
    NSUInteger safariMinor = [self nextInRange:0 max:9];
    NSUInteger safariPatch = [self nextInRange:0 max:99];

    return [NSString stringWithFormat:
        @"Mozilla/5.0 (%@; %@ %lu_%lu_%lu like Mac OS X) "
         "AppleWebKit/%lu.%lu.%lu (KHTML, like Gecko) "
         "Version/%lu.%lu.%lu Mobile/%c%lu%c%c Safari/604.1",
        deviceStr, cpuStr,
        (unsigned long)major, (unsigned long)minor, (unsigned long)patch,
        (unsigned long)wkMajor, (unsigned long)wkMinor, (unsigned long)wkPatch,
        (unsigned long)safariMajor, (unsigned long)safariMinor, (unsigned long)safariPatch,
        (char)('A' + buildLetter),
        (unsigned long)buildNum,
        (char)('A' + ([self nextU64] % 26)),
        (char)('a' + ([self nextU64] % 26))];
}

// ─── System Version: كل الأرقام عشوائية ─────────────────────────────
- (NSString *)newSystemVersion {
    NSUInteger major = [self nextInRange:14 max:18];
    NSUInteger minor = [self nextInRange:0 max:7];
    NSUInteger patch = [self nextInRange:0 max:3];
    if (major >= 17) {
        // iOS 17+ عادةً بدون patch في الفئة
        return [NSString stringWithFormat:@"%lu.%lu",
                (unsigned long)major, (unsigned long)minor];
    }
    if (patch == 0) {
        return [NSString stringWithFormat:@"%lu.%lu",
                (unsigned long)major, (unsigned long)minor];
    }
    return [NSString stringWithFormat:@"%lu.%lu.%lu",
            (unsigned long)major, (unsigned long)minor, (unsigned long)patch];
}

// ─── Device Name: اسم عشوائي بالكامل ────────────────────────────────
- (NSString *)newDeviceName {
    // بادئة ديناميكية
    NSArray *prefixes = @[@"iPhone", @"iPad", @"iPod"];
    NSString *prefix = prefixes[[self nextInRange:0 max:prefixes.count - 1]];

    // لاحقة عشوائية طويلة
    NSUInteger suffixLen = [self nextInRange:6 max:14];
    static const char set[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSMutableString *suffix = [NSMutableString stringWithCapacity:suffixLen];
    for (NSUInteger i = 0; i < suffixLen; i++) {
        NSUInteger idx = [self nextInRange:0 max:35];
        [suffix appendFormat:@"%c", set[idx]];
    }

    // صيغة الاسم: بعض الأحيان مع مسافة، بعض الأحيان بدون، أحياناً مع شرطة
    NSUInteger style = [self nextInRange:0 max:2];
    if (style == 0) return [NSString stringWithFormat:@"%@-%@", prefix, suffix];
    if (style == 1) return [NSString stringWithFormat:@"%@ %@", prefix, suffix];
    return [NSString stringWithFormat:@"%@%@", prefix, suffix];
}

// ─── الترويسات: عدد ديناميكي، ترتيب عشوائي، أسماء بديلة ديناميكية ──
- (NSDictionary *)newHeaders {
    // مخزن الأسماء المحتملة للترويسات (بكل الصيغ المعروفة)
    NSArray *ipKeys = @[
        @"X-Forwarded-For", @"X-Real-IP", @"X-Client-IP",
        @"X-Originating-IP", @"X-Remote-IP", @"X-Remote-Addr",
        @"Client-IP", @"CF-Connecting-IP", @"True-Client-IP",
        @"X-Cluster-Client-IP", @"X-ProxyUser-Ip", @"Fastly-Client-IP",
        @"X-Forwarded", @"Forwarded-For", @"X-Original-IP",
        @"X-Originating-Address", @"X-Client-Address"
    ];

    // خلط عشوائي كامل
    NSMutableArray *shuffled = [ipKeys mutableCopy];
    for (NSUInteger i = shuffled.count; i > 1; i--) {
        NSUInteger j = [self nextInRange:0 max:i - 1];
        [shuffled exchangeObjectAtIndex:i - 1 withObjectAtIndex:j];
    }

    // اختيار عدد عشوائي من الترويسات (5..12)
    NSUInteger count = [self nextInRange:5 max:12];
    if (count > shuffled.count) count = shuffled.count;

    NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) {
        NSString *key = shuffled[i];

        // لكل ترويسة: إما IPv4 أو IPv6 (احتمال 20% لـ IPv6)
        BOOL useV6 = ([self nextU64] % 5) == 0;
        NSString *value = useV6 ? [self newRandomIPv6] : [self newRandomIP];

        // بعض الترويسات تحتاج صيغة خاصة
        if ([key isEqualToString:@"Forwarded"] || [key isEqualToString:@"Forwarded-For"]) {
            // الصيغة القياسية RFC 7239
            value = [NSString stringWithFormat:@"for=%@;proto=https;by=%@",
                     value, [self newRandomIP]];
        }

        headers[key] = value;
    }

    // إضافة User-Agent ديناميكي (بصيغة عشوائية)
    headers[@"User-Agent"] = [self newUserAgent];

    return headers;
}

// ─── فاصل التدوير: عشوائي 5..45 ثانية ──────────────────────────────
- (NSTimeInterval)newRotationInterval {
    NSUInteger seconds = [self nextInRange:5 max:45];
    // إضافة أجزاء كسرية عشوائية
    double frac = ([self nextU64] % 1000) / 1000.0;
    return (NSTimeInterval)seconds + frac;
}

@end

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 2 — Device Identifier Hooks (Dynamic)
// ═══════════════════════════════════════════════════════════════════════════

%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    return [[NSUUID alloc] initWithUUIDString:[[GhostEngine shared] newIDFA]];
}
- (BOOL)isAdvertisingTrackingEnabled { return YES; }
%end

%hook UIDevice
- (NSUUID *)identifierForVendor {
    return [[NSUUID alloc] initWithUUIDString:[[GhostEngine shared] newIDFV]];
}
- (NSString *)name {
    return [[GhostEngine shared] newDeviceName];
}
- (NSString *)systemVersion {
    return [[GhostEngine shared] newSystemVersion];
}
- (NSString *)model {
    NSArray *models = @[@"iPhone", @"iPad"];
    NSUInteger idx = arc4random_uniform((uint32_t)models.count);
    return models[idx];
}
%end

%hook NSProcessInfo
- (NSUUID *)globallyUniqueString {
    return [[NSUUID alloc] initWithUUIDString:[[GhostEngine shared] newUUID]];
}
%end

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 3 — C Function Hooks
// ═══════════════════════════════════════════════════════════════════════════

// ─── getifaddrs ──────────────────────────────────────────────────────
static int (*orig_getifaddrs)(struct ifaddrs **);

static int hook_getifaddrs(struct ifaddrs **ifap) {
    int ret = orig_getifaddrs(ifap);
    if (ret != 0 || !ifap || !*ifap) return ret;

    struct ifaddrs *ifa = *ifap;
    while (ifa) {
        if (ifa->ifa_name &&
            (strcmp(ifa->ifa_name, "en0") == 0 ||
             strcmp(ifa->ifa_name, "en1") == 0) &&
            ifa->ifa_addr &&
            ifa->ifa_addr->sa_family == AF_LINK) {

            struct sockaddr_dl *sdl = (struct sockaddr_dl *)ifa->ifa_addr;
            NSString *mac = [[GhostEngine shared] newMAC];
            // استخراج البايتات من أي صيغة (نستخدم أول 6 بايت من الهيكس)
            NSString *clean = [[mac stringByReplacingOccurrencesOfString:@":" withString:@""]
                                  stringByReplacingOccurrencesOfString:@"-" withString:@""];
            clean = [clean stringByReplacingOccurrencesOfString:@"." withString:@""];
            if (clean.length >= 12) {
                for (int i = 0; i < 6; i++) {
                    NSString *pair = [clean substringWithRange:NSMakeRange(i*2, 2)];
                    unsigned int v = 0;
                    sscanf([pair UTF8String], "%x", &v);
                    LLADDR(sdl)[i] = (unsigned char)v;
                }
                sdl->sdl_alen = 6;
            }
        }
        ifa = ifa->ifa_next;
    }
    return ret;
}

// ─── sysctl ──────────────────────────────────────────────────────────
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);

static int hook_sysctl(int *name, u_int namelen,
                       void *oldp, size_t *oldlenp,
                       void *newp, size_t newlen) {
    int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);

    if (ret == 0 && oldp && namelen >= 6 &&
        name[0] == CTL_NET && name[1] == PF_ROUTE &&
        name[4] == NET_RT_IFLIST && name[5] == 0) {

        struct if_msghdr *ifm = (struct if_msghdr *)oldp;
        char *end = (char *)oldp + (oldlenp ? *oldlenp : 0);

        while ((char *)ifm < end && ifm->ifm_msglen > 0) {
            if (ifm->ifm_type == RTM_IFINFO) {
                struct sockaddr_dl *sdl = (struct sockaddr_dl *)(ifm + 1);
                if (sdl->sdl_family == AF_LINK && sdl->sdl_alen == 6) {
                    NSString *mac = [[GhostEngine shared] newMAC];
                    NSString *clean = [[mac stringByReplacingOccurrencesOfString:@":" withString:@""]
                                          stringByReplacingOccurrencesOfString:@"-" withString:@""];
                    clean = [clean stringByReplacingOccurrencesOfString:@"." withString:@""];
                    if (clean.length >= 12) {
                        char *addr = LLADDR(sdl);
                        for (int i = 0; i < 6; i++) {
                            NSString *pair = [clean substringWithRange:NSMakeRange(i*2, 2)];
                            unsigned int v = 0;
                            sscanf([pair UTF8String], "%x", &v);
                            addr[i] = (unsigned char)v;
                        }
                    }
                }
            }
            ifm = (struct if_msghdr *)((char *)ifm + ifm->ifm_msglen);
        }
    }
    return ret;
}

// ─── connect ─────────────────────────────────────────────────────────
static int (*orig_connect)(int, const struct sockaddr *, socklen_t);

static int hook_connect(int fd, const struct sockaddr *addr, socklen_t len) {
    if (!addr || addr->sa_family != AF,_INET) const {
        return orig_connect(fd, addr, len char);
    }
    return orig_connect(fd *, addr, len);
service}

// ─── getaddrinfo ─────────────────────────────────────────────────────
static int (*orig_getaddrinfo)(const char *, const char *,
                               const struct addrinfo *, struct addrinfo **);

static int hook_getaddrinfo(const char *node,
                            const struct addrinfo *hints,
                            struct addrinfo **res) {
    return orig_getaddrinfo(node, service, hints, res);
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 4 — HTTP Header Injection (Dynamic Order & Count)
// ═══════════════════════════════════════════════════════════════════════════

static void GhostInjectHeaders(NSMutableURLRequest *req) {
    if (!req) return;

    NSDictionary *h = [[GhostEngine shared] newHeaders];

    // خلط ترتيب المفاتيح (لدعم انطباع أن كل طلب مختلف حتى في الترتيب)
    NSArray *keys = [h allKeys];
    NSMutableArray *shuffled = [keys mutableCopy];
    for (NSUInteger i = shuffled.count; i > 1; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)i);
        [shuffled exchangeObjectAtIndex:i - 1 withObjectAtIndex:j];
    }

    for (NSString *k in shuffled) {
        // لا نستبدل User-Agent إذا عيّنه التطبيق بنفسه
        if ([k isEqualToString:@"User-Agent"] &&
            [req valueForHTTPHeaderField:@"User-Agent"] != nil) {
            continue;
        }
        [req setValue:h[k] forHTTPHeaderField:k];
    }
}

%hook __NSCFURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSMutableURLRequest *m = [request mutableCopy];
    GhostInjectHeaders(m);
    return %orig(m, completionHandler);
}
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSMutableURLRequest *m = [request mutableCopy];
    GhostInjectHeaders(m);
    return %orig(m);
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSMutableURLRequest *m = [NSMutableURLRequest requestWithURL:url];
    GhostInjectHeaders(m);
    return %orig(m, completionHandler);
}
%end

%hook NSURLConnection
+ (NSURLConnection *)connectionWithRequest:(NSURLRequest *)request
                                  delegate:(id)delegate {
    NSMutableURLRequest *m = [request mutableCopy];
    GhostInjectHeaders(m);
    return %orig(m, delegate);
}
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse **)response
                             error:(NSError **)error {
    NSMutableURLRequest *m = [request mutableCopy];
    GhostInjectHeaders(m);
    return %orig(m, response, error);
}
%end

// ─── CFNetwork Layer ─────────────────────────────────────────────────
typedef struct __CFHTTPMessage *CFHTTPMessageRef;
typedef struct __CFReadStream *CFReadStreamRef;

static CFReadStreamRef (*orig_CFReadStreamCreateForHTTPRequest)(
    CFAllocatorRef, CFHTTPMessageRef);

static CFReadStreamRef hook_CFReadStreamCreateForHTTPRequest(
    CFAllocatorRef alloc, CFHTTPMessageRef req) {
    if (req) {
        NSDictionary *h = [[GhostEngine shared] newHeaders];
        NSArray *keys = [h allKeys];
        NSMutableArray *shuffled = [keys mutableCopy];
        for (NSUInteger i = shuffled.count; i > 1; i--) {
            NSUInteger j = arc4random_uniform((uint32_t)i);
            [shuffled exchangeObjectAtIndex:i - 1 withObjectAtIndex:j];
        }
        for (NSString *k in shuffled) {
            CFHTTPMessageSetHeaderFieldValue(req,
                (__bridge CFStringRef)k,
                (__bridge CFStringRef)h[k]);
        }
    }
    return orig_CFReadStreamCreateForHTTPRequest(alloc, req);
}

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 5 — Periodic Rotation Timer
// ═══════════════════════════════════════════════════════════════════════════

@interface GhostRotationScheduler : NSObject
@property (nonatomic, strong) NSTimer *timer;
- (void)start;
- (void)scheduleNext;
@end

@implementation GhostRotationScheduler

+ (instancetype)shared {
    static GhostRotationScheduler *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[GhostRotationScheduler alloc] init]; });
    return inst;
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self scheduleNext];
    });
}

- (void)scheduleNext {
    NSTimeInterval interval = [[GhostEngine shared] newRotationInterval];
    NSLog(@"[GhostIdentity] next rotation in %.3f seconds", interval);

    self.timer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                  target:self
                                                selector:@selector(fire:)
                                                userInfo:nil
                                                 repeats:NO];
}

- (void)fire:(NSTimer *)t {
    // لا نحتاج فعل شيء — كل القيم تُولَّد عند الطلب.
    // هذا المؤقّت يجعل الفاصل الزمني عشوائياً باستمرار.
    [self scheduleNext];
}

@end

// ═══════════════════════════════════════════════════════════════════════════
// SECTION 6 — Constructor
// ═══════════════════════════════════════════════════════════════════════════

%ctor {
    @autoreleasepool {
        NSLog(@"[GhostIdentity] ─────────────────────────────");
        NSLog(@"[GhostIdentity] v3 booting (zero static values)...");

        (void)[GhostEngine shared];

        MSHookFunction((void *)getifaddrs,
                       (void *)hook_getifaddrs,
                       (void **)&orig_getifaddrs);
        NSLog(@"[GhostIdentity] ✓ getifaddrs hooked");

        MSHookFunction((void *)sysctl,
                       (void *)hook_sysctl,
                       (void **)&orig_sysctl);
        NSLog(@"[GhostIdentity] ✓ sysctl hooked");

        MSHookFunction((void *)connect,
                       (void *)hook_connect,
                       (void **)&orig_connect);
        NSLog(@"[GhostIdentity] ✓ connect hooked");

        MSHookFunction((void *)getaddrinfo,
                       (void *)hook_getaddrinfo,
                       (void **)&orig_getaddrinfo);
        NSLog(@"[GhostIdentity] ✓ getaddrinfo hooked");

        void *cf = dlopen("/System/Library/Frameworks/CFNetwork.framework/CFNetwork",
                          RTLD_LAZY);
        if (cf) {
            void *sym = dlsym(cf, "CFReadStreamCreateForHTTPRequest");
            if (sym) {
                MSHookFunction(sym,
                    (void *)hook_CFReadStreamCreateForHTTPRequest,
                    (void **)&orig_CFReadStreamCreateForHTTPRequest);
                NSLog(@"[GhostIdentity] ✓ CFNetwork hooked");
            }
        }

        // بدء المؤقّت العشوائي
        [[GhostRotationScheduler shared] start];

        NSLog(@"[GhostIdentity] Engine ready (all values dynamic) ✅");
        NSLog(@"[GhostIdentity] ─────────────────────────────");
    }
}
