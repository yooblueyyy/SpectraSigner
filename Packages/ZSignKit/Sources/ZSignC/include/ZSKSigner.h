#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Options describing a single signing job.
@interface ZSKSignOptions : NSObject

/// Folder containing `Payload/<Name>.app` (or the `.app` itself).
@property (nonatomic, copy) NSString *appFolder;

/// PKCS#12 certificate path. Ignored when `adhoc` is YES.
@property (nonatomic, copy, nullable) NSString *p12Path;
@property (nonatomic, copy, nullable) NSString *p12Password;
@property (nonatomic, copy, nullable) NSString *provisionPath;
@property (nonatomic, copy, nullable) NSString *entitlementsPath;

@property (nonatomic, copy, nullable) NSString *bundleIdentifier;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *version;
@property (nonatomic, copy, nullable) NSString *minimumOSVersion;
/// Square PNG used to replace the app icon.
@property (nonatomic, copy, nullable) NSString *iconPath;

/// Mach-O dylibs to copy into the bundle and load from the main executable.
@property (nonatomic, copy) NSArray<NSString *> *dylibPaths;
/// Load-command names (e.g. `@executable_path/Foo.dylib`) to strip.
@property (nonatomic, copy) NSArray<NSString *> *removeDylibNames;
@property (nonatomic) BOOL weakInject;

@property (nonatomic) BOOL enableFileSharing;
@property (nonatomic) BOOL removeSupportedDevices;
@property (nonatomic) BOOL removeExtensions;
@property (nonatomic) BOOL removeWatchApp;
@property (nonatomic) BOOL removeProvision;
@property (nonatomic) BOOL adhoc;

@end

@interface ZSKSigner : NSObject

/// Signs the bundle in place. Blocking; call off the main thread.
/// `logHandler` receives every line zsign prints.
+ (BOOL)signWithOptions:(ZSKSignOptions *)options
             logHandler:(nullable void (^)(NSString *line))logHandler
                  error:(NSError **)error NS_SWIFT_NAME(sign(options:log:));

/// Returns YES when `password` unlocks the PKCS#12 file and it pairs with the profile.
+ (BOOL)validateP12AtPath:(NSString *)p12Path
                 password:(NSString *)password
            provisionPath:(NSString *)provisionPath
                    error:(NSError **)error NS_SWIFT_NAME(validate(p12:password:provision:));

@end

NS_ASSUME_NONNULL_END
