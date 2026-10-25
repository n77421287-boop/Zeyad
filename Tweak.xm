#import <Foundation/Foundation.h>

// دالة لتوليد عنوان IP عشوائي ضمن النطاق المطلوب: 83.82.x.x
static NSString *generateRandomIP() {
    int thirdOctet = arc4random_uniform(256); // 0 إلى 255
    int fourthOctet = arc4random_uniform(256); // 0 إلى 255
    return [NSString stringWithFormat:@"83.82.%d.%d", thirdOctet, fourthOctet];
}

// دالة مركزية لاستلام الطلب، استنساخه، وتعديل الـ Headers الخاصة بالـ IP ديناميكياً
static NSURLRequest *modifyRequest(NSURLRequest *request) {
    if (!request) return nil;
    
    // تحويل الـ NSURLRequest إلى NSMutableURLRequest قابل للتعديل
    NSMutableURLRequest *mutableReq = [request mutableCopy];
    if (!mutableReq) return request;
    
    // توليد IP عشوائي جديد خاص بهذا الطلب فقط
    NSString *randomIP = generateRandomIP();
    
    // حقن وتعديل حقول الـ IP الوهمية بالكامل ومسح أي قيم قديمة
    [mutableReq setValue:randomIP forHTTPHeaderField:@"X-Forwarded-For"];
    [mutableReq setValue:randomIP forHTTPHeaderField:@"Client-IP"];
    [mutableReq setValue:randomIP forHTTPHeaderField:@"X-Real-IP"];
    [mutableReq setValue:randomIP forHTTPHeaderField:@"True-Client-IP"];
    [mutableReq setValue:randomIP forHTTPHeaderField:@"X-Cluster-Client-IP"];
    
    return [mutableReq copy];
}

%hook NSURLSession

// 1. مهام جلب البيانات (Data Tasks)
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    return %orig(modifyRequest(request));
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    return %orig(modifyRequest(request), completionHandler);
}

// 2. مهام رفع البيانات (Upload Tasks)
- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    return %orig(modifyRequest(request), bodyData);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    return %orig(modifyRequest(request), bodyData, completionHandler);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL {
    return %orig(modifyRequest(request), fileURL);
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    return %orig(modifyRequest(request), fileURL, completionHandler);
}

// 3. مهام تحميل الملفات (Download Tasks)
- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request {
    return %orig(modifyRequest(request));
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    return %orig(modifyRequest(request), completionHandler);
}

%end
