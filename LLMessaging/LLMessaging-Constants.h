//
//  LLMessaging-Constants.h
//  LLMessaging
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const LLMessagingBundleIdentifier;

extern NSString * const LLMessagingErrorDomain;

typedef NS_ENUM(NSInteger, LLMessagingErrorCode) {
    LLMessagingUnknownError = 0,
};

FOUNDATION_EXPORT double LLMessagingVersionNumber;
FOUNDATION_EXPORT const unsigned char *LLMessagingVersionString;