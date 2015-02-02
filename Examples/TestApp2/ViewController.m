//
//  ViewController.m
//  TestApp2
//
//  Created by Damien DeVille on 2/1/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "ViewController.h"

#import <LLBSDMessaging/LLBSDMessaging.h>

#import "SpecialMessage.h"

@interface ViewController () <LLBSDConnectionDelegate>

@property (strong, nonatomic) LLBSDConnectionClient *client;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    LLBSDConnectionClient *client = [[LLBSDConnectionClient alloc] initWithApplicationGroupIdentifier:@"com.ddeville.testapp.group" connectionIdentifier:1];
    client.delegate = self;
    self.client = client;

    [client start];
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

    SpecialMessage *specialMessage = [[SpecialMessage alloc] init];
    specialMessage.title = @"This is a special message";

    NSDictionary *userInfo = @{
        @"text" : self.messageField.text,
        @"special" : specialMessage,
    };
    LLBSDMessage *message = [LLBSDMessage messageWithName:@"message" userInfo:userInfo];

    [self.client sendMessage:message completion:^ (NSError *error) {
        if (error) {
            [self _presentError:error];
        }
    }];
}

#pragma mark - LLBSDConnectionDelegate

- (void)connection:(LLBSDConnection *)connection didReceiveMessage:(LLBSDMessage *)message fromProcess:(LLBSDProcessInfo *)processInfo
{
    if (![message.name isEqualToString:@"message"]) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *text = self.logView.text;
        text = [text stringByAppendingString:@"\n\n"];
        text = [text stringByAppendingString:message.userInfo[@"text"]];
        self.logView.text = text;
    });
}

- (void)connection:(LLBSDConnection *)connection didFailToReceiveMessageWithError:(NSError *)error
{
    [self _presentError:error];
}

@end
