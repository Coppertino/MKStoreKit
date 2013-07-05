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

- (id)initWithProductId:(NSString *)aProductId receiptData:(NSData *)aReceipt
{
    if ((self = [super init])) {
        self.productId = aProductId;
        self.receipt = aReceipt;
        if (OWN_SERVER && SERVER_PRODUCT_MODEL) {
            _serverClient = [AFHTTPClient clientWithBaseURL:OWN_SERVER];
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
    if(REVIEW_ALLOWED) {
        
        AFHTTPClient *client = [AFHTTPClient clientWithBaseURL:[OWN_SERVER URLByAppendingPathComponent:@"featureCheck.php"]];
        [client setParameterEncoding:AFFormURLParameterEncoding];
        
        [client postPath:nil parameters:@{@"productid" : productId, @"udid" : [self deviceId]} success:^(AFHTTPRequestOperation *operation, id responseObject) {
            if ([[responseObject description] rangeOfString:@"YES"].location != NSNotFound && completionBlock) {
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

+ (void)redeemProduct:(NSString *)productId withCode:(NSString *)code userInfo:(NSDictionary *)userInfo
           onComplete:(void (^)(NSDictionary *receipt, NSString *signature))completionBlock
              onError:(void (^)(NSError *))errorBlock;
{
    if (REDEEM_ALLOWED && OWN_SERVER) {
        AFHTTPClient *client = [AFHTTPClient clientWithBaseURL:[OWN_SERVER URLByAppendingPathComponent:@"redeemCode.php"]];
        [client registerHTTPOperationClass:[AFJSONRequestOperation class]];
        [client setDefaultHeader:@"Accept" value:@"application/json;"];
        [client setParameterEncoding:AFFormURLParameterEncoding];
        
        NSDictionary *params = @{
                                 @"productid" : productId,
                                 @"code" : code,
                                 @"hwid" : [self deviceId],
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
        errorBlock([NSError errorWithDomain:kMKStoreErrorDomain code:-2 userInfo:@{NSLocalizedDescriptionKey : @"Redemption no allowed or server not set"}]);
    }
}

- (void)verifyReceiptOnComplete:(void (^)(void))completionBlock onError:(void (^)(NSError *))errorBlock
{
    [_serverClient postPath:[[OWN_SERVER path] stringByAppendingPathComponent:@"verifyProduct.php"] parameters:@{ @"receiptdata" : [self.receipt base64EncodedString]} success:^(AFHTTPRequestOperation *operation, id responseObject) {

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
