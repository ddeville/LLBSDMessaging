//
//  LLSocketConnection.h
//  Test
//
//  Created by Damien DeVille on 1/31/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>

@class LLSocketConnection, LLSocketInfo, LLSocketMessage;

@protocol LLSocketConnectionDelegate <NSObject>

- (void)connection:(LLSocketConnection *)connection didReceiveMessage:(LLSocketMessage *)message fromConnectionInfo:(LLSocketInfo *)info;

@end

@interface LLSocketConnection : NSObject

- (id)initWithApplicationGroupIdentifier:(NSString *)applicationGroupIdentifier connectionIdentifier:(uint8_t)connectionIdentifier;

- (void)resume;
- (void)suspend;

@property (weak, nonatomic) id <LLSocketConnectionDelegate> delegate;

@property (readonly, strong, nonatomic) LLSocketInfo *info;

@end

@class LLSocketConnectionServer;

@protocol LLSocketConnectionServerDelegate <LLSocketConnectionDelegate>

- (BOOL)server:(LLSocketConnectionServer *)server shouldAcceptNewConnection:(LLSocketInfo *)connectionInfo;

@end

@interface LLSocketConnectionServer : LLSocketConnection

- (void)broadcastMessage:(LLSocketMessage *)message;

- (void)sendMessage:(LLSocketMessage *)message toClient:(LLSocketInfo *)info;

@property (weak, nonatomic) id <LLSocketConnectionServerDelegate> delegate;

@end

@interface LLSocketConnectionClient : LLSocketConnection

- (void)sendMessage:(LLSocketMessage *)message;

@end
