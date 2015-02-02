//
//  LLBSDConnectionInfo.h
//  LLBSDMessaging
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LLBSDProcessInfo : NSObject <NSSecureCoding, NSCopying>

/*!
    \brief
 */
- (id)initWithProcessName:(NSString *)processName processIdentifier:(pid_t)processIdentifier;

/*!
    \brief
 */
@property (readonly, copy, nonatomic) NSString *processName;

/*!
    \brief
 */
@property (readonly, assign, nonatomic) pid_t processIdentifier;

@end
