//
//  MKStoreManager.m
//  MKStoreKit (Version 5.0)
//
//	File created using Singleton XCode Template by Mugunth Kumar (http://mugunthkumar.com
//  Permission granted to do anything, commercial/non-commercial with this file apart from removing the line/URL above
//  Read my blog post at http://mk.sg/1m on how to use this code

//  Created by Mugunth Kumar (@mugunthkumar) on 04/07/11.
//  Copyright (C) 2011-2020 by Steinlogic Consulting And Training Pte Ltd.

//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

//  As a side note on using this code, you might consider giving some credit to me by
//	1) linking my website from your app's website
//	2) or crediting me inside the app's credits page
//	3) or a tweet mentioning @mugunthkumar
//	4) A paypal donation to mugunth.kumar@gmail.com

#import <Security/CMSDecoder.h>
#import <Security/SecAsn1Coder.h>
#import <Security/SecAsn1Templates.h>
#import <Security/SecRequirement.h>
#import <CommonCrypto/CommonDigest.h>

#import "MKStoreManager.h"
#import "SSKeychain.h"
#import "MKSKSubscriptionProduct.h"
#import "MKSKProduct.h"
#import "NSData+MKBase64.h"

#if ! __has_feature(objc_arc)
#error MKStoreKit is ARC only. Either turn on ARC for the project or use -fobjc-arc flag
#endif

#if TARGET_OS_MAC
/*
 * For OSX Validtion
 */
typedef struct {
    size_t          length;
    unsigned char   *data;
} tMKASN1_Data;

typedef struct {
    tMKASN1_Data type;     // INTEGER
    tMKASN1_Data version;  // INTEGER
    tMKASN1_Data value;    // OCTET STRING
} tMKReceiptAttribute;

typedef struct {
    tMKReceiptAttribute **attrs;
} tMKReceiptPayload;

// ASN.1 receipt attribute template
static const SecAsn1Template kMKReceiptAttributeTemplate[] = {
    { SEC_ASN1_SEQUENCE, 0, NULL, sizeof(tMKReceiptAttribute) },
    { SEC_ASN1_INTEGER, offsetof(tMKReceiptAttribute, type), NULL, 0 },
    { SEC_ASN1_INTEGER, offsetof(tMKReceiptAttribute, version), NULL, 0 },
    { SEC_ASN1_OCTET_STRING, offsetof(tMKReceiptAttribute, value), NULL, 0 },
    { 0, 0, NULL, 0 }
};

// ASN.1 receipt template set
static const SecAsn1Template kMKSetOfReceiptAttributeTemplate[] = {
    { SEC_ASN1_SET_OF, 0, kMKReceiptAttributeTemplate, sizeof(tMKReceiptPayload) },
    { 0, 0, NULL, 0 }
};

enum {
    kMKReceiptAttributeTypeInAppPurchaseReceipt    = 17,
    
    kMKReceiptAttributeTypeInAppQuantity               = 1701,
    kMKReceiptAttributeTypeInAppProductID              = 1702,
    kMKReceiptAttributeTypeInAppTransactionID          = 1703,
    kMKReceiptAttributeTypeInAppPurchaseDate           = 1704,
    kMKReceiptAttributeTypeInAppOriginalTransactionID  = 1705,
    kMKReceiptAttributeTypeInAppOriginalPurchaseDate   = 1706,
};

static NSString * const kMKStoreErrorDomain = @"MKStoreKitErrorDomain";

static NSString *kMKReceiptInfoKeyInAppProductID               = @"in-app-id";
static NSString *kMKReceiptInfoKeyInAppTransactionID           = @"in-app-trx-id";
static NSString *kMKReceiptInfoKeyInAppOriginalTransactionID   = @"in-app-original-trx-id";
static NSString *kMKReceiptInfoKeyInAppPurchaseDate            = @"in-app-date";
static NSString *kMKReceiptInfoKeyInAppOriginalPurchaseDate    = @"in-app-original-date";
static NSString *kMKReceiptInfoKeyInAppQuantity                = @"in-app-qnt";
static NSString *kMKReceiptInfoKeyInAppPurchaseReceipt         = @"in-app-purchase-rctp";

inline static NSData *MKDecodeReceiptData(NSData *receiptData, NSError **error)
{
    CMSDecoderRef decoder = NULL;
    SecPolicyRef policyRef = NULL;
    SecTrustRef trustRef = NULL;
    
    NSData *ret = nil;
    CFDataRef dataRef = NULL;
    NSError *err;
    

    // Create a decoder
    OSStatus status = CMSDecoderCreate(&decoder);
    if (status) {
        err = [NSError errorWithDomain:kMKStoreErrorDomain
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey:@"Failed to decode MAS receipt data: Create a decoder"}];
        goto finish;
    }
    
    // Decrypt the message (1)
    status = CMSDecoderUpdateMessage(decoder, receiptData.bytes, receiptData.length);
    if (status) {
        err = [NSError errorWithDomain:kMKStoreErrorDomain
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey:@"Failed to decode MAS receipt data: Update message"}];
        goto finish;
    }
    
    // Decrypt the message (2)
    status = CMSDecoderFinalizeMessage(decoder);
    if (status) {
        err = [NSError errorWithDomain:kMKStoreErrorDomain
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey:@"Failed to decode MAS receipt data: Finalize message"}];
        goto finish;
    }
    
    // Get the decrypted content
    status = CMSDecoderCopyContent(decoder, &dataRef);
    if (status) {
        err = [NSError errorWithDomain:kMKStoreErrorDomain
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey:@"Failed to decode MAS receipt data: Get decrypted content"}];
        goto finish;
    }
    ret = [NSData dataWithData:(__bridge NSData *)dataRef];
    CFRelease(dataRef);
    
    // Check the signature
    size_t numSigners;
    status = CMSDecoderGetNumSigners(decoder, &numSigners);
    if (status) {
        err = [NSError errorWithDomain:kMKStoreErrorDomain
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey:@"Failed to decode MAS receipt data: Get singer count"}];
        goto finish;

    }
    if (numSigners == 0) {
        err = [NSError errorWithDomain:kMKStoreErrorDomain
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey:@"Failed to decode MAS receipt data: No signer found"}];
        goto finish;
    }
    
    policyRef = SecPolicyCreateBasicX509();
    
    CMSSignerStatus signerStatus;
    OSStatus certVerifyResult;
    status = CMSDecoderCopySignerStatus(decoder, 0, policyRef, TRUE, &signerStatus, &trustRef, &certVerifyResult);
    if (status) {
        err = [NSError errorWithDomain:kMKStoreErrorDomain
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey:@"Failed to decode MAS receipt data: Get signer status"}];
        goto finish;
    }
    if (signerStatus != kCMSSignerValid) {
        err = [NSError errorWithDomain:kMKStoreErrorDomain
                                  code:-1
                              userInfo:@{NSLocalizedDescriptionKey:@"Failed to decode MAS receipt data: No valid signer"}];
        goto finish;
    }
        
finish:
    if (policyRef) CFRelease(policyRef);
    if (trustRef) CFRelease(trustRef);
    if (decoder) CFRelease(decoder);
    
    if (err) *error = err;
    
    return ret;
}

inline static int MKGetIntValueFromASN1Data(const tMKASN1_Data *asn1Data)
{
    int ret = 0;
    for (int i = 0; i < asn1Data->length; i++) {
        ret = (ret << 8) | asn1Data->data[i];
    }
    return ret;
}

inline static NSNumber *MKDecodeIntNumberFromASN1Data(SecAsn1CoderRef decoder, tMKASN1_Data srcData, NSError **error)
{
    tMKASN1_Data asn1Data;
    OSStatus status = SecAsn1Decode(decoder, srcData.data, srcData.length, kSecAsn1IntegerTemplate, &asn1Data);
    if (status) {
        *error = [NSError errorWithDomain:kMKStoreErrorDomain
                                     code:-2
                                 userInfo:@{NSLocalizedDescriptionKey:@"Failed to get MAS receipt information: Decode integer value"}];
        return nil;
    }
    return [NSNumber numberWithInt:MKGetIntValueFromASN1Data(&asn1Data)];
}

inline static NSString *MKDecodeUTF8StringFromASN1Data(SecAsn1CoderRef decoder, tMKASN1_Data srcData, NSError **error)
{
    tMKASN1_Data asn1Data;
    OSStatus status = SecAsn1Decode(decoder, srcData.data, srcData.length, kSecAsn1UTF8StringTemplate, &asn1Data);
    if (status) {
        *error = [NSError errorWithDomain:kMKStoreErrorDomain
                                     code:-2
                                 userInfo:@{NSLocalizedDescriptionKey:@"Failed to get MAS receipt information: Decode UTF-8 string"}];
        return nil;
    }
    return [[NSString alloc] initWithBytes:asn1Data.data length:asn1Data.length encoding:NSUTF8StringEncoding];
}

inline static NSDate *MKDecodeDateFromASN1Data(SecAsn1CoderRef decoder, tMKASN1_Data srcData, NSError **error)
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-ddTHH:mm:ssZ"];
    
    tMKASN1_Data asn1Data;
    OSStatus status = SecAsn1Decode(decoder, srcData.data, srcData.length, kSecAsn1IA5StringTemplate, &asn1Data);
    if (status) {
        *error = [NSError errorWithDomain:kMKStoreErrorDomain
                                     code:-2
                                 userInfo:@{NSLocalizedDescriptionKey:@"Failed to get MAS receipt information: Decode date (IA5 string)"}];
        return nil;
    }
    
    NSString *dateStr = [[NSString alloc] initWithBytes:asn1Data.data length:asn1Data.length encoding:NSASCIIStringEncoding];
    return [dateFormatter dateFromString:dateStr];
}

inline static NSDictionary *MKGetReceiptPayload(NSData *payloadData, NSError **error)
{
    SecAsn1CoderRef asn1Decoder = NULL;

    NSMutableDictionary *ret = [NSMutableDictionary dictionary];
    
    // Create the ASN.1 parser
    OSStatus status = SecAsn1CoderCreate(&asn1Decoder);
    if (status) {
        *error = [NSError errorWithDomain:kMKStoreErrorDomain
                                     code:-3
                                 userInfo:@{NSLocalizedDescriptionKey:@"Failed to get MAS receipt information: Create ASN.1 decoder"}];
        
        if (asn1Decoder) SecAsn1CoderRelease(asn1Decoder);
        return nil;
    }
    
    // Decode the receipt payload
    tMKReceiptPayload payload = { NULL };
    status = SecAsn1Decode(asn1Decoder, payloadData.bytes, payloadData.length, kMKSetOfReceiptAttributeTemplate, &payload);
    if (status) {
        *error = [NSError errorWithDomain:kMKStoreErrorDomain
                                     code:-3
                                 userInfo:@{NSLocalizedDescriptionKey:@"Failed to get MAS receipt information: Decode payload"}];
        if (asn1Decoder) SecAsn1CoderRelease(asn1Decoder);
        return nil;
    }
    
    // Fetch all attributes
    tMKReceiptAttribute *anAttr;
    NSError *err;
    for (int i = 0; (anAttr = payload.attrs[i]); i++) {
        int type = MKGetIntValueFromASN1Data(&anAttr->type);
        switch (type) {
            case kMKReceiptAttributeTypeInAppProductID:
                [ret setValue:MKDecodeUTF8StringFromASN1Data(asn1Decoder, anAttr->value, &err)
                       forKey:kMKReceiptInfoKeyInAppProductID];
                break;
            case kMKReceiptAttributeTypeInAppTransactionID:
                [ret setValue:MKDecodeUTF8StringFromASN1Data(asn1Decoder, anAttr->value, &err)
                       forKey:kMKReceiptInfoKeyInAppTransactionID];
                break;
            case kMKReceiptAttributeTypeInAppOriginalTransactionID:
                [ret setValue:MKDecodeUTF8StringFromASN1Data(asn1Decoder, anAttr->value, &err)
                       forKey:kMKReceiptInfoKeyInAppOriginalTransactionID];
                break;
                
                // Purchase Date (As IA5 String (almost identical to the ASCII String))
            case kMKReceiptAttributeTypeInAppPurchaseDate:
                [ret setValue:MKDecodeDateFromASN1Data(asn1Decoder, anAttr->value, &err)
                       forKey:kMKReceiptInfoKeyInAppPurchaseDate];
                break;
            case kMKReceiptAttributeTypeInAppOriginalPurchaseDate:
                [ret setValue:MKDecodeDateFromASN1Data(asn1Decoder, anAttr->value, &err)
                       forKey:kMKReceiptInfoKeyInAppOriginalPurchaseDate];
                break;
                
                // Quantity (Integer Value)
            case kMKReceiptAttributeTypeInAppQuantity:
                [ret setValue:MKDecodeIntNumberFromASN1Data(asn1Decoder, anAttr->value, &err)
                       forKey:kMKReceiptInfoKeyInAppQuantity];
                break;
                
                // In App Purchases Receipt
            case kMKReceiptAttributeTypeInAppPurchaseReceipt: {
                NSMutableArray *inAppPurchases = [ret valueForKey:kMKReceiptInfoKeyInAppPurchaseReceipt];
                if (!inAppPurchases) {
                    inAppPurchases = [NSMutableArray array];
                    [ret setValue:inAppPurchases forKey:kMKReceiptInfoKeyInAppPurchaseReceipt];
                }
                NSData *inAppData = [NSData dataWithBytes:anAttr->value.data length:anAttr->value.length];
                NSDictionary *inAppInfo = MKGetReceiptPayload(inAppData, &err);
                [inAppPurchases addObject:inAppInfo];
                break;
            }
                
                // Otherwise
            default:
                break;
        }
        if (err) {
            *error = err;
            ret = nil;
            break;
        }
    }
    if (asn1Decoder) SecAsn1CoderRelease(asn1Decoder);
    
    return ret;
}

#endif

@interface MKStoreManager (/* private methods and properties */)

@property (nonatomic, copy) void (^onTransactionCancelled)(NSError *e);
@property (nonatomic, copy) void (^onTransactionCompleted)(NSString *productId, NSData* receiptData, NSArray* downloads);

@property (nonatomic, copy) void (^onRestoreFailed)(NSError* error);
@property (nonatomic, copy) void (^onRestoreCompleted)();

@property (nonatomic, assign, getter=isProductsAvailable) BOOL isProductsAvailable;
@property (nonatomic, strong) NSMutableArray *previewAllowedProducts;
@property (nonatomic, strong) SKProductsRequest *productsRequest;

+ (NSString *)serviceName;

- (void)requestProductData;
- (void)startVerifyingSubscriptionReceipts;
- (void)rememberPurchaseOfProduct:(NSString*) productIdentifier withReceipt:(NSData*) receiptData;
- (void)addToQueue:(NSString*) productId;

@end

@implementation MKStoreManager

+ (NSString *)serviceName;
{
    return [[[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleNameKey] stringByAppendingString:@"-Store"];
}

+ (void)updateFromiCloud:(NSNotification *)notificationObject
{
    if ([MKStoreKitConfigs isReviewAllowed]) {
        return;
    }
    
    NSUbiquitousKeyValueStore *iCloudStore = [NSUbiquitousKeyValueStore defaultStore];
    NSDictionary *dict = [iCloudStore dictionaryRepresentation];
    NSMutableArray *products = [self allProducts];
    
    [products enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        id valueFromiCloud = [dict objectForKey:obj];

        if(valueFromiCloud) {
            NSError *error = nil;
            if ([SSKeychain setPassword:valueFromiCloud forService:[self.class serviceName] account:obj error:&error] && error) {
                NSLog(@"%@", error);
            }
        }
    }];
}

+ (BOOL)iCloudAvailable
{
    if (![MKStoreKitConfigs isReviewAllowed] && NSClassFromString(@"NSUbiquitousKeyValueStore")) {      // is iOS 5?
        if ([NSUbiquitousKeyValueStore defaultStore]) {         // is iCloud enabled
            return YES;
        }
    }
    
    return NO;
}

+ (void)setObject:(id)object forKey:(NSString *)key
{
    if (object) {
        NSString *objectString = nil;
        if ([object isKindOfClass:[NSData class]]) {
            objectString = [[NSString alloc] initWithData:object encoding:NSUTF8StringEncoding];
        }
        
        if ([object isKindOfClass:[NSNumber class]]) {
            objectString = [(NSNumber*)object stringValue];
        }
        
        NSError *error = nil;
        if (![SSKeychain setPassword:objectString forService:[self.class serviceName] account:key error:&error] && error) {
            NSLog(@"%@", error);
        }
        
        if ([self iCloudAvailable]) {
            [[NSUbiquitousKeyValueStore defaultStore] setObject:objectString forKey:key];
            [[NSUbiquitousKeyValueStore defaultStore] synchronize];
        }
    } else {
        
        NSError *error = nil;
        if ([SSKeychain deletePasswordForService:[self.class serviceName] account:key error:&error] && error) {
            NSLog(@"%@", error);
        }
        
        if([self iCloudAvailable]) {
            [[NSUbiquitousKeyValueStore defaultStore] removeObjectForKey:key];
            [[NSUbiquitousKeyValueStore defaultStore] synchronize];
        }
    }
}

+ (id)receiptForKey:(NSString *)key {
    
    NSData *receipt = [MKStoreManager objectForKey:key];
    
    if (!receipt) {
        receipt = [MKStoreManager objectForKey:[NSString stringWithFormat:@"%@-receipt", key]];
    }
    
    return receipt;
}

+ (id)objectForKey:(NSString *)key
{
    NSError *error = nil;
    id password = [SSKeychain passwordForService:[self.class serviceName] account:key error:&error];
    if(!password && error && [error code] != -25300) {
        NSLog(@"MK:SSKeychain: %@", error);
    }
    
    return password;
}

+ (NSNumber *)numberForKey:(NSString *)key
{
    return [NSNumber numberWithInt:[[MKStoreManager objectForKey:key] intValue]];
}

+ (NSData *)dataForKey:(NSString*)key
{
    return [[MKStoreManager objectForKey:key] dataUsingEncoding:NSUTF8StringEncoding];
}


#pragma mark - Singleton Methods
+ (instancetype)sharedManager {
    static MKStoreManager *_sharedStoreManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedStoreManager = [[self alloc] init];
        _sharedStoreManager.previewAllowedProducts = [NSMutableArray array];
        _sharedStoreManager.purchasableObjects = [NSMutableArray array];
#if defined (__IPHONE_6_0) || defined(NSAppKitVersionNumber10_7_2)
        _sharedStoreManager.hostedContents = [NSMutableArray array];
#endif
        [_sharedStoreManager requestProductData];
        [[SKPaymentQueue defaultQueue] addTransactionObserver:_sharedStoreManager];
        [_sharedStoreManager startVerifyingSubscriptionReceipts];

        if ([self iCloudAvailable])
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(updateFromiCloud:)
                                                         name:NSUbiquitousKeyValueStoreDidChangeExternallyNotification
                                                       object:nil];
        
    });
    
    return _sharedStoreManager;
}

#pragma mark - Internal MKStoreKit functions
+ (NSDictionary *)storeKitItems
{
    return MKStoreKitConfigs.products;
}

- (void)restorePreviousTransactionsOnComplete:(void (^)(void)) completionBlock
                                      onError:(void (^)(NSError*)) errorBlock
{
    self.onRestoreCompleted = completionBlock;
    self.onRestoreFailed = errorBlock;
    
	[[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

- (void)restoreCompleted
{
    if(self.onRestoreCompleted) {
        self.onRestoreCompleted();
    }
    
    self.onRestoreCompleted = nil;
}

- (void)restoreFailedWithError:(NSError *)error
{
    if (self.onRestoreFailed) {
        self.onRestoreFailed(error);
    }
    
    self.onRestoreFailed = nil;
}

- (void)requestProductData
{
    NSMutableArray *productsArray = [NSMutableArray array];
    NSArray *consumables = [[[MKStoreManager storeKitItems] objectForKey:@"Consumables"] allKeys];
    NSArray *nonConsumables = [[MKStoreManager storeKitItems] objectForKey:@"Non-Consumables"];
    NSArray *subscriptions = [[[MKStoreManager storeKitItems] objectForKey:@"Subscriptions"] allKeys];
    
    [productsArray addObjectsFromArray:consumables];
    [productsArray addObjectsFromArray:nonConsumables];
    [productsArray addObjectsFromArray:subscriptions];
    
    if ([MKStoreKitConfigs isReviewAllowed]) {
        [self.purchasableObjects addObjectsFromArray:consumables];
        [self.purchasableObjects addObjectsFromArray:nonConsumables];
        [self.purchasableObjects addObjectsFromArray:subscriptions];
        
        // request data from server
        [self.purchasableObjects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
           [MKSKProduct verifyProductForReviewAccess:obj onComplete:^(NSNumber *status) {
               NSLog(@"loooking %@ res %@", obj, status);
               if ([status intValue] == 1) {
                   [[[MKStoreManager sharedManager] previewAllowedProducts] addObject:obj];
               }
           } onError:NULL];
        }];
    } else {
        self.productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:productsArray]];
        self.productsRequest.delegate = self;
        [self.productsRequest start];
    }
}

+ (NSMutableArray*)allProducts
{
    NSMutableArray *productsArray = [NSMutableArray array];
    NSArray *consumables = [[[self storeKitItems] objectForKey:@"Consumables"] allKeys];
    NSArray *consumableNames = [self allConsumableNames];
    NSArray *nonConsumables = [[self storeKitItems] objectForKey:@"Non-Consumables"];
    NSArray *subscriptions = [[[self storeKitItems] objectForKey:@"Subscriptions"] allKeys];
    
    [productsArray addObjectsFromArray:consumables];
    [productsArray addObjectsFromArray:consumableNames];
    [productsArray addObjectsFromArray:nonConsumables];
    [productsArray addObjectsFromArray:subscriptions];
    
    return productsArray;
}

+ (NSArray *)allConsumableNames
{
    NSMutableSet *consumableNames = [[NSMutableSet alloc] initWithCapacity:0];
    NSDictionary *consumables = [[self storeKitItems] objectForKey:@"Consumables"];

    for (NSDictionary *consumable in [consumables allValues]) {
        NSString *name = [consumable objectForKey:@"Name"];
        [consumableNames addObject:name];
    }
    
    return [consumableNames allObjects];
}

- (BOOL)removeAllKeychainData
{
    __block NSError *error = nil;
    [[MKStoreManager allProducts] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [SSKeychain deletePasswordForService:[self.class serviceName] account:obj error:&error];
    }];
    
    return (error != nil);
}

- (BOOL)verifySignature:(NSData *)signature data:(NSData *)data
{
	if (([data length] == 0) || !signature) {
		return NO;
	}

	SecTransformRef			verifierTransform	= NULL;
	SecGroupTransformRef	group				= SecTransformCreateGroupTransform();
	CFReadStreamRef			readStream			= NULL;
	SecTransformRef			readTransform		= NULL;
    
	Boolean			status = false;
	CFBooleanRef	verifyStatus = NULL;
    
    readStream		= CFReadStreamCreateWithBytesNoCopy (kCFAllocatorDefault, [data bytes], [data length], kCFAllocatorNull);
    readTransform	= SecTransformCreateReadTransformWithReadStream(readStream);
    
    if (!readTransform) {
        goto finish;
    }
    
    verifierTransform = SecVerifyTransformCreate(MKStoreKitConfigs.publicKey, (__bridge CFDataRef)signature, NULL);
    
    if (!verifierTransform) {
        goto finish;
    }
    
    // Set to a digest input
    status = SecTransformSetAttribute(verifierTransform, kSecInputIsDigest, kCFBooleanTrue, NULL);
    
    if (!status) {
        goto finish;
    }
    
    // Set to a SHA1 digest input
    status = SecTransformSetAttribute(verifierTransform, kSecDigestTypeAttribute, kSecDigestSHA1, NULL);
    
    if (!status) {
        goto finish;
    }
    
    // Configure and then run group
    SecTransformConnectTransforms(readTransform, kSecTransformOutputAttributeName, verifierTransform, kSecTransformInputAttributeName, group, NULL);
    
    // Execute group
    CFErrorRef error = NULL;
    verifyStatus = SecTransformExecute(group, &error);
    
    if (error) { CFRelease(error); error = NULL; }
    
    status = verifyStatus != NULL;
    if (status)
    {
        status = CFBooleanGetValue(verifyStatus);
        CFRelease(verifyStatus);
    }
    
finish:
    
    if (verifierTransform) { CFRelease (verifierTransform); }
    if (group) { CFRelease (group); }
    if (readStream) { CFRelease (readStream); }
    if (readTransform) { CFRelease (readTransform);}
    
    return status == true;
}

- (NSString *)MD5StringForString:(NSString *)string {
    const char *cstr = [string UTF8String];
    unsigned char result[16];
    CC_MD5(cstr, strlen(cstr), result);
    
    return [NSString stringWithFormat:
            @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];  
}

#pragma mark - Delegation
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
	[self.purchasableObjects addObjectsFromArray:response.products];
	
#ifdef DEBUG
    [self.purchasableObjects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        SKProduct *product = obj;
        NSLog(@"Feature: %@, Cost: %f, ID: %@", product.localizedTitle, [product.price doubleValue], product.productIdentifier);
    }];
    
    [response.invalidProductIdentifiers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSLog(@"Problem in iTunes connect configuration for product: %@", obj);
    }];
#endif
    
	self.isProductsAvailable = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:kProductFetchedNotification
                                                        object:@(self.isProductsAvailable)];
	self.productsRequest = nil;
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error
{
	self.isProductsAvailable = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:kProductFetchedNotification
                                                        object:[NSNumber numberWithBool:self.isProductsAvailable]];
	self.productsRequest = nil;
}

// call this function to check if the user has already purchased your feature
+ (BOOL)isFeaturePurchased:(NSString *)featureId
{
    if ([MKStoreKitConfigs isReviewAllowed]) {
        __block BOOL purhcased = NO;
        [[[MKStoreManager sharedManager] previewAllowedProducts] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if ([obj isEqualToString:featureId]) {
                purhcased = YES;
                *stop = YES;
            }
        }];
        
        return purhcased;
    }

    if  ([[MKStoreManager numberForKey:featureId] boolValue]) {
        NSData *receiptData = [[MKStoreManager objectForKey:[NSString stringWithFormat:@"%@-receipt", featureId]] dataUsingEncoding:NSUTF8StringEncoding];
        
        // For redeem or activation by license receipt will be JSON
        id jsonObject = receiptData ? [NSJSONSerialization JSONObjectWithData:receiptData options:0 error:NULL] : nil;
        
        BOOL isValidJson = jsonObject && [jsonObject isKindOfClass:[NSDictionary class]] && [jsonObject valueForKey:@"type"];
        if (isValidJson) {
        
            // check for redeem or activation by license
            if ([jsonObject[@"type"] isEqualToString:@"redeem"]
                || [jsonObject[@"type"] isEqualToString:@"activationByLicense"]) {
                
                NSDictionary *receiptObject = jsonObject[@"receipt"];
                NSString *signature = jsonObject[@"signature"];
                NSString *signatureProductId = receiptObject[@"productid"] ? receiptObject[@"productid"] : receiptObject[@"product_id"];
                
                NSData *receiptData;
                if ([jsonObject[@"type"] isEqualToString:@"activationByLicense"]) {
                    NSString *receiptString = [NSString stringWithFormat:@"%@%@", receiptObject[@"productid"], receiptObject[@"hwid"]];
                    receiptData = [receiptString dataUsingEncoding:NSUTF8StringEncoding];
                } else {
                    receiptData = [NSJSONSerialization dataWithJSONObject:receiptObject options:0 error:NULL];
                }
                
                BOOL validate = [receiptObject[@"hwid"] isEqualToString:MKStoreKitConfigs.deviceId];
                validate = validate && [signatureProductId isEqualToString:featureId];
                validate = validate && [[MKStoreManager sharedManager] verifySignature:[NSData dataFromBase64String:signature]
                                                                                  data:receiptData];
                return validate;
            }
            
            // check for receipt stored after MAS purchase
            if ([jsonObject[@"type"] isEqualToString:@"store"]) {
                NSDictionary *receiptObject = jsonObject[@"receipt"];
                NSString *signature = jsonObject[@"signature"];
                
                NSString *srtingToCheck = [NSString stringWithFormat:@"%@.%@.%@", [[NSBundle mainBundle] bundleIdentifier], featureId, MKStoreKitConfigs.deviceId];
                BOOL validate = [[[self sharedManager] MD5StringForString:srtingToCheck] isEqualToString:signature];
                
                return validate;
            }
        }
        
        // If no one receipt is stored in Key Chain then check receipt in app MAS signature
        if (!receiptData) {
            NSError *error;
            NSData *payloadData = MKDecodeReceiptData([[self sharedManager] receiptFromBundle], &error);
            if (error) {
                NSLog(@"Error while checking purchase: %@", error);
                return NO;
            }
            NSDictionary *inapps = MKGetReceiptPayload(payloadData, &error);
            if (error) {
                NSLog(@"Error while checking purchase: %@", error);
                return NO;
            }
            if (inapps && [inapps valueForKey:kMKReceiptInfoKeyInAppPurchaseReceipt]) {
                __block BOOL result = NO;
                [inapps[kMKReceiptInfoKeyInAppPurchaseReceipt] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    if ([[obj valueForKey:kMKReceiptInfoKeyInAppProductID] isEqualToString:featureId]) {
                        result = YES;
                        *stop = YES;
                    }
                }];
                return result;
            }
            
            if ([[self sharedManager] advancedValidation]) {
                return [[self sharedManager] advancedValidation](featureId);
            }
        }
    }

    return NO;
}

- (BOOL)isSubscriptionActive:(NSString *)featureId
{
    MKSKSubscriptionProduct *subscriptionProduct = [self.subscriptionProducts objectForKey:featureId];
    if (!subscriptionProduct.receipt) return NO;
    
    id jsonObject = [NSJSONSerialization JSONObjectWithData:subscriptionProduct.receipt options:NSJSONReadingAllowFragments error:nil];
    NSData *receiptData = [NSData dataFromBase64String:[jsonObject objectForKey:@"latest_receipt"]];
    
    NSPropertyListFormat plistFormat;
    NSDictionary *payloadDict = [NSPropertyListSerialization propertyListWithData:receiptData
                                                                          options:NSPropertyListImmutable
                                                                           format:&plistFormat
                                                                            error:nil];
    
    receiptData = [NSData dataFromBase64String:[payloadDict objectForKey:@"purchase-info"]];
    
    NSDictionary *receiptDict = [NSPropertyListSerialization propertyListWithData:receiptData
                                                                          options:NSPropertyListImmutable
                                                                           format:&plistFormat
                                                                            error:nil];
    
    NSTimeInterval expiresDate = [[receiptDict objectForKey:@"expires-date"] doubleValue]/1000.0f;
    return expiresDate > [[NSDate date] timeIntervalSince1970];
}

// Call this function to populate your UI
// this function automatically formats the currency based on the user's locale
- (NSMutableArray *)purchasableObjectsDescription
{
	NSMutableArray *productDescriptions = [[NSMutableArray alloc] initWithCapacity:[self.purchasableObjects count]];
    [self.purchasableObjects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        SKProduct *product = obj;
        
        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
        [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
        [numberFormatter setLocale:product.priceLocale];
        NSString *formattedString = [numberFormatter stringFromNumber:product.price];
        
        // you might probably need to change this line to suit your UI needs
        NSString *description = [NSString stringWithFormat:@"%@ (%@)",[product localizedTitle], formattedString];
        
#ifdef DEBUG
        NSLog(@"MK:Product %ld - %@", idx, description);
#endif
        [productDescriptions addObject: description];
        
    }];

	return productDescriptions;
}

/*Call this function to get a dictionary with all prices of all your product identifers

 For example,
 `
 NSDictionary *prices = [[MKStoreManager sharedManager] pricesDictionary];
 NSString *upgradePrice = [prices objectForKey:@"com.mycompany.upgrade"]
 `
 */
- (NSMutableDictionary *)pricesDictionary
{
    NSMutableDictionary *priceDict = [NSMutableDictionary dictionary];
    if ([MKStoreKitConfigs isReviewAllowed]) {
        [self.purchasableObjects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [priceDict setObject:@"Preview" forKey:obj];
        }];
    } else {
        [self.purchasableObjects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            SKProduct *product = obj;
            
            NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
            [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
            [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
            [numberFormatter setLocale:product.priceLocale];
            NSString *formattedString = [numberFormatter stringFromNumber:product.price];
            
            NSString *priceString = [NSString stringWithFormat:@"%@", formattedString];
            [priceDict setObject:priceString forKey:product.productIdentifier];
        }];
    }
    return priceDict;
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message
{
#if TARGET_OS_IPHONE
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:NSLocalizedString(@"Dismiss", @"")
                                          otherButtonTitles:nil];
    [alert show];
#elif TARGET_OS_MAC
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:NSLocalizedString(@"Ok", @"")];
    
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert setAlertStyle:NSInformationalAlertStyle];
    
    [alert runModal];
    
#endif
}

- (void)buyFeature:(NSString *)featureId
        onComplete:(void (^)(NSString *, NSData *, NSArray *))completionBlock
       onCancelled:(void (^)(NSError *e))cancelBlock
{
    self.onTransactionCompleted = completionBlock;
    self.onTransactionCancelled = cancelBlock;
    
    [MKSKProduct verifyProductForReviewAccess:featureId onComplete:^(NSNumber * isAllowed) {
        if ([isAllowed boolValue]) {
            [self showAlertWithTitle:NSLocalizedString(@"Application review request successfully approved.", @"")
                             message:NSLocalizedString(@"You may now review Vox for a limited time with all the paid features enabled.", @"")];
            
            if(self.onTransactionCompleted) {
                self.onTransactionCompleted(featureId, nil, nil);
            }
        } else {
            if ([MKStoreKitConfigs isReviewAllowed]) {
                [MKSKProduct requestProductPreview:featureId];
                if (cancelBlock) {
                    cancelBlock(nil);
                }
            } else {
                [self addToQueue:featureId];
            }
        }
        
    } onError:^(NSError *error) {
        NSLog(@"Review request cannot be checked now: %@", [error description]);
        if ([MKStoreKitConfigs isReviewAllowed]) {
            [MKSKProduct requestProductPreview:featureId];
            if (cancelBlock) {
                cancelBlock(nil);
            }
        } else {
            [self addToQueue:featureId];
        }
    }];
}

- (void)redeemFeature:(NSString *)featureId withCode:(NSString *)code forUser:(NSString *)name withEmail:(NSString *)email
           onComplete:(void (^)(NSString *purchasedFeature, NSData *purchasedReceipt, NSArray *availableDownloads))completionBlock
          onCancelled:(void (^)(NSError *e))cancelBlock;
{
    NSDictionary *userInfo = @{
                               @"email" : email ? email : @"",
                               @"name" : name ? name : @""
                               };
    [MKSKProduct redeemProduct:featureId withCode:code userInfo:userInfo onComplete:^(NSDictionary *receipt, NSString *signature) {
        if (completionBlock) {
            // Validate receipt data
            if ([self verifySignature:[NSData dataFromBase64String:signature] data:[NSJSONSerialization dataWithJSONObject:receipt options:0 error:NULL]])
            {
                NSData *receiptData = [NSJSONSerialization dataWithJSONObject:@{
                                       @"type" : @"redeem",
                                       @"receipt" : receipt,
                                       @"signature" : signature
                                       } options:0 error:NULL];
                
                [self rememberPurchaseOfProduct:featureId withReceipt:receiptData];
                completionBlock(featureId, receiptData, nil);
            } else {
                NSLog(@"MKStore Signature validation error");
                if (cancelBlock) {
                    cancelBlock([NSError errorWithDomain:kMKStoreErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey : @"MKStore Signature validation error"}]);
                }
            }
        }
    } onError:^(NSError *e) {
        
        if (cancelBlock) {
            cancelBlock(e);
        }
    }];
}


- (void)activateFeature:(NSString *)featureId
      withLicenseNumber:(NSString *)licenseNumber
             onComplete:(void (^)(NSString *purchasedFeature, NSData *purchasedReceipt))completionBlock
            onCancelled:(void (^)(NSError *e))cancelBlock
{
    [MKSKProduct activateProduct:(NSString *)featureId
               withLicenseNumber:(NSString *)licenseNumber
                      onComplete:^(NSDictionary *receipt, NSString *signature) {
                          
        if (completionBlock) {
            // Validate receipt data
            
            NSString *receiptString = [NSString stringWithFormat:@"%@%@", receipt[@"productid"], receipt[@"hwid"]];
            
            if ([self verifySignature:[NSData dataFromBase64String:signature]
                                 data:[receiptString dataUsingEncoding:NSUTF8StringEncoding]]) {
                
                NSData *receiptData = [NSJSONSerialization dataWithJSONObject:@{
                                                                                @"type" : @"activationByLicense",
                                                                                @"receipt" : receipt,
                                                                                @"signature" : signature
                                                                                } options:0 error:NULL];
                
                [self rememberPurchaseOfProduct:featureId withReceipt:receiptData];
                
                completionBlock(featureId, receiptData);
            } else {
                NSLog(@"MKStore Signature validation error");
                if (cancelBlock) {
                    cancelBlock([NSError errorWithDomain:kMKStoreErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey : @"MKStore Signature validation error"}]);
                }
            }
        }
    } onError:^(NSError *e) {
        if (cancelBlock) {
            cancelBlock(e);
        }
    }];
}

- (void)addToQueue:(NSString *)productId
{
    if ([SKPaymentQueue canMakePayments]) {
        NSArray *allIds = [self.purchasableObjects valueForKey:@"productIdentifier"];
        NSUInteger index = [allIds indexOfObject:productId];
        
        if(index != NSNotFound) {
            SKProduct *thisProduct = [self.purchasableObjects objectAtIndex:index];
            SKPayment *payment = [SKPayment paymentWithProduct:thisProduct];
            [[SKPaymentQueue defaultQueue] addPayment:payment];
        }
	} else {
        [self showAlertWithTitle:NSLocalizedString(@"In-App Purchasing disabled", @"")
                         message:NSLocalizedString(@"Check your parental control settings and try again later", @"")];
	}
}

// ---------------------------------------------------------------------------------------------------------
// Conusmeable products
// ---------------------------------------------------------------------------------------------------------
- (BOOL)canConsumeProduct:(NSString *)productIdentifier
{
	return ([[MKStoreManager numberForKey:productIdentifier] intValue] > 0);
}

- (BOOL)canConsumeProduct:(NSString *)productIdentifier quantity:(int)quantity
{
	return ([[MKStoreManager numberForKey:productIdentifier] intValue] >= quantity);
}

- (BOOL)consumeProduct:(NSString *)productIdentifier quantity:(int)quantity
{
	int count = [[MKStoreManager numberForKey:productIdentifier] intValue];
	if(count < quantity) {
		return NO;
	} else {
		count -= quantity;
        [MKStoreManager setObject:[NSNumber numberWithInt:count] forKey:productIdentifier];
		return YES;
	}
}

// ---------------------------------------------------------------------------------------------------------
// Subscriptions
// ---------------------------------------------------------------------------------------------------------
- (void)startVerifyingSubscriptionReceipts
{
    NSDictionary *subscriptions = [[MKStoreManager storeKitItems] objectForKey:@"Subscriptions"];
    self.subscriptionProducts = [NSMutableDictionary dictionary];
    
    [subscriptions enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *productId = key;
        MKSKSubscriptionProduct *product = [[MKSKSubscriptionProduct alloc] initWithProductId:productId subscriptionDays:[[subscriptions objectForKey:productId] intValue]];
        
        product.receipt = [MKStoreManager dataForKey:productId]; // cached receipt
        if (product.receipt) {
            [product verifyReceiptOnComplete:^(NSNumber* isActive) {
                if([isActive boolValue] == NO) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:kSubscriptionsInvalidNotification
                                                                        object:product.productId];
                    
                    NSLog(@"Subscription: %@ is inactive", product.productId);
                    product.receipt = nil;
                    [self.subscriptionProducts setObject:product forKey:productId];
                    [MKStoreManager setObject:nil forKey:product.productId];

                } else {
                    NSLog(@"Subscription: %@ is active", product.productId);
                }
            } onError:^(NSError* error){
                NSLog(@"Unable to check for subscription validity right now");
            }];
        }
        
        [self.subscriptionProducts setObject:product forKey:productId];
        
    }];
}

- (NSData *)receiptFromBundle
{
    return  [NSData dataWithContentsOfURL:[[NSBundle mainBundle] appStoreReceiptURL]];
}

#if defined(__IPHONE_6_0) || defined(NSFoundationVersionNumber10_7_4)
- (void)hostedContentDownloadStatusChanged:(NSArray*) hostedContents {
    if (NSClassFromString(@"SKDownload")) {
        __block SKDownload *thisHostedContent = nil;
        
        NSMutableArray *itemsToBeRemoved = [NSMutableArray array];
        [hostedContents enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            
            thisHostedContent = obj;
            
            [self.hostedContents enumerateObjectsUsingBlock:^(id obj1, NSUInteger idx1, BOOL *stop1) {
                
                SKDownload *download = obj1;
                if([download.contentIdentifier isEqualToString:thisHostedContent.contentIdentifier]) {
                    [itemsToBeRemoved addObject:obj1];
                }
            }];
        }];
        
        [self.hostedContents removeObjectsInArray:itemsToBeRemoved];
        [self.hostedContents addObjectsFromArray:hostedContents];
        
        if(self.hostedContentDownloadStatusChangedHandler)
            self.hostedContentDownloadStatusChangedHandler(self.hostedContents);
        
        // Finish any completed downloads
        [hostedContents enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            SKDownload *download = obj;
#if TARGET_OS_IPHONE
            switch (download.downloadState) {
                case SKDownloadStateFinished:
#ifdef DEBUG
                    NSLog(@"MK:Download finished: %@", [download description]);
#endif
                    [self provideContent:download.transaction.payment.productIdentifier
                              forReceipt:download.transaction.transactionReceipt
                           hostedContent:[NSArray arrayWithObject:download]];
                    
                    [[SKPaymentQueue defaultQueue] finishTransaction:download.transaction];
                    break;
                default:
                    break;
            }
#elif TARGET_OS_MAC
            switch (download.state) {
                case SKDownloadStateFinished:
                    NSLog(@"Download finished: %@", [download description]);
                    [self provideContent:download.contentIdentifier
                              forReceipt:[self receiptFromBundle]
                           hostedContent:[NSArray arrayWithObject:download]];
                    
                    break;
                default:
                    break;
            }
#endif
        }];
    }
}
#endif

#pragma mark - In-App purchases callbacks
// In most cases you don't have to touch these methods
- (void)provideContent:(NSString *)productIdentifier forReceipt:(NSData *)receiptData hostedContent:(NSArray *)hostedContent
{
    MKSKSubscriptionProduct *subscriptionProduct = [self.subscriptionProducts objectForKey:productIdentifier];
    if(subscriptionProduct) {
        subscriptionProduct.receipt = receiptData;
        if (MKStoreKitConfigs.shouldCheckSubscriptionOnAppleServer) {
            [subscriptionProduct verifyReceiptOnComplete:^(NSNumber* isActive) {
                [[NSNotificationCenter defaultCenter] postNotificationName:kSubscriptionsPurchasedNotification object:productIdentifier];
                
                [MKStoreManager setObject:receiptData forKey:productIdentifier];
                if (self.onTransactionCompleted) {
                    self.onTransactionCompleted(productIdentifier, receiptData, hostedContent);
                }
                if (self.onRestoreCompleted)
                    [self restoreCompleted];
                
            } onError:^(NSError* error) {
                NSLog(@"%@", [error description]);
            }];
        } else {
            [MKStoreManager setObject:receiptData forKey:productIdentifier];
            if (self.onTransactionCompleted) {
                self.onTransactionCompleted(productIdentifier, receiptData, hostedContent);
            }
            if (self.onRestoreCompleted)
                [self restoreCompleted];
        }
    } else {
        if (!receiptData) {
            // Could be a mac in app receipt. Read from receipts and verify here
            receiptData = [self receiptFromBundle];
            if (!receiptData) {
                if(self.onTransactionCancelled) {
                    self.onTransactionCancelled([NSError errorWithDomain:kMKStoreErrorDomain code:-102 userInfo:@{
                                               NSLocalizedDescriptionKey: @"Unable to retrive store receipt data"
                                        }]);
                } else if (self.onRestoreFailed) {
                    [self restoreFailedWithError:[NSError errorWithDomain:kMKStoreErrorDomain code:-102 userInfo:@{
                                               NSLocalizedDescriptionKey: @"Unable to retrive store receipt data"
                                               }]];
                    
                } else {
                    NSLog(@"Receipt invalid");
                }
            }
        }
        
        // ping server and get response before serializing the product
        // this is a blocking call to post receipt data to your server
        // it should normally take a couple of seconds on a good 3G connection
        if (MKStoreKitConfigs.ownServerURL && MKStoreKitConfigs.isServerProductModel) {
            MKSKProduct *thisProduct = [[MKSKProduct alloc] initWithProductId:productIdentifier receiptData:receiptData];
            
            [thisProduct verifyReceiptOnComplete:^{
                NSString *signature = [NSString stringWithFormat:@"%@.%@.%@", [[NSBundle mainBundle] bundleIdentifier], productIdentifier, MKStoreKitConfigs.deviceId];
                signature = [self MD5StringForString:signature];
                NSData *newReceiptData = [NSJSONSerialization dataWithJSONObject:@{
                                          @"type" : @"store",
                                          @"signature" : signature
                                          } options:0 error:NULL];
                
                [self rememberPurchaseOfProduct:productIdentifier withReceipt:newReceiptData];
                if (self.onTransactionCompleted)
                    self.onTransactionCompleted(productIdentifier, receiptData, hostedContent);
                if (self.onRestoreCompleted)
                    [self restoreCompleted];
            } onError:^(NSError* error) {
                if(self.onTransactionCancelled) {
                    self.onTransactionCancelled(error);
                } else if (self.onRestoreFailed) {
                    [self restoreFailedWithError:error];
                } else {
                    NSLog(@"The receipt could not be verified");
                }
            }];
        } else {
            NSString *signature = [NSString stringWithFormat:@"%@.%@.%@", [[NSBundle mainBundle] bundleIdentifier], productIdentifier, MKStoreKitConfigs.deviceId];
            signature = [self MD5StringForString:signature];
            NSData *newReceiptData = [NSJSONSerialization dataWithJSONObject:@{
                                      @"type" : @"store",
                                      @"signature" : signature
                                      } options:0 error:NULL];
            [self rememberPurchaseOfProduct:productIdentifier withReceipt:newReceiptData];
            if (self.onTransactionCompleted) {
                self.onTransactionCompleted(productIdentifier, receiptData, hostedContent);
            } else if (self.onRestoreCompleted)
                [self restoreCompleted];
        }
    }
}


- (void)rememberPurchaseOfProduct:(NSString *)productIdentifier withReceipt:(NSData *)receiptData
{
    NSDictionary *allConsumables = [[MKStoreManager storeKitItems] objectForKey:@"Consumables"];
    if ([[allConsumables allKeys] containsObject:productIdentifier]) {
       
        NSDictionary *thisConsumableDict = [allConsumables objectForKey:productIdentifier];
        int quantityPurchased = [[thisConsumableDict objectForKey:@"Count"] intValue];
        NSString* productPurchased = [thisConsumableDict objectForKey:@"Name"];
        
        int oldCount = [[MKStoreManager numberForKey:productPurchased] intValue];
        int newCount = oldCount + quantityPurchased;
        
        [MKStoreManager setObject:[NSNumber numberWithInt:newCount] forKey:productPurchased];
    } else {
        [MKStoreManager setObject:[NSNumber numberWithBool:YES] forKey:productIdentifier];
    }
    
    [MKStoreManager setObject:receiptData forKey:[NSString stringWithFormat:@"%@-receipt", productIdentifier]];
}

#pragma mark - Store Observer
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
	for (SKPaymentTransaction *transaction in transactions) {
		switch (transaction.transactionState) {
			case SKPaymentTransactionStatePurchased:    [self completeTransaction:transaction]; break;
            case SKPaymentTransactionStateFailed:       [self failedTransaction:transaction]; break;
            case SKPaymentTransactionStateRestored:     [self restoreTransaction:transaction]; break;
            default: break;
		}
	}
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    [self restoreFailedWithError:error];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
//    [self restoreCompleted];
}

- (void)failedTransaction: (SKPaymentTransaction *)transaction
{
    
#ifdef DEBUG
    NSLog(@"MK:Failed transaction: %@", [transaction description]);
    NSLog(@"MK:Error: %@", transaction.error);
#endif
	
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
    
    if(self.onTransactionCancelled)
        self.onTransactionCancelled(transaction.error);
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction
{
#if TARGET_OS_IPHONE
    
    NSArray *downloads = nil;
    
#ifdef __IPHONE_6_0
    
    if([transaction respondsToSelector:@selector(downloads)])
        downloads = transaction.downloads;
    
    if([downloads count] > 0) {
        
        [[SKPaymentQueue defaultQueue] startDownloads:transaction.downloads];
        // We don't have content yet, and we can't finish the transaction
#ifdef DEBUG
        NSLog(@"MK:Download(s) started: %@", [transaction description]);
#endif
        return;
    }
#endif
    
    [self provideContent:transaction.payment.productIdentifier
              forReceipt:transaction.transactionReceipt
           hostedContent:downloads];
#elif TARGET_OS_MAC
    [self provideContent:transaction.payment.productIdentifier
              forReceipt:nil
           hostedContent:nil];
#endif
    
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}

- (void)restoreTransaction:(SKPaymentTransaction *)transaction
{
    
#if TARGET_OS_IPHONE
    NSArray *downloads = nil;
    
#ifdef __IPHONE_6_0
    
    if([transaction respondsToSelector:@selector(downloads)])
        downloads = transaction.downloads;
    if([downloads count] > 0) {
        
        [[SKPaymentQueue defaultQueue] startDownloads:transaction.downloads];
        // We don't have content yet, and we can't finish the transaction
#ifdef DEBUG
        NSLog(@"MK:Download(s) started: %@", [transaction description]);
#endif
        return;
    }
#endif
    
    [self provideContent: transaction.originalTransaction.payment.productIdentifier
              forReceipt:transaction.transactionReceipt
           hostedContent:downloads];
#elif TARGET_OS_MAC
    [self provideContent: transaction.originalTransaction.payment.productIdentifier
              forReceipt:nil
           hostedContent:nil];
#endif
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}

#ifdef __IPHONE_6_0
- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray *)downloads
{
    [self hostedContentDownloadStatusChanged:downloads];
}
#endif

@end
