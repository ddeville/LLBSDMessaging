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
    A class identifying a process that can send or receive messages on a `LLBSDConnection`.

    \param processName
    The name of the process as seen in the process table.

    \param processIdentifier
    The identifier of the process aka pid.
 */
- (instancetype)initWithProcessName:(NSString *)processName processIdentifier:(pid_t)processIdentifier;

/*!
    \brief
    The name of the process as seen in the process table.
 */
@property (readonly, copy, nonatomic) NSString *processName;

/*!
    \brief
    The identifier of the process aka pid.
 */
@property (readonly, assign, nonatomic) pid_t processIdentifier;

@end
