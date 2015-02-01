//
//  LLSocketConnection.m
//  LLMessaging
//
//  Created by Damien DeVille on 1/31/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "LLSocketConnection.h"

#import <sys/socket.h>
#import <sys/sysctl.h>
#import <sys/un.h>
#import <TargetConditionals.h>

#import "LLSocketInfo.h"
#import "LLSocketMessage.h"

static NSString * const kLLSocketConnectionMessageNameKey = @"name";
static NSString * const kLLSocketConnectionMessageUserInfoKey = @"userInfo";
static NSString * const kLLSocketConnectionMessageConnectionInfoKey = @"connectionInfo";

static const pid_t kInvalidPid = -1;

#pragma mark - LLSocketConnection

@interface LLSocketConnection ()

@property (assign, nonatomic) NSString *socketPath;
@property (assign, nonatomic) dispatch_fd_t fd;

@property (strong, nonatomic) dispatch_queue_t queue;

- (void)_startOnSerialQueue;
- (void)_invalidateOnSerialQueue;
- (void)_completeReadingWithMessage:(LLSocketMessage *)message info:(LLSocketInfo *)info;

@end

@implementation LLSocketConnection

static NSString *_LLSocketConnectionValidObservationContext = @"_LLSocketConnectionValidObservationContext";

- (id)initWithApplicationGroupIdentifier:(NSString *)applicationGroupIdentifier connectionIdentifier:(uint8_t)connectionIdentifier
{
    NSAssert(![self isMemberOfClass:[LLSocketConnection class]], @"Cannot instantiate the base class");
    
    self = [self init];
    if (self == nil) {
        return nil;
    }

    _fd = kInvalidPid;
    _socketPath = _createSocketPath(applicationGroupIdentifier, connectionIdentifier);
    _queue = dispatch_queue_create("com.ddeville.llmessaging.serial-queue", DISPATCH_QUEUE_SERIAL);
    _info = [[LLSocketInfo alloc] initWithProcessName:[[NSProcessInfo processInfo] processName] processIdentifier:[[NSProcessInfo processInfo] processIdentifier]];

    [self addObserver:self forKeyPath:@"valid" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:&_LLSocketConnectionValidObservationContext];

    return self;
}

- (void)dealloc
{
    /*
        Note: By removing the observer before invalidating we ensure that the invalidation handler is not invoked.
     */
    [self removeObserver:self forKeyPath:@"valid" context:&_LLSocketConnectionValidObservationContext];
    [self invalidate];
}

- (void)start
{
    dispatch_async(self.queue, ^ {
        [self _startOnSerialQueue];
    });
}

- (void)invalidate
{
    dispatch_async(self.queue, ^ {
        [self _invalidateOnSerialQueue];
    });
}

- (BOOL)isValid
{
    return (self.fd != kInvalidPid);
}

#pragma mark - KVO

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key
{
    NSMutableSet *keyPaths = [NSMutableSet setWithSet:[super keyPathsForValuesAffectingValueForKey:key]];

    if ([key isEqualToString:@"valid"]) {
        [keyPaths addObject:@"fd"];
    }

    return keyPaths;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == &_LLSocketConnectionValidObservationContext) {
        BOOL oldValid = [change[NSKeyValueChangeOldKey] boolValue];
        BOOL newValid = [change[NSKeyValueChangeNewKey] boolValue];
        if ((oldValid && !newValid) && self.invalidationHandler) {
            self.invalidationHandler();
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - Private (Serial Queue)

- (void)_startOnSerialQueue
{
    NSAssert(NO, @"Cannot call on the base class");
}

- (void)_invalidateOnSerialQueue
{
    NSAssert(NO, @"Cannot call on the base class");
}

#pragma mark - Private

static NSString *_createSocketPath(NSString *applicationGroupIdentifier, uint8_t connectionIdentifier)
{
    /*
     * `sockaddr_un.sun_path` has a max length of 104 characters
     * However, the container URL for the application group identifier in the simulator is much longer than that
     * Since the simulator has looser sandbox restrictions we just use /tmp
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

static dispatch_data_t _createFramedMessageData(LLSocketMessage *message, LLSocketInfo *info)
{
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    [content setValue:message.name forKey:kLLSocketConnectionMessageNameKey];
    [content setValue:message.userInfo forKey:kLLSocketConnectionMessageUserInfoKey];
    [content setValue:info forKey:kLLSocketConnectionMessageConnectionInfoKey];

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

static LLSocketMessage *_createMessageFromHTTPMessage(CFHTTPMessageRef message, LLSocketInfo **infoRef)
{
    NSDictionary *content = nil;
    do {
        if (!CFHTTPMessageIsHeaderComplete(message)) {
            break;
        }

        NSData *bodyData = CFBridgingRelease(CFHTTPMessageCopyBody(message));

        NSInteger contentLength = [CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(message, (__bridge CFStringRef)@"Content-Length")) integerValue];
        NSInteger bodyLength = (NSInteger)[bodyData length];

        if (contentLength != bodyLength) {
            break;
        }

        @try {
            content = [NSKeyedUnarchiver unarchiveObjectWithData:bodyData];
        }
        @catch (...) {}
    } while (0);

    if (!content) {
        return nil;
    }

    if (infoRef != NULL) {
        *infoRef = content[kLLSocketConnectionMessageConnectionInfoKey];
    }
    return [LLSocketMessage messageWithName:content[kLLSocketConnectionMessageNameKey] userInfo:content[kLLSocketConnectionMessageUserInfoKey]];
}

- (void)_completeReadingWithMessage:(LLSocketMessage *)message info:(LLSocketInfo *)info
{
    [self.delegate connection:self didReceiveMessage:message fromConnectionInfo:info];
}

@end

#pragma mark - LLSocketConnectionServer

static const int kLLSocketServerConnectionsBacklog = 1024;

@interface LLSocketConnectionServer ()

@property (strong, nonatomic) dispatch_source_t listeningSource;

@property (strong, nonatomic) NSMutableDictionary *fdToChannelMap;
@property (strong, nonatomic) NSMutableDictionary *infoToFdMap;
@property (strong, nonatomic) NSMutableDictionary *fdToFramedMessageMap;

@end

@implementation LLSocketConnectionServer

- (id)initWithApplicationGroupIdentifier:(NSString *)applicationGroupIdentifier connectionIdentifier:(uint8_t)connectionIdentifier
{
    self = [super initWithApplicationGroupIdentifier:applicationGroupIdentifier connectionIdentifier:connectionIdentifier];
    if (self == nil) {
        return nil;
    }

    _fdToChannelMap = [NSMutableDictionary dictionary];
    _infoToFdMap = [NSMutableDictionary dictionary];
    _fdToFramedMessageMap = [NSMutableDictionary dictionary];

    return self;
}

- (void)broadcastMessage:(LLSocketMessage *)message
{
    dispatch_async(self.queue, ^ {
        [self _broadcastMessageOnSerialQueue:message];
    });
}

- (void)sendMessage:(LLSocketMessage *)message toClient:(LLSocketInfo *)info
{
    dispatch_async(self.queue, ^ {
        [self _sendMessageOnSerialQueue:message toClient:info];
    });
}

#pragma mark - Private (Serial Queue)

- (void)_startOnSerialQueue
{
    NSParameterAssert(self.fd == kInvalidPid);

    dispatch_fd_t fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        return;
    }

    self.fd = fd;

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

- (void)_invalidateOnSerialQueue
{
    [self _cleanup];

    if (self.socketPath) {
        unlink(self.socketPath.UTF8String);
        self.socketPath = nil;
    }

    if (self.fd != kInvalidPid) {
        close(self.fd);
        self.fd = kInvalidPid;
    }
}

- (void)_broadcastMessageOnSerialQueue:(LLSocketMessage *)message
{
    [self.infoToFdMap enumerateKeysAndObjectsUsingBlock:^ (LLSocketInfo *info, NSNumber *fd, BOOL *stop) {
        [self sendMessage:message toClient:info];
    }];
}

- (void)_sendMessageOnSerialQueue:(LLSocketMessage *)message toClient:(LLSocketInfo *)info
{
    dispatch_fd_t fd = [self.infoToFdMap[info] intValue];
    dispatch_io_t channel = self.fdToChannelMap[@(fd)];
    if (!channel) {
        return;
    }

    dispatch_data_t message_data = _createFramedMessageData(message, info);
    dispatch_io_write(channel, 0, message_data, self.queue, ^ (bool done, dispatch_data_t data, int error) {});
}

#pragma mark - Private

static pid_t _findProcessIdentifierBehindSocket(dispatch_fd_t fd)
{
    pid_t pid;
    socklen_t pid_len = sizeof(pid);

    int retrieved = getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &pid_len);
    if (retrieved < 0) {
        return kInvalidPid;
    }

    return pid;
}

static char *_findProcessNameForProcessIdentifier(pid_t pid)
{
    if (pid == kInvalidPid) {
        return NULL;
    }

    int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    u_int mib_length = 4;
    size_t size;
    int st = sysctl(mib, mib_length, NULL, &size, NULL, 0);

    char *proc_name = NULL;
    struct kinfo_proc *process = NULL;

    do {
        size += size / 10;
        struct kinfo_proc *new_process = realloc(process, size);
        if (!new_process){
            break;
        }

        process = new_process;
        st = sysctl(mib, mib_length, process, &size, NULL, 0);

        if (process->kp_proc.p_pid == pid) {
            proc_name = process->kp_proc.p_comm;
            break;
        }

    } while (st == -1 && errno == ENOMEM);

    free(process);

    return proc_name;
}

- (LLSocketInfo *)_findSocketInfo:(dispatch_fd_t)fd
{
    pid_t process_identifier = _findProcessIdentifierBehindSocket(fd);
    char *process_name = _findProcessNameForProcessIdentifier(process_identifier);

    if (process_identifier == kInvalidPid || process_name == NULL) {
        return nil;
    }

    return [[LLSocketInfo alloc] initWithProcessName:[NSString stringWithUTF8String:process_name] processIdentifier:process_identifier];
}

- (void)_acceptNewConnection
{
    struct sockaddr client_addr;
    socklen_t client_addrlen = sizeof(client_addr);
    dispatch_fd_t client_fd = accept(self.fd, &client_addr, &client_addrlen);

    if (client_fd < 0) {
        return;
    }

    BOOL accepted = NO;

    LLSocketInfo *info = [self _findSocketInfo:client_fd];
    if (info) {
        accepted = [self.delegate server:self shouldAcceptNewConnection:info];
    }

    if (!accepted) {
        close(client_fd);
        return;
    }

    self.infoToFdMap[info] = @(client_fd);
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
    CFHTTPMessageRef framedMessage = (__bridge CFHTTPMessageRef)self.fdToFramedMessageMap[@(fd)];

    if (data && dispatch_data_get_size(data) != 0) {
        if (!framedMessage) {
            self.fdToFramedMessageMap[@(fd)] = CFBridgingRelease(CFHTTPMessageCreateEmpty(kCFAllocatorDefault, false));
            framedMessage = (__bridge CFHTTPMessageRef)self.fdToFramedMessageMap[@(fd)];
        }

        void const *bytes = NULL; size_t bytesLength = 0;
        dispatch_data_t contiguousData __attribute__((unused, objc_precise_lifetime)) = dispatch_data_create_map(data, &bytes, &bytesLength);

        CFHTTPMessageAppendBytes(framedMessage, bytes, bytesLength);
    }

    if (framedMessage && CFHTTPMessageIsHeaderComplete(framedMessage)) {
        NSInteger contentLength = [CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(framedMessage, CFSTR("Content-Length"))) integerValue];
        NSInteger bodyLength = (NSInteger)[CFBridgingRelease(CFHTTPMessageCopyBody(framedMessage)) length];

        if (contentLength == bodyLength) {
            LLSocketInfo *info = nil;
            LLSocketMessage *message = _createMessageFromHTTPMessage(framedMessage, &info);

            [self.fdToFramedMessageMap removeObjectForKey:@(fd)];

            [self _completeReadingWithMessage:message info:info];
        }
    }
}

- (void)_cleanupConnection:(dispatch_fd_t)fd
{
    dispatch_io_t channel = self.fdToChannelMap[@(fd)];
    if (channel) {
        dispatch_io_close(channel, DISPATCH_IO_STOP);
        [self.fdToChannelMap removeObjectForKey:@(fd)];
    }

    __block LLSocketInfo *info = nil;
    [self.infoToFdMap enumerateKeysAndObjectsUsingBlock:^ (LLSocketInfo *connectionInfo, NSNumber *fileDescriptor, BOOL *stop) {
        if (fileDescriptor.intValue == fd) {
            info = connectionInfo;
            *stop = YES;
        }
    }];

    if (info) {
        [self.infoToFdMap removeObjectForKey:info];
    }
}

- (void)_cleanup
{
    for (dispatch_io_t channel in  self.fdToChannelMap.allValues) {
        dispatch_io_close(channel, DISPATCH_IO_STOP);
    }

    [self.fdToChannelMap removeAllObjects];
    [self.fdToFramedMessageMap removeAllObjects];
    [self.infoToFdMap removeAllObjects];
}

@end

#pragma mark - LLSocketConnectionClient

@interface LLSocketConnectionClient ()

@property (strong, nonatomic) dispatch_io_t channel;
@property (strong, nonatomic) id /* CFHTTPMessageRef */ framedMessage;

@end

@implementation LLSocketConnectionClient

- (void)sendMessage:(LLSocketMessage *)message
{
    dispatch_async(self.queue, ^ {
        [self _sendMessageOnSerialQueue:message];
    });
}

#pragma mark - Private (Serial Queue)

- (void)_startOnSerialQueue
{
    NSParameterAssert(self.fd == kInvalidPid);

    dispatch_fd_t fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        return;
    }

    self.fd = fd;

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

- (void)_invalidateOnSerialQueue
{
    if (self.channel) {
        dispatch_io_close(self.channel, DISPATCH_IO_STOP);
        self.channel = nil;
    }

    if (self.fd != kInvalidPid) {
        close(self.fd);
        self.fd = kInvalidPid;
    }
}

- (void)_sendMessageOnSerialQueue:(LLSocketMessage *)message
{
    dispatch_data_t message_data = _createFramedMessageData(message, self.info);
    dispatch_io_write(self.channel, 0, message_data, self.queue, ^ (bool done, dispatch_data_t data, int error) {});
}

#pragma mark - Private

- (void)_setupChannel
{
    dispatch_io_t channel = dispatch_io_create(DISPATCH_IO_STREAM, self.fd, self.queue, ^ (int error) {});
    dispatch_io_set_low_water(channel, 1);
    dispatch_io_set_high_water(channel, SIZE_MAX);
    self.channel = channel;

    dispatch_io_read(channel, 0, SIZE_MAX, self.queue, ^ (bool done, dispatch_data_t data, int error) {
        if (error) {
            return;
        }

        [self _readData:data];

        if (done) {
            [self invalidate];
        }
    });
}

- (void)_readData:(dispatch_data_t)data
{
    CFHTTPMessageRef framedMessage = (__bridge CFHTTPMessageRef)self.framedMessage;

    if (data && dispatch_data_get_size(data) != 0) {
        if (!self.framedMessage) {
            self.framedMessage = CFBridgingRelease(CFHTTPMessageCreateEmpty(kCFAllocatorDefault, false));
            framedMessage = (__bridge CFHTTPMessageRef)self.framedMessage;
        }

        void const *bytes = NULL; size_t bytesLength = 0;
        dispatch_data_t contiguousData __attribute__((unused, objc_precise_lifetime)) = dispatch_data_create_map(data, &bytes, &bytesLength);

        CFHTTPMessageAppendBytes(framedMessage, bytes, bytesLength);
    }

    if (framedMessage && CFHTTPMessageIsHeaderComplete(framedMessage)) {
        NSInteger contentLength = [CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(framedMessage, CFSTR("Content-Length"))) integerValue];
        NSInteger bodyLength = (NSInteger)[CFBridgingRelease(CFHTTPMessageCopyBody(framedMessage)) length];

        if (contentLength == bodyLength) {
            LLSocketInfo *info = nil;
            LLSocketMessage *message = _createMessageFromHTTPMessage(framedMessage, &info);

            self.framedMessage = nil;

            [self _completeReadingWithMessage:message info:info];
        }
    }
}

@end