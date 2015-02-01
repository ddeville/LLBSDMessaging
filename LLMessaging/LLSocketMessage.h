//
//  LLSocketMessage.h
//  LLMessaging
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LLSocketMessage : NSObject

/*!
    \brief
 */
+ (instancetype)messageWithName:(NSString *)name userInfo:(NSDictionary *)userInfo;

/*!
    \brief
 */
@property (copy, nonatomic) NSString *name;

/*!
    \brief
 */
@property (strong, nonatomic) NSDictionary *userInfo;

@end
