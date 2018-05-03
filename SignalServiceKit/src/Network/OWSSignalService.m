//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSSignalService.h"
#import "NSNotificationCenter+OWS.h"
#import "OWSCensorshipConfiguration.h"
#import "OWSError.h"
#import "OWSHTTPSecurityPolicy.h"
#import "OWSPrimaryStorage.h"
#import "TSAccountManager.h"
#import "TSConstants.h"
#import "YapDatabaseConnection+OWS.h"
#import <AFNetworking/AFHTTPSessionManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kOWSPrimaryStorage_OWSSignalService = @"kTSStorageManager_OWSSignalService";
NSString *const kOWSPrimaryStorage_isCensorshipCircumventionManuallyActivated
    = @"kTSStorageManager_isCensorshipCircumventionManuallyActivated";
NSString *const kOWSPrimaryStorage_ManualCensorshipCircumventionDomain
    = @"kTSStorageManager_ManualCensorshipCircumventionDomain";
NSString *const kOWSPrimaryStorage_ManualCensorshipCircumventionCountryCode
    = @"kTSStorageManager_ManualCensorshipCircumventionCountryCode";

NSString *const kNSNotificationName_IsCensorshipCircumventionActiveDidChange =
    @"kNSNotificationName_IsCensorshipCircumventionActiveDidChange";

static NSString *TextSecureServerURL = @"wss://token-chat-service.herokuapp.com";


@interface OWSSignalService ()

@property (nonatomic, nullable, readonly) OWSCensorshipConfiguration *censorshipConfiguration;

@property (atomic) BOOL hasCensoredPhoneNumber;

@property (atomic) BOOL isCensorshipCircumventionActive;

@end

#pragma mark -

@implementation OWSSignalService

@synthesize isCensorshipCircumventionActive = _isCensorshipCircumventionActive;

+ (instancetype)sharedInstance
{
    static OWSSignalService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initDefault];
    });
    return sharedInstance;
}

- (instancetype)initDefault
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self observeNotifications];

    [self updateHasCensoredPhoneNumber];
    [self updateIsCensorshipCircumventionActive];

    OWSSingletonAssert();

    return self;
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(registrationStateDidChange:)
                                                 name:RegistrationStateDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(localNumberDidChange:)
                                                 name:kNSNotificationName_LocalNumberDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)updateHasCensoredPhoneNumber
{
    NSString *localNumber = [TSAccountManager localNumber];

    if (localNumber) {
        self.hasCensoredPhoneNumber = [OWSCensorshipConfiguration isCensoredPhoneNumber:localNumber];
    } else {
        DDLogError(@"%@ no known phone number to check for censorship.", self.logTag);
        self.hasCensoredPhoneNumber = NO;
    }

    [self updateIsCensorshipCircumventionActive];
}

- (BOOL)isCensorshipCircumventionManuallyActivated
{
    return
        [[OWSPrimaryStorage dbReadConnection] boolForKey:kOWSPrimaryStorage_isCensorshipCircumventionManuallyActivated
                                            inCollection:kOWSPrimaryStorage_OWSSignalService];
}

- (void)setIsCensorshipCircumventionManuallyActivated:(BOOL)value
{
    [[OWSPrimaryStorage dbReadWriteConnection] setObject:@(value)
                                                  forKey:kOWSPrimaryStorage_isCensorshipCircumventionManuallyActivated
                                            inCollection:kOWSPrimaryStorage_OWSSignalService];

    [self updateIsCensorshipCircumventionActive];
}

- (void)updateIsCensorshipCircumventionActive
{
    self.isCensorshipCircumventionActive
        = (self.isCensorshipCircumventionManuallyActivated || self.hasCensoredPhoneNumber);
}

- (void)setIsCensorshipCircumventionActive:(BOOL)isCensorshipCircumventionActive
{
    @synchronized(self)
    {
        if (_isCensorshipCircumventionActive == isCensorshipCircumventionActive) {
            return;
        }

        _isCensorshipCircumventionActive = isCensorshipCircumventionActive;
    }

    [[NSNotificationCenter defaultCenter]
        postNotificationNameAsync:kNSNotificationName_IsCensorshipCircumventionActiveDidChange
                           object:nil
                         userInfo:nil];
}

- (BOOL)isCensorshipCircumventionActive
{
    @synchronized(self)
    {
        return _isCensorshipCircumventionActive;
    }
}

- (AFHTTPSessionManager *)signalServiceSessionManager
{
    if (self.isCensorshipCircumventionActive) {
        DDLogInfo(@"%@ using reflector HTTPSessionManager via: %@",
            self.logTag,
            self.censorshipConfiguration.domainFrontBaseURL);
        return self.reflectorSignalServiceSessionManager;
    } else {
        return self.defaultSignalServiceSessionManager;
    }
}

+ (void)setBaseURLPath:(NSString *)baseURLPath {
    TextSecureServerURL = baseURLPath;
}

+ (NSString *)baseURLPath {
    return TextSecureServerURL;
}

- (AFHTTPSessionManager *)defaultSignalServiceSessionManager
{
    NSURL *baseURL = [[NSURL alloc] initWithString:OWSSignalService.baseURLPath];
    OWSAssert(baseURL);
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL sessionConfiguration:sessionConf];

    sessionManager.securityPolicy = [OWSHTTPSecurityPolicy sharedPolicy];
    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];

    return sessionManager;
}

- (NSURL *)domainFrontingBaseURL
{
    NSString *localNumber = [TSAccountManager localNumber];
    OWSAssert(localNumber.length > 0);
    
    // Target fronting domain
    OWSAssert(self.isCensorshipCircumventionActive);
    NSString *frontingHost = [self.censorshipConfiguration frontingHost:localNumber];
    if (self.isCensorshipCircumventionManuallyActivated && self.manualCensorshipCircumventionDomain.length > 0) {
        frontingHost = self.manualCensorshipCircumventionDomain;
    };
    NSURL *baseURL = [[NSURL alloc] initWithString:[self.censorshipConfiguration frontingHost:localNumber]];
    OWSAssert(baseURL);
    
    return baseURL;
}

- (AFHTTPSessionManager *)reflectorSignalServiceSessionManager
{
    OWSCensorshipConfiguration *censorshipConfiguration = self.censorshipConfiguration;

    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    // modify by yaozongchao, 参考toshi
//    AFHTTPSessionManager *sessionManager =
//        [[AFHTTPSessionManager alloc] initWithBaseURL:censorshipConfiguration.domainFrontBaseURL
//                                 sessionConfiguration:sessionConf];
    AFHTTPSessionManager *sessionManager =
    [[AFHTTPSessionManager alloc] initWithBaseURL:self.domainFrontingBaseURL
                             sessionConfiguration:sessionConf];

//    sessionManager.securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy;
    sessionManager.securityPolicy = [[self class] googlePinningPolicy];

    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    [sessionManager.requestSerializer setValue:self.censorshipConfiguration.signalServiceReflectorHost forHTTPHeaderField:@"Host"];
    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];

    return sessionManager;
}

#pragma mark - Profile Uploading

- (AFHTTPSessionManager *)CDNSessionManager
{
    if (self.isCensorshipCircumventionActive) {
        DDLogInfo(@"%@ using reflector CDNSessionManager via: %@",
            self.logTag,
            self.censorshipConfiguration.domainFrontBaseURL);
        return self.reflectorCDNSessionManager;
    } else {
        return self.defaultCDNSessionManager;
    }
}

- (AFHTTPSessionManager *)defaultCDNSessionManager
{
    NSURL *baseURL = [[NSURL alloc] initWithString:textSecureCDNServerURL];
    OWSAssert(baseURL);
    
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:baseURL sessionConfiguration:sessionConf];

    sessionManager.securityPolicy = [OWSHTTPSecurityPolicy sharedPolicy];
    
    // Default acceptable content headers are rejected by AWS
    sessionManager.responseSerializer.acceptableContentTypes = nil;

    return sessionManager;
}

- (AFHTTPSessionManager *)reflectorCDNSessionManager
{
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;

    OWSCensorshipConfiguration *censorshipConfiguration = self.censorshipConfiguration;

//    AFHTTPSessionManager *sessionManager =
//        [[AFHTTPSessionManager alloc] initWithBaseURL:censorshipConfiguration.domainFrontBaseURL
//                                 sessionConfiguration:sessionConf];
    AFHTTPSessionManager *sessionManager =
    [[AFHTTPSessionManager alloc] initWithBaseURL:self.domainFrontingBaseURL
                             sessionConfiguration:sessionConf];

//    sessionManager.securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy;
    sessionManager.securityPolicy = [[self class] googlePinningPolicy];


    sessionManager.requestSerializer = [AFJSONRequestSerializer serializer];
    [sessionManager.requestSerializer setValue:censorshipConfiguration.CDNReflectorHost forHTTPHeaderField:@"Host"];

    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];

    return sessionManager;
}

#pragma mark - Google Pinning Policy

/**
 * We use the Google Pinning Policy when connecting to our censorship circumventing reflector,
 * which is hosted on Google.
 */
+ (AFSecurityPolicy *)googlePinningPolicy {
    static AFSecurityPolicy *securityPolicy = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error;
        NSString *path = [NSBundle.mainBundle pathForResource:@"GIAG2" ofType:@"crt"];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            @throw [NSException
                    exceptionWithName:@"Missing server certificate"
                    reason:[NSString stringWithFormat:@"Missing signing certificate for service googlePinningPolicy"]
                    userInfo:nil];
        }
        
        NSData *googleCertData = [NSData dataWithContentsOfFile:path options:0 error:&error];
        if (!googleCertData) {
            if (error) {
                @throw [NSException exceptionWithName:@"OWSSignalServiceHTTPSecurityPolicy" reason:@"Couln't read google pinning cert" userInfo:nil];
            } else {
                NSString *reason = [NSString stringWithFormat:@"Reading google pinning cert faile with error: %@", error];
                @throw [NSException exceptionWithName:@"OWSSignalServiceHTTPSecurityPolicy" reason:reason userInfo:nil];
            }
        }
        
        NSSet<NSData *> *certificates = [NSSet setWithObject:googleCertData];
        securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate withPinnedCertificates:certificates];
    });
    return securityPolicy;
}

#pragma mark - Events

- (void)registrationStateDidChange:(NSNotification *)notification
{
    [self updateHasCensoredPhoneNumber];
}

- (void)localNumberDidChange:(NSNotification *)notification
{
    [self updateHasCensoredPhoneNumber];
}

#pragma mark - Manual Censorship Circumvention

- (nullable OWSCensorshipConfiguration *)censorshipConfiguration
{
    if (self.isCensorshipCircumventionManuallyActivated) {
        NSString *countryCode = self.manualCensorshipCircumventionCountryCode;
        if (countryCode.length == 0) {
            OWSFail(@"%@ manualCensorshipCircumventionCountryCode was unexpectedly 0", self.logTag);
        }

        OWSCensorshipConfiguration *configuration =
            [OWSCensorshipConfiguration censorshipConfigurationWithCountryCode:countryCode];
        OWSAssert(configuration);

        return configuration;
    }

    OWSCensorshipConfiguration *configuration =
        [OWSCensorshipConfiguration censorshipConfigurationWithPhoneNumber:TSAccountManager.localNumber];
    return configuration;
}

- (nullable NSString *)manualCensorshipCircumventionCountryCode
{
    return
        [[OWSPrimaryStorage dbReadConnection] objectForKey:kOWSPrimaryStorage_ManualCensorshipCircumventionCountryCode
                                              inCollection:kOWSPrimaryStorage_OWSSignalService];
}

- (void)setManualCensorshipCircumventionCountryCode:(nullable NSString *)value
{
    [[OWSPrimaryStorage dbReadWriteConnection] setObject:value
                                                  forKey:kOWSPrimaryStorage_ManualCensorshipCircumventionCountryCode
                                            inCollection:kOWSPrimaryStorage_OWSSignalService];
}

@end

NS_ASSUME_NONNULL_END
