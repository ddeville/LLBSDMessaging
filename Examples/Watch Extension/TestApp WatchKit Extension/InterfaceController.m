//
//  InterfaceController.m
//  TestApp WatchKit Extension
//
//  Created by Damien DeVille on 2/13/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "InterfaceController.h"

#import <LLBSDMessaging/LLBSDMessaging.h>

#import "InterfaceRow.h"
#import "Shared.h"

@interface InterfaceController() <LLBSDConnectionDelegate>

@property (strong, nonatomic) LLBSDConnectionClient *connection;

@property (strong, nonatomic) NSMutableArray *names;

@end

@implementation InterfaceController

- (id)init
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    self.names = [NSMutableArray array];
    
    LLBSDConnectionClient *connection = [[LLBSDConnectionClient alloc] initWithApplicationGroupIdentifier:kApplicationGroupIdentifier connectionIdentifier:kConnectionIdentifier];
    connection.delegate = self;
    self.connection = connection;
    
    return self;
}

- (void)awakeWithContext:(id)context
{
	[super awakeWithContext:context];
    
    [self _connect];
}

- (void)table:(WKInterfaceTable *)table didSelectRowAtIndex:(NSInteger)rowIndex
{
    NSString *name = self.names[rowIndex];
    [self _removeName:name];
    [self _messageRemoveName:name];
}

#pragma mark - Private

- (void)_connect
{
    static const NSTimeInterval kRetryDelay = 2.0;
    
    [self.connection start:^ (NSError *error) {
        if ([error.domain isEqualToString:LLBSDMessagingErrorDomain] && error.code == LLBSDMessagingInvalidChannelError) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRetryDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self _connect];
            });
        }
    }];
}

- (void)_addName:(NSString *)name
{
    [self.names insertObject:name atIndex:0];
    [self.table insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:0] withRowType:@"row"];
    
    InterfaceRow *row = [self.table rowControllerAtIndex:0];
    [row.label setText:name];
}

- (void)_removeName:(NSString *)name
{
    NSInteger rowIndex = [self.names indexOfObject:name];
    if (rowIndex == NSNotFound) {
        return;
    }
    
    [self.names removeObjectAtIndex:rowIndex];
    [self.table removeRowsAtIndexes:[NSIndexSet indexSetWithIndex:rowIndex]];
}

- (void)_messageRemoveName:(NSString *)name
{
    LLBSDMessage *message = [LLBSDMessage messageWithName:kRemoveNameMessageName userInfo:@{kNameKey : name}];
    [self.connection sendMessage:message completion:nil];
}

#pragma mark - LLBSDConnectionDelegate

- (void)connection:(LLBSDConnection *)connection didReceiveMessage:(LLBSDMessage *)message fromProcess:(LLBSDProcessInfo *)processInfo
{
    if ([message.name isEqualToString:kAddNameMessageName]) {
        NSString *name = message.userInfo[kNameKey];
        dispatch_async(dispatch_get_main_queue(), ^ {
            [self _addName:name];
        });
    } else if ([message.name isEqualToString:kRemoveNameMessageName]) {
        NSString *name = message.userInfo[kNameKey];
        dispatch_async(dispatch_get_main_queue(), ^ {
            [self _removeName:name];
        });
    }
}

- (void)connection:(LLBSDConnection *)connection didFailToReceiveMessageWithError:(NSError *)error
{
    // no-op
}

@end
