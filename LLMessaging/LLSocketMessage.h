//
//  LLSocketMessage.h
//  LLMessaging
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LLSocketMessage : NSObject

+ (instancetype)messageWithName:(NSString *)name userInfo:(NSDictionary *)userInfo;

@property (copy, nonatomic) NSString *name;
@property (strong, nonatomic) NSDictionary *userInfo;

@end
