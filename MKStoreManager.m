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

static NSString *kMKReceiptInfoKeyInAppProductID               = @"in-app-id";
static NSString *kMKReceiptInfoKeyInAppTransactionID           = @"in-app-trx-id";
static NSString *kMKReceiptInfoKeyInAppOriginalTransactionID   = @"in-app-original-trx-id";
static NSString *kMKReceiptInfoKeyInAppPurchaseDate            = @"in-app-date";
static NSString *kMKReceiptInfoKeyInAppOriginalPurchaseDate    = @"in-app-original-date";
static NSString *kMKReceiptInfoKeyInAppQuantity                = @"in-app-qnt";
static NSString *kMKReceiptInfoKeyInAppPurchaseReceipt         = @"in-app-purchase-rctp";

inline static NSData *MKDecodeReceiptData(NSData *receiptData)
{
    CMSDecoderRef decoder = NULL;
    SecPolicyRef policyRef = NULL;
    SecTrustRef trustRef = NULL;
    
    @try {
        // Create a decoder
        OSStatus status = CMSDecoderCreate(&decoder);
        if (status) {
            [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to decode receipt data: Create a decoder", nil];
        }
        
        // Decrypt the message (1)
        status = CMSDecoderUpdateMessage(decoder, receiptData.bytes, receiptData.length);
        if (status) {
            [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to decode receipt data: Update message", nil];
        }
        
        // Decrypt the message (2)
        status = CMSDecoderFinalizeMessage(decoder);
        if (status) {
            [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to decode receipt data: Finalize message", nil];
        }
        
        // Get the decrypted content
        NSData *ret = nil;
        CFDataRef dataRef = NULL;
        status = CMSDecoderCopyContent(decoder, &dataRef);
        if (status) {
            [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to decode receipt data: Get decrypted content", nil];
        }
        ret = [NSData dataWithData:(__bridge NSData *)dataRef];
        CFRelease(dataRef);
        
        // Check the signature
        size_t numSigners;
        status = CMSDecoderGetNumSigners(decoder, &numSigners);
        if (status) {
            [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to check receipt signature: Get singer count", nil];
        }
        if (numSigners == 0) {
            [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to check receipt signature: No signer found", nil];
        }
        
        policyRef = SecPolicyCreateBasicX509();
        
        CMSSignerStatus signerStatus;
        OSStatus certVerifyResult;
        status = CMSDecoderCopySignerStatus(decoder, 0, policyRef, TRUE, &signerStatus, &trustRef, &certVerifyResult);
        if (status) {
            [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to check receipt signature: Get signer status", nil];
        }
        if (signerStatus != kCMSSignerValid) {
            [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to check receipt signature: No valid signer", nil];
        }
        
        return ret;
    } @catch (NSException *e) {
        @throw e;
    } @finally {
        if (policyRef) CFRelease(policyRef);
        if (trustRef) CFRelease(trustRef);
        if (decoder) CFRelease(decoder);
    }
}

inline static int MKGetIntValueFromASN1Data(const tMKASN1_Data *asn1Data)
{
    int ret = 0;
    for (int i = 0; i < asn1Data->length; i++) {
        ret = (ret << 8) | asn1Data->data[i];
    }
    return ret;
}

inline static NSNumber *MKDecodeIntNumberFromASN1Data(SecAsn1CoderRef decoder, tMKASN1_Data srcData)
{
    tMKASN1_Data asn1Data;
    OSStatus status = SecAsn1Decode(decoder, srcData.data, srcData.length, kSecAsn1IntegerTemplate, &asn1Data);
    if (status) {
        [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to get receipt information: Decode integer value", nil];
    }
    return [NSNumber numberWithInt:MKGetIntValueFromASN1Data(&asn1Data)];
}

inline static NSString *MKDecodeUTF8StringFromASN1Data(SecAsn1CoderRef decoder, tMKASN1_Data srcData)
{
    tMKASN1_Data asn1Data;
    OSStatus status = SecAsn1Decode(decoder, srcData.data, srcData.length, kSecAsn1UTF8StringTemplate, &asn1Data);
    if (status) {
        [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to get receipt information: Decode UTF-8 string", nil];
    }
    return [[NSString alloc] initWithBytes:asn1Data.data length:asn1Data.length encoding:NSUTF8StringEncoding];
}

inline static NSDate *MKDecodeDateFromASN1Data(SecAsn1CoderRef decoder, tMKASN1_Data srcData)
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-ddTHH:mm:ssZ"];
    
    tMKASN1_Data asn1Data;
    OSStatus status = SecAsn1Decode(decoder, srcData.data, srcData.length, kSecAsn1IA5StringTemplate, &asn1Data);
    if (status) {
        [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to get receipt information: Decode date (IA5 string)", nil];
    }
    
    NSString *dateStr = [[NSString alloc] initWithBytes:asn1Data.data length:asn1Data.length encoding:NSASCIIStringEncoding];
    return [dateFormatter dateFromString:dateStr];
}

inline static NSDictionary *MKGetReceiptPayload(NSData *payloadData)
{
    SecAsn1CoderRef asn1Decoder = NULL;
    @try {
        NSMutableDictionary *ret = [NSMutableDictionary dictionary];
        
        // Create the ASN.1 parser
        OSStatus status = SecAsn1CoderCreate(&asn1Decoder);
        if (status) {
            [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to get receipt information: Create ASN.1 decoder", nil];
        }
        
        // Decode the receipt payload
        tMKReceiptPayload payload = { NULL };
        status = SecAsn1Decode(asn1Decoder, payloadData.bytes, payloadData.length, kMKSetOfReceiptAttributeTemplate, &payload);
        if (status) {
            [NSException raise:@"MacAppStore Receipt Validation Error" format:@"Failed to get receipt information: Decode payload", nil];
        }
        
        // Fetch all attributes
        tMKReceiptAttribute *anAttr;
        for (int i = 0; (anAttr = payload.attrs[i]); i++) {
            int type = MKGetIntValueFromASN1Data(&anAttr->type);
            switch (type) {
                case kMKReceiptAttributeTypeInAppProductID:
                    [ret setValue:MKDecodeUTF8StringFromASN1Data(asn1Decoder, anAttr->value) forKey:kMKReceiptInfoKeyInAppProductID];
                    break;
                case kMKReceiptAttributeTypeInAppTransactionID:
                    [ret setValue:MKDecodeUTF8StringFromASN1Data(asn1Decoder, anAttr->value) forKey:kMKReceiptInfoKeyInAppTransactionID];
                    break;
                case kMKReceiptAttributeTypeInAppOriginalTransactionID:
                    [ret setValue:MKDecodeUTF8StringFromASN1Data(asn1Decoder, anAttr->value) forKey:kMKReceiptInfoKeyInAppOriginalTransactionID];
                    break;
                    
                    // Purchase Date (As IA5 String (almost identical to the ASCII String))
                case kMKReceiptAttributeTypeInAppPurchaseDate:
                    [ret setValue:MKDecodeDateFromASN1Data(asn1Decoder, anAttr->value) forKey:kMKReceiptInfoKeyInAppPurchaseDate];
                    break;
                case kMKReceiptAttributeTypeInAppOriginalPurchaseDate:
                    [ret setValue:MKDecodeDateFromASN1Data(asn1Decoder, anAttr->value) forKey:kMKReceiptInfoKeyInAppOriginalPurchaseDate];
                    break;
                    
                    // Quantity (Integer Value)
                case kMKReceiptAttributeTypeInAppQuantity:
                    [ret setValue:MKDecodeIntNumberFromASN1Data(asn1Decoder, anAttr->value)
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
                    NSDictionary *inAppInfo = MKGetReceiptPayload(inAppData);
                    [inAppPurchases addObject:inAppInfo];
                    break;
                }
                    
                    // Otherwise
                default:
                    break;
            }
        }
        return ret;
    } @catch (NSException *e) {
        @throw e;
    } @finally {
        if (asn1Decoder) SecAsn1CoderRelease(asn1Decoder);
    }
    
}

#endif

@interface MKStoreManager (/* private methods and properties */)

@property (nonatomic, copy) void (^onTransactionCancelled)();
@property (nonatomic, copy) void (^onTransactionCompleted)(NSString *productId, NSData* receiptData, NSArray* downloads);

@property (nonatomic, copy) void (^onRestoreFailed)(NSError* error);
@property (nonatomic, copy) void (^onRestoreCompleted)();

@property (nonatomic, assign, getter=isProductsAvailable) BOOL isProductsAvailable;

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
    NSLog(@"Updating from iCloud");
    
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
    if (NSClassFromString(@"NSUbiquitousKeyValueStore")) {      // is iOS 5?
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
        if ([SSKeychain setPassword:objectString forService:[self.class serviceName] account:key error:&error] && error) {
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
    if(error) {
        NSLog(@"%@", error);
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
    
	self.productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:productsArray]];
	self.productsRequest.delegate = self;
	[self.productsRequest start];
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
    
    @try {
        readStream		= CFReadStreamCreateWithBytesNoCopy (kCFAllocatorDefault, [data bytes], [data length], kCFAllocatorNull);
        readTransform	= SecTransformCreateReadTransformWithReadStream(readStream);
        
        if (!readTransform) {
            return -1;
        }
        
        verifierTransform = SecVerifyTransformCreate(MKStoreKitConfigs.publicKey, (__bridge CFDataRef)signature, NULL);
        
        if (!verifierTransform) {
            return -1;
        }
        
        // Set to a digest input
        status = SecTransformSetAttribute(verifierTransform, kSecInputIsDigest, kCFBooleanTrue, NULL);
        
        if (!status) {
            return -1;
        }
        
        // Set to a SHA1 digest input
        status = SecTransformSetAttribute(verifierTransform, kSecDigestTypeAttribute, kSecDigestSHA1, NULL);
        
        if (!status) {
            return -1;
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
        
        return status == true;
        
    }
    @catch (NSException *exception) {

    }
    @finally {
        if (verifierTransform) { CFRelease (verifierTransform); verifierTransform = NULL; } \
        if (group) { CFRelease (group); group = NULL; } \
        if (readStream) { CFRelease (readStream); readStream = NULL; } \
        if (readTransform) { CFRelease (readTransform); readTransform = NULL;} \
    }
    
}

#pragma mark - Delegation
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
	[self.purchasableObjects addObjectsFromArray:response.products];
	
#ifndef NDEBUG
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
    @try {
        if  ([[MKStoreManager numberForKey:featureId] boolValue]) {
            NSData *receiptData = [[MKStoreManager objectForKey:[NSString stringWithFormat:@"%@-receipt", featureId]] dataUsingEncoding:NSUTF8StringEncoding];
            
            // For redeem  could be JSON
            id jsonObject = receiptData ? [NSJSONSerialization JSONObjectWithData:receiptData options:0 error:NULL] : nil;
            
            if (jsonObject && [jsonObject isKindOfClass:[NSDictionary class]] && [jsonObject valueForKey:@"type"] && [jsonObject[@"type"] isEqualToString:@"redeem"]) {
                NSDictionary *receiptObject = jsonObject[@"receipt"];
                NSString *signature = jsonObject[@"signature"];
                
                BOOL validate = [receiptObject[@"hwid"] isEqualToString:MKStoreKitConfigs.deviceId];
                validate = validate && [receiptObject[@"product_id"] isEqualToString:featureId];
                validate = validate && [[MKStoreManager sharedManager] verifySignature:[NSData dataFromBase64String:signature] data:[NSJSONSerialization dataWithJSONObject:receiptObject options:0 error:NULL]];
                
                return validate;
            }
            
            // If this one from receipt - read receipt and validate it
            if (!receiptData)
            {
                NSData *payloadData = MKDecodeReceiptData([[self sharedManager] receiptFromBundle]);
                NSDictionary *inapps = MKGetReceiptPayload(payloadData);
                if (inapps && [inapps valueForKey:kMKReceiptInfoKeyInAppPurchaseReceipt])
                {
                    __block BOOL result = NO;
                    [inapps[kMKReceiptInfoKeyInAppPurchaseReceipt] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                        if ([[obj valueForKey:kMKReceiptInfoKeyInAppProductID] isEqualToString:featureId]) {
                            result = YES;
                            *stop = YES;
                        }
                    }];
                    
                    return result;
                }
            }
            
        }
        
    }
    @catch (NSException *exception) {
        NSLog(@"Error validate in-app internal error: %@", [exception reason]);
        
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
        
#ifndef NDEBUG
        NSLog(@"Product %ld - %@", idx, description);
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
    [alert addButtonWithTitle:NSLocalizedString(@"Dismiss", @"")];
    
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert setAlertStyle:NSInformationalAlertStyle];
    
    [alert runModal];
    
#endif
}

- (void)buyFeature:(NSString *)featureId
        onComplete:(void (^)(NSString *, NSData *, NSArray *))completionBlock
       onCancelled:(void (^)(void))cancelBlock
{
    self.onTransactionCompleted = completionBlock;
    self.onTransactionCancelled = cancelBlock;
    
    [MKSKProduct verifyProductForReviewAccess:featureId onComplete:^(NSNumber * isAllowed) {
        if ([isAllowed boolValue]) {
            [self showAlertWithTitle:NSLocalizedString(@"Review request approved", @"")
                             message:NSLocalizedString(@"You can use this feature for reviewing the app.", @"")];
            
            if(self.onTransactionCompleted) {
                self.onTransactionCompleted(featureId, nil, nil);
            }
        } else {
            [self addToQueue:featureId];
        }
        
    } onError:^(NSError *error) {
         NSLog(@"Review request cannot be checked now: %@", [error description]);
         [self addToQueue:featureId];
    }];
}

- (void)redeemFeature:(NSString *)featureId withCode:(NSString *)code forUser:(NSString *)name withEmail:(NSString *)email
           onComplete:(void (^)(NSString *purchasedFeature, NSData *purchasedReceipt, NSArray *availableDownloads))completionBlock
          onCancelled:(void (^)(void))cancelBlock;
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
                    cancelBlock();
                }
            }
        }
    } onError:^(NSError *e) {
        NSLog(@"Error to redeem(%@): %@", featureId, e);
        [self showAlertWithTitle:NSLocalizedString(@"In-App redemption problem", @"")
                         message:e.localizedDescription];
        
        if (cancelBlock) {
            cancelBlock();
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
#ifndef NDEBUG
                    NSLog(@"Download finished: %@", [download description]);
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
        [subscriptionProduct verifyReceiptOnComplete:^(NSNumber* isActive) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kSubscriptionsPurchasedNotification object:productIdentifier];
            
            [MKStoreManager setObject:receiptData forKey:productIdentifier];
            if (self.onTransactionCompleted) {
                self.onTransactionCompleted(productIdentifier, receiptData, hostedContent);
            }
        } onError:^(NSError* error) {
            NSLog(@"%@", [error description]);
        }];
    } else {
        if (!receiptData) {
            // Could be a mac in app receipt. Read from receipts and verify here
            receiptData = [self receiptFromBundle];
            if (!receiptData) {
                if(self.onTransactionCancelled) {
                    self.onTransactionCancelled(productIdentifier);
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
                [self rememberPurchaseOfProduct:productIdentifier withReceipt:receiptData];
                if (self.onTransactionCompleted)
                    self.onTransactionCompleted(productIdentifier, receiptData, hostedContent);
            } onError:^(NSError* error) {
                if(self.onTransactionCancelled) {
                    self.onTransactionCancelled(productIdentifier);
                } else {
                    NSLog(@"The receipt could not be verified");
                }
            }];
        } else {
            [self rememberPurchaseOfProduct:productIdentifier withReceipt:receiptData];
            if (self.onTransactionCompleted) {
                self.onTransactionCompleted(productIdentifier, receiptData, hostedContent);
            }
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
    [self restoreCompleted];
}

- (void)failedTransaction: (SKPaymentTransaction *)transaction
{
    
#ifndef NDEBUG
    NSLog(@"Failed transaction: %@", [transaction description]);
    NSLog(@"error: %@", transaction.error);
#endif
	
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
    
    if(self.onTransactionCancelled)
        self.onTransactionCancelled();
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
#ifndef NDEBUG
        NSLog(@"Download(s) started: %@", [transaction description]);
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
#ifndef NDEBUG
        NSLog(@"Download(s) started: %@", [transaction description]);
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
