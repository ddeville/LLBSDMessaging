//
//  LLSocketConnectionInfo.h
//  LLMessaging
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LLSocketInfo : NSObject <NSSecureCoding, NSCopying>

- (id)initWithProcessName:(NSString *)processName processIdentifier:(pid_t)processIdentifier;

@property (readonly, copy, nonatomic) NSString *processName;
@property (readonly, assign, nonatomic) pid_t processIdentifier;

@end
