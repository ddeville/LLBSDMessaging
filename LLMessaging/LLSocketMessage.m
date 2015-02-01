//
//  LLSocketMessage.m
//  LLMessaging
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "LLSocketMessage.h"

@implementation LLSocketMessage

+ (instancetype)messageWithName:(NSString *)name userInfo:(NSDictionary *)userInfo
{
    LLSocketMessage *message = [[LLSocketMessage alloc] init];
    message.name = name;
    message.userInfo = userInfo;
    return message;
}

@end
