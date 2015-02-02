//
//  LLBSDMessaging-Constants.h
//  LLBSDMessaging
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const LLBSDMessagingBundleIdentifier;

extern NSString * const LLBSDMessagingErrorDomain;

typedef NS_ENUM(NSInteger, LLBSDMessagingErrorCode) {
    LLBSDMessagingUnknownError = 0,

    LLBSDMessagingEncodingError = -100,
    LLBSDMessagingDecodingError = -101,
    LLBSDMessagingInvalidChannelError = -102,
};

FOUNDATION_EXPORT double LLBSDMessagingVersionNumber;
FOUNDATION_EXPORT const unsigned char *LLBSDMessagingVersionString;