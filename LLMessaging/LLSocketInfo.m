//
//  LLSocketConnectionInfo.m
//  LLMessaging
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "LLSocketInfo.h"

static NSString * const LLSocketInfoProcessNameKey = @"processName";
static NSString * const LLSocketInfoProcessIdentifierKey = @"processIdentifier";

@implementation LLSocketInfo

- (id)initWithProcessName:(NSString *)processName processIdentifier:(pid_t)processIdentifier
{
    self = [self init];
    if (self == nil) {
        return nil;
    }

    _processName = [processName copy];
    _processIdentifier = processIdentifier;

    return self;
}

#pragma mark - NSObject

- (BOOL)isEqual:(LLSocketInfo *)object
{
    if ([self class] != [object class]) {
        return NO;
    }
    if (![self.processName isEqualToString:object.processName]) {
        return NO;
    }
    if (!self.processIdentifier != object.processIdentifier) {
        return NO;
    }
    return YES;
}

- (NSUInteger)hash
{
    return (self.processName.hash ^ self.processIdentifier);
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
    return [[[self class] alloc] initWithProcessName:self.processName processIdentifier:self.processIdentifier];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    _processName = [decoder decodeObjectOfClass:[NSString class] forKey:LLSocketInfoProcessNameKey];
    _processIdentifier = [[decoder decodeObjectOfClass:[NSNumber class] forKey:LLSocketInfoProcessIdentifierKey] intValue];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:[self processName] forKey:LLSocketInfoProcessNameKey];
    [encoder encodeObject:@([self processIdentifier]) forKey:LLSocketInfoProcessIdentifierKey];
}

@end
