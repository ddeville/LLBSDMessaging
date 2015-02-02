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

@optional

/*!
    \brief
    This method is called whenever a message is successfully received by the connection peer.

    \param connection
    The current connection receiving the message.

    \param message
    The message being received.

    \param processInfo
    The info about the process that sent the message.
 */
- (void)connection:(LLBSDConnection *)connection didReceiveMessage:(LLBSDMessage *)message fromProcess:(LLBSDProcessInfo *)processInfo;

/*!
    \brief
    This method is called whenever a message was sent successfully but failed to be received by the connection. Usual errors include decoding custom classes.

    \param connection
    The current connection receiving the message.

    \param error
    The error describing the failure to receive the message.
 */
- (void)connection:(LLBSDConnection *)connection didFailToReceiveMessageWithError:(NSError *)error;

@end

/*!
    \brief
    An abstract class representing a connection peer. Delegate methods and completion blocks will be called on any thread.
 */
@interface LLBSDConnection : NSObject

/*!
    \brief
    Initializes a new connection peer. Note that you should only initialize a concrete subclass of `LLBSDConnection`.

    \param applicationGroupIdentifier
    The identifier for an application group security container. You should have a `com.apple.security.application-groups` entitlement for this identifier

    \param connectionIdentifier
    An identifier for the connection. Both ends of a connection should use the same identifier.
 */
- (instancetype)initWithApplicationGroupIdentifier:(NSString *)applicationGroupIdentifier connectionIdentifier:(uint8_t)connectionIdentifier;

/*!
    \brief
    The connection delegate.
 */
@property (weak, nonatomic) id <LLBSDConnectionDelegate> delegate;

/*!
    \brief
    Starts the connection. It is a programmer error to start a connection that is still valid.
 */
- (void)start;

/*!
    \brief
    Invalidates the connection. The connection can be started again after invalidating. Upon invalidating, messages currently in transit will be cancelled.
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
    A handler that is invoked whenever the connection becomes invalid.
 */
@property (copy, nonatomic) void (^invalidationHandler)(void);

/*!
    \brief
    The process info about the connection peer.
 */
@property (readonly, strong, nonatomic) LLBSDProcessInfo *processInfo;

/*!
    \brief
    A set of custom classes that can be sent in a message `userInfo`. Classes in this set need to conform to `NSSecureCoding`.
 */
@property (strong, nonatomic) NSSet *allowedMessageClasses;

@end

@class LLBSDConnectionServer;

@protocol LLBSDConnectionServerDelegate <LLBSDConnectionDelegate>

/*!
    \brief
    This method is called whenever a client attempts to connect to the server. Returning NO will deny the connection.

    \param server
    The server that is receiving the connection.

    \param processInfo
    Process info about the client that is attempting to connect.
 */
- (BOOL)server:(LLBSDConnectionServer *)server shouldAcceptNewConnection:(LLBSDProcessInfo *)processInfo;

@end

/*!
    \brief
    A concrete subclass of `LLBSDConnection` modeling a server that can listen and message to multiple clients.
 */
@interface LLBSDConnectionServer : LLBSDConnection

/*!
    \brief
    The connection delegate.
 */
@property (weak, nonatomic) id <LLBSDConnectionServerDelegate> delegate;

/*!
    \brief
    Broadcast a message to all the connected clients. This method will do nothing if no client is currently connected.

    \param message
    The message to broadcast to the clients.

    \param completion
    A completion handler that is invoked whenever the message is sent (not delivered). A sending error can optionally be included.
 */
- (void)broadcastMessage:(LLBSDMessage *)message completion:(void (^)(NSError *error))completion;

/*!
    \brief
    Send a message to a particular client.

    \param message
    The message to send to the client.

    \param info
    The process info about the client.

    \param completion
    A completion handler that is invoked whenever the message is sent (not delivered). A sending error can optionally be included.
 */
- (void)sendMessage:(LLBSDMessage *)message toClient:(LLBSDProcessInfo *)info completion:(void (^)(NSError *error))completion;

@end

/*!
    \brief
    A concrete subclass of `LLBSDConnection` modeling a client that can connect and message to a single server.
 */
@interface LLBSDConnectionClient : LLBSDConnection

/*!
    \brief
    Send a message to the connected server.

    \param completion
    A completion handler that is invoked whenever the message is sent (not delivered). A sending error can optionally be included.
 */
- (void)sendMessage:(LLBSDMessage *)message completion:(void (^)(NSError *error))completion;

@end
