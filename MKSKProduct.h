//
//  MKSKProduct.h
//  MKStoreKit (Version 5.0)
//
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
#import "MKStoreKitConfigs.h"

@interface MKSKProduct : NSObject 

@property (nonatomic, strong) NSData *receipt;
@property (nonatomic, strong) NSString *productId;

/*!
 * Basic construtor
 * @param aProductId in-app id from itunes connect 
 * @param aReceipt receipt data
 * @retrun initialized instance
 */
- (id)initWithProductId:(NSString *)aProductId receiptData:(NSData *)aReceipt;

/*!
 * Class method that help to find out device id
 * @return device identificator
 */
+ (NSString *)deviceId;

/*!
 * Mehtod that will perform remove verification of receipt from Apple
 * @param completionBlock will be called when verification went well
 * @param errorBlock will be called when verification perform problem
 */
- (void)verifyReceiptOnComplete:(void (^)(void))completionBlock onError:(void (^)(NSError *))errorBlock;

#pragma mark - Helpers for server side verification
+ (void)verifyProductForReviewAccess:(NSString *)productId onComplete:(void (^)(NSNumber *))completionBlock onError:(void (^)(NSError *))errorBlock;
+ (void)redeemProduct:(NSString *)productId withCode:(NSString *)code userInfo:(NSDictionary *)userInfo onComplete:(void (^)(NSDictionary *receipt, NSString *signature))completionBlock onError:(void (^)(NSError *))errorBlock;

@end
