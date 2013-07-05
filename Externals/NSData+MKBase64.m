//
//  NSData+MKNKBase64.m
//  base64
//
//  Created by Matt Gallagher on 2009/06/03.
//  Copyright 2009 Matt Gallagher. All rights reserved.
//
//  This software is provided 'as-is', without any express or implied
//  warranty. In no event will the authors be held liable for any damages
//  arising from the use of this software. Permission is granted to anyone to
//  use this software for any purpose, including commercial applications, and to
//  alter it and redistribute it freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source
//     distribution.
//

#import "NSData+MKBase64.h"

@implementation NSData (MKNKBase64)

+ (NSData *)dataFromBase64String:(NSString *)aString
{
    __block CFDataRef decodedData = NULL;
    __block SecTransformRef decoder = NULL;
    __block CFErrorRef error = NULL;
    
    BOOL(^passNextPhase)(CFErrorRef) = ^(CFErrorRef error){
        if (error) {
#ifdef DEBUG
            CFShow(error);
#endif
            if (decoder) CFRelease(decoder);
            if (decodedData) CFRelease(decodedData);
            
            return NO;
        }
        return YES;
    };
    
    /* Create the transform objects */
    decoder = SecDecodeTransformCreate(kSecBase64Encoding, &error);
    if (!passNextPhase(error)) {
        return nil;
    }
    
    /* Tell the decode transform to get its input from the
     encodedData object. */
    if (SecTransformSetAttribute(decoder, kSecTransformInputAttributeName, (__bridge CFDataRef)[aString dataUsingEncoding:NSUTF8StringEncoding], &error)
        && !passNextPhase(error)) {
        CFRelease(error);
        return nil;
    }
    
    /* Execute the decode transform. */
    decodedData = SecTransformExecute(decoder, &error);
    if (!passNextPhase(error)) {
        CFRelease(error);
        return nil;
    }
    
    CFRelease(decoder);
    NSData *data = (__bridge NSData *)decodedData;
    return data;
}

- (NSString *)base64EncodedString
{
    __block CFDataRef encodedData = NULL;
    __block SecTransformRef encoder = NULL;
    __block CFErrorRef error = NULL;
    BOOL(^passNextPhase)(CFErrorRef) = ^(CFErrorRef error){
        if (error) {
            if (encoder) CFRelease(encoder);
            if (encodedData) CFRelease(encodedData);
            
            return NO;
        }
        return YES;
    };
    
    /* Create the transform objects */
    encoder = SecEncodeTransformCreate(kSecBase64Encoding, &error);
    
    if (!passNextPhase(error)) {
        return nil;
    }
    
    /* Tell the encode transform to get its input from the
     sourceData object. */
    SecTransformSetAttribute(encoder, kSecTransformInputAttributeName, (__bridge CFDataRef)self, &error);
    if (!passNextPhase(error)) {
        CFRelease(error);
        return nil;
    }
    
    /* Execute the encode transform. */
    encodedData = SecTransformExecute(encoder, &error);
    
    if (!passNextPhase(error)) {
        CFRelease(error);
        return nil;
    }
    
    CFRelease(encoder);
    NSData *data = (__bridge NSData *)encodedData;
    NSString *base64String = [NSString stringWithUTF8String:[data bytes]];
    
    return base64String;
}

@end
