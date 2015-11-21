//
//  MKSKProduct.m
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

#import "MKSKProduct.h"
#import "AFHTTPClient.h"
#import "AFJSONRequestOperation.h"

#import "NSData+MKBase64.h"

#if ! __has_feature(objc_arc)
#error MKStoreKit is ARC only. Either turn on ARC for the project or use -fobjc-arc flag
#endif

static NSString * const kMKStoreErrorDomain = @"MKStoreKitErrorDomain";

@implementation MKSKProduct
{
    AFHTTPClient *_serverClient;
}

- (id)initWithProductId:(NSString *)aProductId receiptData:(NSData *)aReceipt
{
    if ((self = [super init])) {
        self.productId = aProductId;
        self.receipt = aReceipt;
        if (MKStoreKitConfigs.ownServerURL && MKStoreKitConfigs.isServerProductModel) {
            _serverClient = [AFHTTPClient clientWithBaseURL:MKStoreKitConfigs.ownServerURL];
            [_serverClient registerHTTPOperationClass:[AFJSONRequestOperation class]];
            [_serverClient setDefaultHeader:@"Accept" value:@"application/json;"];
            [_serverClient setParameterEncoding:AFFormURLParameterEncoding];
        }
    }
    return self;
}

#pragma mark -
#pragma mark In-App purchases promo codes support
// This function is only used if you want to enable in-app purchases for free for reviewers
// Read my blog post http://mk.sg/31

+ (void)verifyProductForReviewAccess:(NSString *)productId
                          onComplete:(void (^)(NSNumber *))completionBlock
                             onError:(void (^)(NSError *))errorBlock
{
    if(MKStoreKitConfigs.isReviewAllowed) {
        
        AFHTTPClient *client = [AFHTTPClient clientWithBaseURL:[MKStoreKitConfigs.ownServerURL URLByAppendingPathComponent:@"featureCheck.php"]];
        [client setParameterEncoding:AFFormURLParameterEncoding];
        
        [client postPath:nil parameters:@{@"productid" : productId, @"udid" : MKStoreKitConfigs.deviceId} success:^(AFHTTPRequestOperation *operation, id responseObject) {
            if ([[operation responseString] rangeOfString:@"YES"].location != NSNotFound && completionBlock) {
                completionBlock(@YES);
            } else if (errorBlock) {
                errorBlock(nil);
            }
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            if (errorBlock) {
                errorBlock(error);
            }
        }];
    } else {
        completionBlock(@NO);
    }
}

+ (void)redeemProduct:(NSString *)productId
             withCode:(NSString *)code
             userInfo:(NSDictionary *)userInfo
           onComplete:(void (^)(NSDictionary *receipt, NSString *signature))completionBlock
              onError:(void (^)(NSError *))errorBlock
{
    if (MKStoreKitConfigs.ownServerURL && MKStoreKitConfigs.isRedeemAllowed) {
        AFHTTPClient *client = [AFHTTPClient clientWithBaseURL:[MKStoreKitConfigs.ownServerURL URLByAppendingPathComponent:@"redeemCode.php"]];
        [client registerHTTPOperationClass:[AFJSONRequestOperation class]];
        [client setDefaultHeader:@"Accept" value:@"application/json;"];
        [client setParameterEncoding:AFFormURLParameterEncoding];
        
        NSDictionary *params = @{
                                 @"productid" : productId,
                                 @"code" : code,
                                 @"hwid" : MKStoreKitConfigs.deviceId,
                                 @"email" : (userInfo && [userInfo valueForKey:@"email"]) ? userInfo[@"email"] : @"",
                                 @"name" : (userInfo && [userInfo valueForKey:@"name"]) ? userInfo[@"name"] : @""
                                 };

        [client postPath:nil parameters:params success:^(AFHTTPRequestOperation *operation, id responseObject) {
            if (responseObject && [responseObject valueForKey:@"result"] && [responseObject[@"result"] intValue] == 1) {
                if (completionBlock) {
                    completionBlock(responseObject[@"receipt"], responseObject[@"sign"]);
                }
            } else {
                NSError *error = [NSError errorWithDomain:kMKStoreErrorDomain code:-1 userInfo:nil];
                if (responseObject && [responseObject valueForKey:@"error"] && errorBlock) {
                    error = [NSError errorWithDomain:kMKStoreErrorDomain code:-3 userInfo:@{
                             NSLocalizedDescriptionKey : responseObject[@"error"]
                                }];
                }
                
                if (errorBlock) {
                    errorBlock(error);
                }
            }
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            if (errorBlock) {
                errorBlock(error);
            }
        }];
    } else if (errorBlock) {
        errorBlock([NSError errorWithDomain:kMKStoreErrorDomain code:-2 userInfo:@{NSLocalizedDescriptionKey : @"Redemption is not allowed or server is not set"}]);
    }
}

+ (void)activateProduct:(NSString *)productId
      withLicenseNumber:(NSString *)licenseNumber
           onComplete:(void (^)(NSDictionary *receipt, NSString *signature))completionBlock
              onError:(void (^)(NSError *))errorBlock
{
    if ([MKStoreKitConfigs paymentServerURL] && MKStoreKitConfigs.isActivationWithLicenseNumberAllowed) {
        AFHTTPClient *client = [AFHTTPClient clientWithBaseURL:[[MKStoreKitConfigs paymentServerURL] URLByAppendingPathComponent:@"activate-product"]];
        [client registerHTTPOperationClass:[AFJSONRequestOperation class]];
        [client setDefaultHeader:@"Accept" value:@"application/json;"];
        [client setParameterEncoding:AFFormURLParameterEncoding];
        
        NSDictionary *params = @{
                                 @"productid" : productId,
                                 @"licenseNumber" : licenseNumber,
                                 @"hwid" : MKStoreKitConfigs.deviceId,
                                };
        
        [client postPath:nil parameters:params success:^(AFHTTPRequestOperation *operation, id responseObject) {
            if (responseObject && [responseObject valueForKey:@"result"] && [responseObject[@"result"] intValue] == 1) {
                if (completionBlock) {
                    completionBlock(responseObject[@"receipt"], responseObject[@"sign"]);
                }
            } else {
                NSError *error = [NSError errorWithDomain:kMKStoreErrorDomain code:-10 userInfo:nil];
                if (responseObject && [responseObject valueForKey:@"error"] && errorBlock) {
                    error = [NSError errorWithDomain:kMKStoreErrorDomain code:-30 userInfo:@{
                                                                                            NSLocalizedDescriptionKey : responseObject[@"error"]
                                                                                            }];
                }
                
                if (errorBlock) {
                    errorBlock(error);
                }
            }
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            if (errorBlock) {
                errorBlock(error);
            }
        }];
    } else if (errorBlock) {
        errorBlock([NSError errorWithDomain:kMKStoreErrorDomain code:-20 userInfo:@{NSLocalizedDescriptionKey : @"Activation is not allowed or server is not set"}]);
    }
}

+ (void)requestProductPreview:(NSString *)productId;
{
    NSURL *url = [MKStoreKitConfigs ownServerURL];
    url = [NSURL URLWithString:[[url absoluteString] stringByAppendingFormat:@"openRequestPage.php?productid=%@&hwid=%@", productId,[MKStoreKitConfigs deviceId]]];
    
    [[NSWorkspace sharedWorkspace] openURL:url];
    
}

- (void)verifyReceiptOnComplete:(void (^)(void))completionBlock onError:(void (^)(NSError *))errorBlock
{
    NSString *receiptData = [self.receipt base64EncodedString];
    if (!receiptData) {
        if (errorBlock) {
            NSError *error = [NSError errorWithDomain:kMKStoreErrorDomain
                                                 code:-10
                                             userInfo:@{NSLocalizedDescriptionKey:@"Receipt not found"}];
            errorBlock(error);
        }
        return;
    }
    [_serverClient postPath:[[MKStoreKitConfigs.ownServerURL path] stringByAppendingPathComponent:@"verifyProduct.php"]
                 parameters:@{ @"receiptdata" : receiptData}
                    success:^(AFHTTPRequestOperation *operation, id responseObject) {

        if (responseObject && [[responseObject valueForKey:@"result"] intValue] == 1) {
            if (completionBlock) {
                completionBlock();
            }
        } else {
            NSError *error = [NSError errorWithDomain:kMKStoreErrorDomain code:-1 userInfo:nil];
            if (responseObject && [[responseObject valueForKey:@"result"] intValue] == 0 && [responseObject valueForKey:@"error"]) {
                error = [NSError errorWithDomain:error.domain code:error.code userInfo:@{NSLocalizedDescriptionKey: [responseObject valueForKey:@"error"]}];
            }
            
            if (errorBlock) {
                errorBlock(error);
            }
        }
     
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (errorBlock) {
            errorBlock(error);
        }
    }];
}

@end
