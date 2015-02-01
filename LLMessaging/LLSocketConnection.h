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

/*!
    \brief
 */
- (void)connection:(LLSocketConnection *)connection didReceiveMessage:(LLSocketMessage *)message fromConnectionInfo:(LLSocketInfo *)info;

@end

/*!
    \brief
 */
@interface LLSocketConnection : NSObject

/*!
    \brief
 */
- (id)initWithApplicationGroupIdentifier:(NSString *)applicationGroupIdentifier connectionIdentifier:(uint8_t)connectionIdentifier;

/*!
    \brief
 */
@property (weak, nonatomic) id <LLSocketConnectionDelegate> delegate;

/*!
    \brief
 */
- (void)start;

/*!
    \brief
    */
- (void)invalidate;

/*!
    \brief
    Returns whether the connection is currently valid (`start` was called and the connection was not invalidated).
    KVO compliant.
 */
@property (assign, getter=isValid, nonatomic) BOOL valid;

/*!
    \brief
 */
@property (copy) void (^invalidationHandler)(void);

/*!
    \brief
 */
@property (readonly, strong, nonatomic) LLSocketInfo *info;

@end

@class LLSocketConnectionServer;

@protocol LLSocketConnectionServerDelegate <LLSocketConnectionDelegate>

/*!
    \brief
 */
- (BOOL)server:(LLSocketConnectionServer *)server shouldAcceptNewConnection:(LLSocketInfo *)connectionInfo;

@end

/*!
    \brief
 */
@interface LLSocketConnectionServer : LLSocketConnection

/*!
    \brief
 */
@property (weak, nonatomic) id <LLSocketConnectionServerDelegate> delegate;

/*!
    \brief
 */
- (void)broadcastMessage:(LLSocketMessage *)message;

/*!
    \brief
 */
- (void)sendMessage:(LLSocketMessage *)message toClient:(LLSocketInfo *)info;

@end

/*!
    \brief
 */
@interface LLSocketConnectionClient : LLSocketConnection

/*!
    \brief
 */
- (void)sendMessage:(LLSocketMessage *)message;

@end
