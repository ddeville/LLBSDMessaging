//
//  LLBSDMessage.m
//  LLBSDMessaging
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "LLBSDMessage.h"

@implementation LLBSDMessage

+ (instancetype)messageWithName:(NSString *)name userInfo:(NSDictionary *)userInfo
{
    NSParameterAssert(name);
    
    LLBSDMessage *message = [[LLBSDMessage alloc] init];
    message.name = name;
    message.userInfo = userInfo;
    return message;
}

@end
