//
//  ViewController.m
//  TestApp
//
//  Created by Damien DeVille on 2/13/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "ViewController.h"

#import <LLBSDMessaging/LLBSDMessaging.h>

#import "Shared.h"

@interface ViewController () <LLBSDConnectionServerDelegate>

@property (strong, nonatomic) LLBSDConnectionServer *connection;
@property (strong, nonatomic) LLBSDProcessInfo *extension;

@property (strong, nonatomic) NSMutableArray *names;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.names = [NSMutableArray array];
    
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
    
    LLBSDConnectionServer *connection = [[LLBSDConnectionServer alloc] initWithApplicationGroupIdentifier:kApplicationGroupIdentifier connectionIdentifier:kConnectionIdentifier];
    connection.delegate = self;
    self.connection = connection;
    
    [connection start:nil];
}

#pragma mark - Actions

- (IBAction)add:(id)sender
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add name" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:nil];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^ (UIAlertAction *action) {
        NSString *text = [[[alert textFields] firstObject] text];
        NSString *name = (text.length ? text : @"No Name");
        [self _addName:name];
        [self _messageAddName:name];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Private

- (void)_addName:(NSString *)name
{
    if ([self.names containsObject:name]) {
        name = [name stringByAppendingString:@" Copy"];
    }
    
    [self.names insertObject:name atIndex:0];
    [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)_messageAddName:(NSString *)name
{
    LLBSDMessage *message = [LLBSDMessage messageWithName:kAddNameMessageName userInfo:@{kNameKey : name}];
    [self.connection broadcastMessage:message completion:nil];
}

- (void)_removeName:(NSString *)name
{
    NSInteger rowIndex = [self.names indexOfObject:name];
    if (rowIndex == NSNotFound) {
        return;
    }
    
    [self.names removeObjectAtIndex:rowIndex];
    [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:rowIndex inSection:0]] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)_messageRemoveName:(NSString *)name
{
    LLBSDMessage *message = [LLBSDMessage messageWithName:kRemoveNameMessageName userInfo:@{kNameKey : name}];
    [self.connection broadcastMessage:message completion:nil];
}

#pragma mark - LLBSDConnectionServerDelegate

- (BOOL)server:(LLBSDConnectionServer *)server shouldAcceptNewConnection:(LLBSDProcessInfo *)processInfo
{
    self.extension = processInfo;
    
    dispatch_async(dispatch_get_main_queue(), ^ {
        for (NSString *name in self.names) {
            [self _messageAddName:name];
        }
    });
    
    return YES;
}

- (void)connection:(LLBSDConnection *)connection didReceiveMessage:(LLBSDMessage *)message fromProcess:(LLBSDProcessInfo *)processInfo;
{
    if ([message.name isEqualToString:kRemoveNameMessageName]) {
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

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.names.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    cell.textLabel.text = self.names[indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *name = self.names[indexPath.row];
    [self _removeName:name];
    [self _messageRemoveName:name];
}

#pragma mark - UITableViewDelegate

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath
{
    return NO;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleDelete;
}

@end
