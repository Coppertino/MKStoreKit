//
//  MKStoreManager.h
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

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>
#import "MKStoreKitConfigs.h"

#ifdef DEBUG
#define kReceiptValidationURL @"https://sandbox.itunes.apple.com/verifyReceipt"
#else
#define kReceiptValidationURL @"https://buy.itunes.apple.com/verifyReceipt"
#endif

#define kProductFetchedNotification @"MKStoreKitProductsFetched"
#define kSubscriptionsPurchasedNotification @"MKStoreKitSubscriptionsPurchased"
#define kSubscriptionsInvalidNotification @"MKStoreKitSubscriptionsInvalid"

@interface MKStoreManager : NSObject<SKProductsRequestDelegate, SKPaymentTransactionObserver>


/**
 Shared instance
 */
+ (MKStoreManager*)sharedManager;

/**
 Check if feature purchased (is async when reviewAllowed = YES)
 
 @param     featureId   Feature name
 @returns   YES if feature is avaliable, NO otherwise
 */
+ (BOOL)isFeaturePurchased:(NSString*) featureId;

@property (nonatomic, strong) NSMutableArray *purchasableObjects;
@property (nonatomic, strong) NSMutableDictionary *subscriptionProducts;
/**
 Advanced validation block applied for MAS purchases stored in MAS signature
 */
@property (copy) BOOL (^advancedValidation)(NSString *featureId);

#if defined(__IPHONE_6_0) || defined(NSFoundationVersionNumber10_7_4)

@property (strong, nonatomic) NSMutableArray *hostedContents;
@property (nonatomic, copy) void (^hostedContentDownloadStatusChangedHandler)(NSArray* hostedContent);

#endif

/**
 Quick access method for avaliable product prices

 @returns Dictionary with prices like @"Radio" => @"0.99"
 */
- (NSMutableDictionary *)pricesDictionary;

/**
 Quick access method for avaliable product description
 
 @returns Array with descriptions like @"Radio (0.99)"
 */
- (NSMutableArray*) purchasableObjectsDescription;

/**
 Start purchase feature in MAS (in async mode)
 
 @param     featureId       Feature name
 @param     completionBlock Block to call on success
 @param     completionBlock Block to call when error or cancel
 */
- (void)buyFeature:(NSString *)featureId
        onComplete:(void (^)(NSString *, NSData *, NSArray *))completionBlock
       onCancelled:(void (^)(NSError *e))cancelBlock;


/**
 Start restoration of previous purchases (in async mode)
 
 @param     completionBlock Block to call on success
 @param     completionBlock Block to call when error or cancel
 */
- (void) restorePreviousTransactionsOnComplete:(void (^)(void)) completionBlock
                                       onError:(void (^)(NSError* error)) errorBlock;

/**
 Redeem feature for free access (in async mode)
 
 @param     featureId       Feature name
 @param     code            Redeem code (secret used for processing)
 @param     user            User name
 @param     email           User email
 @param     completionBlock Block to call on success
 @param     completionBlock Block to call when error or cancel
 */
- (void)redeemFeature:(NSString *)featureId withCode:(NSString *)code forUser:(NSString *)name withEmail:(NSString *)email
           onComplete:(void (^)(NSString *purchasedFeature, NSData *purchasedReceipt, NSArray *availableDownloads))completionBlock
          onCancelled:(void (^)(NSError *e))cancelBlock;

/**
 Activate feature after purchase outside MAS by license number (in async mode)
 
 @param     featureId       Feature name
 @param     licenseNumber   License number (secret used for processing)
 @param     completionBlock Block to call on success
 @param     completionBlock Block to call when error or cancel
 */
- (void)activateFeature:(NSString *)featureId
      withLicenseNumber:(NSString *)licenseNumber
             onComplete:(void (^)(NSString *purchasedFeature, NSData *purchasedReceipt))completionBlock
            onCancelled:(void (^)(NSError *e))cancelBlock;


// For consumable support
- (BOOL) canConsumeProduct:(NSString*) productName quantity:(int) quantity;
- (BOOL) consumeProduct:(NSString*) productName quantity:(int) quantity;
- (BOOL) isSubscriptionActive:(NSString*) featureId;

// for testing proposes you can use this method to remove all the saved keychain data (saved purchases, etc.)
- (BOOL) removeAllKeychainData;

// You wont' need this normally. MKStoreKit automatically takes care of remembering receipts.
// but in case you want the receipt data to be posted to your server, use this.
+ (id)receiptForKey:(NSString *)key;
+ (void)setObject:(id)object forKey:(NSString *)key;
+ (NSNumber *)numberForKey:(NSString *)key;

@end
