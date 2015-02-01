//
//  LLSocketConnection.m
//  Test
//
//  Created by Damien DeVille on 1/31/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "LLSocketConnection.h"

#import <TargetConditionals.h>
#import <sys/socket.h>
#import <sys/un.h>

#import "LLSocketInfo.h"
#import "LLSocketMessage.h"

@interface LLSocketConnection ()

@property (assign, nonatomic) NSString *socketPath;
@property (assign, nonatomic) dispatch_fd_t fileDescriptor;

@property (strong, nonatomic) dispatch_queue_t queue;

@end

@implementation LLSocketConnection

- (id)initWithApplicationGroupIdentifier:(NSString *)applicationGroupIdentifier connectionIdentifier:(uint8_t)connectionIdentifier
{
    NSAssert(![self isMemberOfClass:[LLSocketConnection class]], @"Cannot instantiate the base class");
    
    self = [self init];
    if (self == nil) {
        return nil;
    }

    _fileDescriptor = -1;
    _socketPath = _createSocketPath(applicationGroupIdentifier, connectionIdentifier);
    _queue = dispatch_queue_create("LLSocketConnection serial queue", DISPATCH_QUEUE_SERIAL);
    _info = [[LLSocketInfo alloc] initWithBundleIdentifier:[[NSBundle mainBundle] bundleIdentifier] processIdentifier:[[NSProcessInfo processInfo] processIdentifier]];

    return self;
}

- (void)dealloc
{
    [self suspend];
}

- (void)resume
{
    NSAssert(NO, @"Cannot call on the base class");
}

- (void)suspend
{
    NSAssert(NO, @"Cannot call on the base class");
}

#pragma mark - Private

static NSString *_createSocketPath(NSString *applicationGroupIdentifier, uint8_t connectionIdentifier)
{
    /*
     * `sockaddr_un.sun_path` has a max length of 104 characters
     * However, the container URL for the application group identifier in the simulator is much longer than that
     * Since the simulator have looser sandbox restrictions we just use /tmp
     */
#if TARGET_IPHONE_SIMULATOR
    NSString *tempGroupLocation = [NSString stringWithFormat:@"/tmp/%@", applicationGroupIdentifier];
    NSString *socketPath = [tempGroupLocation stringByAppendingPathComponent:[NSString stringWithFormat:@"%d", connectionIdentifier]];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempGroupLocation withIntermediateDirectories:YES attributes:nil error:NULL];
    return socketPath;
#else
    NSURL *applicationGroupURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:applicationGroupIdentifier];
    NSCParameterAssert(applicationGroupURL);

    NSURL *socketURL = [applicationGroupURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%d", connectionIdentifier]];
    return socketURL.path;
#endif /* TARGET_IPHONE_SIMULATOR */
}

static NSString * const kMessageNameKey = @"name";
static NSString * const kMessageUserInfoKey = @"userInfo";

static dispatch_data_t _createFramedMessageData(LLSocketMessage *message)
{
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    [content setValue:message.name forKey:kMessageNameKey];
    [content setValue:message.userInfo forKey:kMessageUserInfoKey];

    NSMutableData *contentData = [NSMutableData data];

    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:contentData];
    archiver.requiresSecureCoding = YES;

    [archiver encodeObject:content forKey:NSKeyedArchiveRootObjectKey];
    [archiver finishEncoding];

    CFHTTPMessageRef response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 200, NULL, kCFHTTPVersion1_1);
    CFHTTPMessageSetHeaderFieldValue(response, (__bridge CFStringRef)@"Content-Length", (__bridge CFStringRef)[NSString stringWithFormat:@"%ld", (unsigned long)[contentData length]]);
    CFHTTPMessageSetBody(response, (__bridge CFDataRef)contentData);

    NSData *messageData = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(response));
    CFRelease(response);

    dispatch_data_t message_data = dispatch_data_create([messageData bytes], [messageData length], NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    return message_data;
}

static LLSocketMessage *_createMessageFromHTTPMessage(CFHTTPMessageRef message)
{
    NSDictionary *content = nil;
    do {
        if (!CFHTTPMessageIsHeaderComplete(message)) {
            break;
        }

        NSInteger contentLength = [CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(message, (__bridge CFStringRef)@"Content-Length")) integerValue];
        NSData *bodyData = CFBridgingRelease(CFHTTPMessageCopyBody(message));

        if (contentLength != (NSInteger)[bodyData length]) {
            break;
        }

        @try {
            content = [NSKeyedUnarchiver unarchiveObjectWithData:bodyData];
        }
        @catch (...) {}
    } while (0);

    return [LLSocketMessage messageWithName:content[kMessageNameKey] userInfo:content[kMessageUserInfoKey]];
}

@end

#pragma mark -

static const int kLLSocketServerConnectionsBacklog = 1024;

@interface LLSocketConnectionServer ()

@property (strong, nonatomic) dispatch_source_t listeningSource;
@property (strong, nonatomic) NSMutableDictionary *fdToChannelMap;
@property (strong, nonatomic) NSMutableDictionary *fdToMessageMap;

@end

@implementation LLSocketConnectionServer

- (id)initWithApplicationGroupIdentifier:(NSString *)applicationGroupIdentifier connectionIdentifier:(uint8_t)connectionIdentifier
{
    self = [super initWithApplicationGroupIdentifier:applicationGroupIdentifier connectionIdentifier:connectionIdentifier];
    if (self == nil) {
        return nil;
    }

    _fdToChannelMap = [NSMutableDictionary dictionary];
    _fdToMessageMap = [NSMutableDictionary dictionary];

    return self;
}

- (void)resume
{
    NSParameterAssert(self.fileDescriptor == -1);

    dispatch_fd_t fd = socket(AF_LOCAL, SOCK_STREAM, 0);
    if (fd < 0) {
        return;
    }

    self.fileDescriptor = fd;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    const char *socket_path = self.socketPath.UTF8String;
    unlink(socket_path);
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);

    int bound = bind(fd, (struct sockaddr *)&addr, sizeof(addr));
    if (bound < 0) {
        return;
    }

    int listening = listen(fd, kLLSocketServerConnectionsBacklog);
    if (listening < 0) {
        return;
    }

    dispatch_source_t listeningSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, self.queue);
    dispatch_source_set_event_handler(listeningSource, ^ {
        [self _acceptNewConnection];
    });
    dispatch_resume(listeningSource);
    self.listeningSource = listeningSource;
}

- (void)suspend
{
    unlink(self.socketPath.UTF8String);
    self.socketPath = nil;

    close(self.fileDescriptor);
    self.fileDescriptor = -1;
}

- (void)broadcastMessage:(LLSocketMessage *)message
{
    [self.fdToChannelMap enumerateKeysAndObjectsUsingBlock:^ (NSNumber *fd, dispatch_io_t channel, BOOL *stop) {
        dispatch_data_t message_data = _createFramedMessageData(message);
        dispatch_io_write(channel, 0, message_data, self.queue, ^ (bool done, dispatch_data_t data, int error) {});
    }];
}

- (void)sendMessage:(LLSocketMessage *)message toClient:(LLSocketInfo *)info
{

}

#pragma mark - Private

- (void)_acceptNewConnection
{
    struct sockaddr client_addr;
    socklen_t client_addrlen = sizeof(client_addr);
    getpeername(self.fileDescriptor, &client_addr, &client_addrlen);
    dispatch_fd_t client_fd = accept(self.fileDescriptor, &client_addr, &client_addrlen);
    if (client_fd < 0) {
        return;
    }
    getpeername(self.fileDescriptor, &client_addr, &client_addrlen);
    [self _setupChannelForNewConnection:client_fd];
}

- (void)_setupChannelForNewConnection:(dispatch_fd_t)fd
{
    dispatch_io_t channel = dispatch_io_create(DISPATCH_IO_STREAM, fd, self.queue, ^ (int error) {});
    dispatch_io_set_low_water(channel, 1);
    dispatch_io_set_high_water(channel, SIZE_MAX);
    self.fdToChannelMap[@(fd)] = channel;

    dispatch_io_read(channel, 0, SIZE_MAX, self.queue, ^ (bool done, dispatch_data_t data, int error) {
        if (error) {
            return;
        }

        [self _readData:data fromConnection:fd];

        if (done) {
            [self _cleanupConnection:fd];
        }
    });
}

- (void)_readData:(dispatch_data_t)data fromConnection:(dispatch_fd_t)fd
{
    CFHTTPMessageRef message = (__bridge CFHTTPMessageRef)self.fdToMessageMap[@(fd)];

    if (data != nil && dispatch_data_get_size(data) != 0) {
        if (!message) {
            self.fdToMessageMap[@(fd)] = CFBridgingRelease(CFHTTPMessageCreateEmpty(kCFAllocatorDefault, false));
            message = (__bridge CFHTTPMessageRef)self.fdToMessageMap[@(fd)];
        }

        void const *bytes = NULL; size_t bytesLength = 0;
        dispatch_data_t contiguousData __attribute__((unused, objc_precise_lifetime)) = dispatch_data_create_map(data, &bytes, &bytesLength);

        CFHTTPMessageAppendBytes(message, bytes, bytesLength);
    }

    if (CFHTTPMessageIsHeaderComplete(message)) {
        NSInteger contentLength = [CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(message, CFSTR("Content-Length"))) integerValue];
        NSInteger bodyLength = (NSInteger)[CFBridgingRelease(CFHTTPMessageCopyBody(message)) length];

        if (contentLength == bodyLength) {
            LLSocketMessage *actualMessage = _createMessageFromHTTPMessage(message);
            [self.fdToMessageMap removeObjectForKey:@(fd)];
            [self _completeReadingWithMessage:actualMessage fromConnection:fd];
        }
    }
}

- (void)_completeReadingWithMessage:(LLSocketMessage *)message fromConnection:(dispatch_fd_t)fd
{
    [self.delegate connection:self didReceiveMessage:message fromConnectionInfo:nil];
}

- (void)_cleanupConnection:(dispatch_fd_t)fd
{
    dispatch_io_t channel = self.fdToMessageMap[@(fd)];
    dispatch_io_close(channel, DISPATCH_IO_STOP);
    [self.fdToChannelMap removeObjectForKey:@(fd)];
}

@end

#pragma mark -

@interface LLSocketConnectionClient ()

@property (strong, nonatomic) dispatch_io_t channel;
@property (strong, nonatomic) id /* CFHTTPMessageRef */ message;

@end

@implementation LLSocketConnectionClient

- (void)resume
{
    NSParameterAssert(self.fileDescriptor == -1);

    dispatch_fd_t fd = socket(AF_LOCAL, SOCK_STREAM, 0);
    if (fd < 0) {
        return;
    }

    self.fileDescriptor = fd;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;

    const char *socket_path = self.socketPath.UTF8String;
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);

    int connected = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    if (connected < 0) {
        return;
    }

    [self _setupChannel];
}

- (void)suspend
{
    close(self.fileDescriptor);
    self.fileDescriptor = -1;
}

- (void)sendMessage:(LLSocketMessage *)message
{
    dispatch_data_t message_data = _createFramedMessageData(message);
    dispatch_io_write(self.channel, 0, message_data, self.queue, ^ (bool done, dispatch_data_t data, int error) {});
}

#pragma mark - Private

- (void)_setupChannel
{
    dispatch_io_t channel = dispatch_io_create(DISPATCH_IO_STREAM, self.fileDescriptor, self.queue, ^ (int error) {});
    dispatch_io_set_low_water(channel, 1);
    dispatch_io_set_high_water(channel, SIZE_MAX);
    self.channel = channel;

    dispatch_io_read(channel, 0, SIZE_MAX, self.queue, ^ (bool done, dispatch_data_t data, int error) {
        if (error) {
            return;
        }

        [self _readData:data];

        if (done) {
            [self _cleanup];
        }
    });
}

- (void)_readData:(dispatch_data_t)data
{
    CFHTTPMessageRef message = (__bridge CFHTTPMessageRef)self.message;

    if (data != nil && dispatch_data_get_size(data) != 0) {
        if (!self.message) {
            self.message = CFBridgingRelease(CFHTTPMessageCreateEmpty(kCFAllocatorDefault, false));
            message = (__bridge CFHTTPMessageRef)self.message;
        }

        void const *bytes = NULL; size_t bytesLength = 0;
        dispatch_data_t contiguousData __attribute__((unused, objc_precise_lifetime)) = dispatch_data_create_map(data, &bytes, &bytesLength);

        CFHTTPMessageAppendBytes(message, bytes, bytesLength);
    }

    if (CFHTTPMessageIsHeaderComplete(message)) {
        NSInteger contentLength = [CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(message, CFSTR("Content-Length"))) integerValue];
        NSInteger bodyLength = (NSInteger)[CFBridgingRelease(CFHTTPMessageCopyBody(message)) length];

        if (contentLength == bodyLength) {
            LLSocketMessage *actualMessage = _createMessageFromHTTPMessage(message);
            self.message = nil;
            [self _completeReadingWithMessage:actualMessage];
        }
    }
}

- (void)_completeReadingWithMessage:(LLSocketMessage *)message
{
    [self.delegate connection:self didReceiveMessage:message fromConnectionInfo:nil];
}

- (void)_cleanup
{
    dispatch_io_close(self.channel, DISPATCH_IO_STOP);
    self.channel = nil;
}

@end