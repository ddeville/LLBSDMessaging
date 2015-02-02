//
//  ViewController.m
//  TestApp
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "ViewController.h"

#import <LLBSDMessaging/LLBSDMessaging.h>

#import "SpecialMessage.h"

@interface ViewController () <LLBSDConnectionServerDelegate>

@property (strong, nonatomic) LLBSDConnectionServer *server;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    LLBSDConnectionServer *server = [[LLBSDConnectionServer alloc] initWithApplicationGroupIdentifier:@"com.ddeville.testapp.group" connectionIdentifier:1];
    server.delegate = self;
    server.allowedMessageClasses = [NSSet setWithObject:[SpecialMessage class]];
    self.server = server;

    [server start];
}

- (void)_presentError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:error.localizedDescription message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - Actions

- (IBAction)sendMessage:(id)sender
{
    if (self.messageField.text.length == 0) {
        return;
    }

    NSDictionary *userInfo = @{
        @"text" : self.messageField.text,
    };
    LLBSDMessage *message = [LLBSDMessage messageWithName:@"message" userInfo:userInfo];

    [self.server broadcastMessage:message completion:^ (NSError *error) {
        if (error) {
            [self _presentError:error];
        }
    }];
}

#pragma mark - LLBSDConnectionServerDelegate

- (BOOL)server:(LLBSDConnectionServer *)server shouldAcceptNewConnection:(LLBSDProcessInfo *)connectionInfo
{
    return YES;
}

- (void)connection:(LLBSDConnection *)connection didReceiveMessage:(LLBSDMessage *)message fromProcess:(LLBSDProcessInfo *)processInfo
{
    if (![message.name isEqualToString:@"message"]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *text = self.logView.text;
        text = [text stringByAppendingString:@"\n\n"];
        text = [text stringByAppendingString:message.userInfo[@"text"]];
        text = [text stringByAppendingString:@"\n"];
        text = [text stringByAppendingString:[message.userInfo[@"special"] title]];
        self.logView.text = text;
    });
}

- (void)connection:(LLBSDConnection *)connection didFailToReceiveMessageWithError:(NSError *)error
{
    [self _presentError:error];
}

@end
