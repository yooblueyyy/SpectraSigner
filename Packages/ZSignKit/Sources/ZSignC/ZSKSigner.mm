#import "ZSKSigner.h"

#include "common.h"
#include "openssl.h"
#include "bundle.h"

#include <mutex>

NSErrorDomain const ZSKErrorDomain = @"ZSignKit";

@implementation ZSKSignOptions

- (instancetype)init {
	if ((self = [super init])) {
		_appFolder = @"";
		_dylibPaths = @[];
		_removeDylibNames = @[];
	}
	return self;
}

@end

// zsign keeps its logger and OpenSSL state in globals, so only one job runs at a time.
static std::mutex gSignLock;
static void (^gLogHandler)(NSString *) = nil;
static NSMutableString *gErrorLines = nil;

static void ZSKLogHook(const char *szLog, int nColor) {
	if (szLog == NULL) {
		return;
	}
	NSString *line = [[NSString stringWithUTF8String:szLog] ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (line.length == 0) {
		return;
	}
	if (nColor == 12) { // zsign prints errors in red
		[gErrorLines appendFormat:@"%@\n", line];
	}
	if (gLogHandler) {
		gLogHandler(line);
	}
}

static string ZSKString(NSString *s) {
	return s.length ? string(s.UTF8String) : string();
}

static NSError *ZSKError(NSString *fallback) {
	NSString *message = [gErrorLines stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (message.length == 0) {
		message = fallback;
	}
	message = [message stringByReplacingOccurrencesOfString:@">>> " withString:@""];
	return [NSError errorWithDomain:ZSKErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation ZSKSigner

+ (BOOL)signWithOptions:(ZSKSignOptions *)o
             logHandler:(void (^)(NSString *))logHandler
                  error:(NSError **)error {
	std::lock_guard<std::mutex> guard(gSignLock);
	gLogHandler = logHandler;
	gErrorLines = [NSMutableString string];
	ZLog::g_pfnHook = ZSKLogHook;
	ZLog::SetLogLever(ZLog::E_INFO);

	BOOL ok = NO;
	@autoreleasepool {
		ZSignAsset asset;
		if (!asset.Init(string(), ZSKString(o.p12Path), ZSKString(o.provisionPath), ZSKString(o.entitlementsPath),
						ZSKString(o.p12Password), o.adhoc, false, false)) {
			if (error) *error = ZSKError(@"Couldn't load the certificate. Check the password and provisioning profile.");
		} else {
			vector<string> dylibs;
			for (NSString *path in o.dylibPaths) dylibs.push_back(ZSKString(path));
			vector<string> removeDylibs;
			for (NSString *name in o.removeDylibNames) removeDylibs.push_back(ZSKString(name));

			ZBundle bundle;
			bundle.m_bEnableDocuments = o.enableFileSharing;
			bundle.m_strMinVersion = ZSKString(o.minimumOSVersion);
			bundle.m_strIconFile = ZSKString(o.iconPath);
			bundle.m_bRemoveExtensions = o.removeExtensions;
			bundle.m_bRemoveWatchApp = o.removeWatchApp;
			bundle.m_bRemoveUISupportedDevices = o.removeSupportedDevices;
			bundle.m_bInjectExtensions = false;

			ok = bundle.SignFolder(&asset, ZSKString(o.appFolder), ZSKString(o.bundleIdentifier), ZSKString(o.version),
								   ZSKString(o.displayName), dylibs, removeDylibs,
								   true /* force */, o.weakInject, false /* cache */, o.removeProvision);
			if (!ok && error) *error = ZSKError(@"Signing failed.");
		}
	}

	ZLog::g_pfnHook = NULL;
	gLogHandler = nil;
	gErrorLines = nil;
	return ok;
}

+ (BOOL)validateP12AtPath:(NSString *)p12Path
                 password:(NSString *)password
            provisionPath:(NSString *)provisionPath
                    error:(NSError **)error {
	std::lock_guard<std::mutex> guard(gSignLock);
	gErrorLines = [NSMutableString string];
	ZLog::g_pfnHook = ZSKLogHook;

	ZSignAsset asset;
	BOOL ok = asset.Init(string(), ZSKString(p12Path), ZSKString(provisionPath), string(), ZSKString(password), false, false, false);
	if (!ok && error) {
		*error = ZSKError(@"The password is wrong or the certificate doesn't match the provisioning profile.");
	}

	ZLog::g_pfnHook = NULL;
	gErrorLines = nil;
	return ok;
}

@end
