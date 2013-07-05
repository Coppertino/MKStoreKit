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
