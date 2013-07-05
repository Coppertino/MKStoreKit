//
//  MKStoreKitConfigs.m
//  Vox
//
//  Created by Ivan Ablamskyi on 05.07.13.
//  Copyright (c) 2013 Coppertino Inc. All rights reserved.
//

#import "MKStoreKitConfigs.h"

@interface MKStoreKitConfigs (/* Private */)

@property (nonatomic) BOOL _reviewAllowed, _redeemAllowed, _serverProductModel;
@property (nonatomic, copy) NSString *_sharedSecret;
@property (nonatomic, copy) NSURL *_ownServerURL;
@property (nonatomic) NSDictionary *_products;
@property (assign) SecKeyRef _publicKeyRef;

@end

@implementation MKStoreKitConfigs

+ (instancetype)sharedConfigs
{
    static MKStoreKitConfigs *_sharedConfigs = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedConfigs = [[self alloc] init];
        _sharedConfigs._products = @{
                                     @"Consumables" : [NSMutableDictionary dictionary],
                                     @"Non-Consumables" : [NSMutableArray array],
                                     @"Subscriptions" : [NSMutableDictionary dictionary]
                                     };
    });
    
    return _sharedConfigs;
}

- (void)dealloc
{
    //clean public key
}

// ------------------------------------------------
// Public mehtods
// ------------------------------------------------
+ (BOOL)isServerProductModel;
{
    return [self.sharedConfigs _serverProductModel];
}

+ (BOOL)isReviewAllowed;
{
    return [self.sharedConfigs _reviewAllowed];
}

+ (BOOL)isRedeemAllowed;
{
    return [self.sharedConfigs _redeemAllowed];
}

+ (NSURL *)ownServerURL;
{
    return [self.sharedConfigs _ownServerURL];
}

+ (NSString *)sharedSecret;
{
    return [self.sharedConfigs _sharedSecret];
}

+ (NSDictionary *)products
{
    return [self.sharedConfigs _products];
}

+ (NSString *)deviceId
{
#if TARGET_OS_IPHONE
    NSString *uniqueID;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id uuid = [defaults objectForKey:@"uniqueID"];
    if (uuid)
        uniqueID = (NSString *)uuid;
    else {
        CFUUIDRef cfUuid = CFUUIDCreate(NULL);
        CFStringRef cfUuidString = CFUUIDCreateString(NULL, cfUuid);
        CFRelease(cfUuid);
        uniqueID = (__bridge NSString *)cfUuidString;
        [defaults setObject:uniqueID forKey:@"uniqueID"];
        CFRelease(cfUuidString);
    }
    
    return uniqueID;
    
#elif TARGET_OS_MAC
    NSString* result = nil;
    
    CFStringRef serialNumber = NULL;
    io_service_t platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"));
    
    if (platformExpert)	{
        CFTypeRef serialNumberAsCFString = IORegistryEntryCreateCFProperty( platformExpert, CFSTR(kIOPlatformUUIDKey), kCFAllocatorDefault, 0 );
        serialNumber = (CFStringRef)serialNumberAsCFString;
        IOObjectRelease(platformExpert);
    }
    
    if (serialNumber)
        result = (__bridge_transfer NSString *)serialNumber;
    else
        result = @"unknown";
    
    return result;
#endif
}

+ (SecKeyRef)publicKey
{
    return [self.sharedConfigs _publicKeyRef];
}

- (void)setOwnServer:(NSURL *)url;
{
    self._ownServerURL = url;
}
- (void)setSharedSecret:(NSString *)secret;
{
    self._sharedSecret = secret;
}

- (void)setReviewAllowed:(BOOL)flag;
{
    self._reviewAllowed = flag;
}

- (void)setRedeemAllowed:(BOOL)flag;
{
    self._redeemAllowed = flag;
}

- (void)setServerProductModel:(BOOL)flag;
{
    self._serverProductModel = flag;
}

- (void)setPublicKeyString:(NSString *)publicKey;
{
    if (!publicKey) {
		return;
	}
    
    if (self._publicKeyRef) {
        CFRelease(self._publicKeyRef);
        self._publicKeyRef = NULL;
    }
    
	OSStatus			status;
	CFArrayRef			items		= NULL;
	SecExternalFormat	format		= kSecFormatUnknown;
	SecExternalItemType itemType	= kSecItemTypeUnknown;
    
	status = SecItemImport((__bridge CFDataRef)[publicKey dataUsingEncoding:NSUTF8StringEncoding], NULL, &format, &itemType, CSSM_KEYATTR_EXTRACTABLE, NULL, NULL, &items);
    
	if ((format != kSecFormatOpenSSL) || (itemType != kSecItemTypePublicKey) || !items || (CFArrayGetCount(items) != 1)) {
#ifdef DEBUG
        if (status != noErr) {
            NSString *errorMessage = (__bridge NSString *)SecCopyErrorMessageString(status, NULL);
            NSLog(@"Unable to import public key: %@", errorMessage);
        } else if (itemType != kSecItemTypePublicKey) {
            NSLog(@"Unable to import public key: key is not public");
        } else if (format != kSecFormatOpenSSL) {
            NSLog(@"Unable to import public key: key is not in OpenSSL Format");
        } else if (!items || (CFArrayGetCount(items) != 1)) {
            NSLog(@"Unable to import public key: Provided data have no OpenSSL key info");
        }
#endif
        
		if (items) {
			CFRelease(items);
			items = NULL;
		}
        
		return;
	}
    
    self._publicKeyRef = (SecKeyRef)CFRetain(CFArrayGetValueAtIndex(items, 0));
}

- (void)addConsumableProduct:(NSString *)productId withName:(NSString *)name andCount:(NSUInteger)count;
{
    self._products[@"Consumables"][productId] = @{@"Name" : name, @"Count" : @(count)};
}

- (void)addNonConsumableProduct:(NSString *)productId;
{
    [self._products[@"Non-Consumables"] addObject:productId];
}

- (void)addSubscription:(NSString *)productId andRenewInterval:(NSUInteger)interval;
{
    self._products[@"Subscriptions"][productId] = @(interval);
}


@end
