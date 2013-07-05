//
//  NSData+MKNKBase64.h
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

#import <Foundation/Foundation.h>

/** @name Work with Base64 data */
@interface NSData (MKNKBase64)

/* Creates an NSData object containing the base64 decoded representation of the base64 string 'aString'
 *    @param aString the base64 string to decode
 *    @return the autoreleased NSData representation of the base64 string */
+ (NSData *)dataFromBase64String:(NSString *)aString;

/* Creates an NSString object that contains the base 64 encoding of the receiver's data. Lines are broken at 64 characters long.
 *    @return an autoreleased NSString being the base 64 representation of the receiver. */
- (NSString *)base64EncodedString;

@end
