//
//  LLBSDMessage.h
//  LLBSDMessaging
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LLBSDMessage : NSObject

/*!
    \brief
    A message that can be sent through a `LLBSDConnection`.

    \param name
    Required. The name that identifies the message.
    
    \param userInfo
    Optional. A dictionary containing extra information. Keys and values need to conform to `NSSecureCoding`.
 */
+ (instancetype)messageWithName:(NSString *)name userInfo:(NSDictionary *)userInfo;

/*!
    \brief
    Required. The name that identifies the message.
 */
@property (copy, nonatomic) NSString *name;

/*!
    \brief
    Optional. A dictionary containing extra information. Keys and values need to conform to `NSSecureCoding`.
 */
@property (strong, nonatomic) NSDictionary *userInfo;

@end
