//
//  SpecialMessage.m
//  TestApp
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "SpecialMessage.h"

@implementation SpecialMessage

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [self init];
    if (self == nil) {
        return nil;
    }
    _title = [decoder decodeObjectForKey:@"title"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:self.title forKey:@"title"];
}

@end
