//
//  LLSocketConnectionInfo.m
//  LLMessaging
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "LLSocketInfo.h"

@implementation LLSocketInfo

- (id)initWithBundleIdentifier:(NSString *)bundleIdentifier processIdentifier:(pid_t)processIdentifier
{
    self = [self init];
    if (self == nil) {
        return nil;
    }

    _bundleIdentifier = [bundleIdentifier copy];
    _processIdentifier = processIdentifier;

    return self;
}

- (BOOL)isEqual:(LLSocketInfo *)object
{
    if ([self class] != [object class]) {
        return NO;
    }
    if (![self.bundleIdentifier isEqualToString:object.bundleIdentifier]) {
        return NO;
    }
    if (!self.processIdentifier != object.processIdentifier) {
        return NO;
    }
    return YES;
}

- (NSUInteger)hash
{
    return (self.bundleIdentifier.hash ^ self.processIdentifier);
}

@end
