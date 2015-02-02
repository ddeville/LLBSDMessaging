//
//  LLBSDConnection.h
//  LLBSDMessaging
//
//  Created by Damien DeVille on 1/31/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import <Foundation/Foundation.h>

@class LLBSDConnection, LLBSDProcessInfo, LLBSDMessage;

@protocol LLBSDConnectionDelegate <NSObject>

/*!
    \brief
 */
- (void)connection:(LLBSDConnection *)connection didReceiveMessage:(LLBSDMessage *)message fromProcess:(LLBSDProcessInfo *)processInfo;

@end

/*!
    \brief
 */
@interface LLBSDConnection : NSObject

/*!
    \brief
 */
- (id)initWithApplicationGroupIdentifier:(NSString *)applicationGroupIdentifier connectionIdentifier:(uint8_t)connectionIdentifier;

/*!
    \brief
 */
@property (weak, nonatomic) id <LLBSDConnectionDelegate> delegate;

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
@property (readonly, strong, nonatomic) LLBSDProcessInfo *info;

@end

@class LLBSDConnectionServer;

@protocol LLBSDConnectionServerDelegate <LLBSDConnectionDelegate>

/*!
    \brief
 */
- (BOOL)server:(LLBSDConnectionServer *)server shouldAcceptNewConnection:(LLBSDProcessInfo *)connectionInfo;

@end

/*!
    \brief
 */
@interface LLBSDConnectionServer : LLBSDConnection

/*!
    \brief
 */
@property (weak, nonatomic) id <LLBSDConnectionServerDelegate> delegate;

/*!
    \brief
 */
- (void)broadcastMessage:(LLBSDMessage *)message completion:(void (^)(NSError *error))completion;

/*!
    \brief
 */
- (void)sendMessage:(LLBSDMessage *)message toClient:(LLBSDProcessInfo *)info completion:(void (^)(NSError *error))completion;

@end

/*!
    \brief
 */
@interface LLBSDConnectionClient : LLBSDConnection

/*!
    \brief
 */
- (void)sendMessage:(LLBSDMessage *)message completion:(void (^)(NSError *error))completion;

@end
