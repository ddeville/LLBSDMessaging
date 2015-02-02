//
//  LLBSDConnection.m
//  LLBSDMessaging
//
//  Created by Damien DeVille on 1/31/15.
//  Copyright (c) 2015 Damien DeVille. All rights reserved.
//

#import "LLBSDConnection.h"

#import <sys/socket.h>
#import <sys/sysctl.h>
#import <sys/un.h>
#import <TargetConditionals.h>

#import "LLBSDProcessInfo.h"
#import "LLBSDMessage.h"
#import "LLBSDMessaging-Constants.h"

static NSString * const kLLBSDConnectionMessageNameKey = @"name";
static NSString * const kLLBSDConnectionMessageUserInfoKey = @"userInfo";
static NSString * const kLLBSDConnectionMessageConnectionInfoKey = @"connectionInfo";

static const pid_t kInvalidPid = -1;

#pragma mark - LLBSDConnection

@interface LLBSDConnection ()

@property (assign, nonatomic) NSString *socketPath;
@property (assign, nonatomic) dispatch_fd_t fd;

@property (strong, nonatomic) dispatch_queue_t queue;

- (void)_startOnSerialQueue;
- (void)_invalidateOnSerialQueue;
- (void)_completeReadingWithMessage:(LLBSDMessage *)message info:(LLBSDProcessInfo *)info;

@end

@implementation LLBSDConnection

static NSString *_LLBSDConnectionValidObservationContext = @"_LLBSDConnectionValidObservationContext";

- (instancetype)initWithApplicationGroupIdentifier:(NSString *)applicationGroupIdentifier connectionIdentifier:(uint8_t)connectionIdentifier
{
    NSAssert(![self isMemberOfClass:[LLBSDConnection class]], @"Cannot instantiate the base class");
    
    self = [self init];
    if (self == nil) {
        return nil;
    }

    _fd = kInvalidPid;
    _socketPath = _createSocketPath(applicationGroupIdentifier, connectionIdentifier);
    _queue = dispatch_queue_create("com.ddeville.llbsdmessaging.serial-queue", DISPATCH_QUEUE_SERIAL);
    _processInfo = [[LLBSDProcessInfo alloc] initWithProcessName:[[NSProcessInfo processInfo] processName] processIdentifier:[[NSProcessInfo processInfo] processIdentifier]];

    [self addObserver:self forKeyPath:@"valid" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:&_LLBSDConnectionValidObservationContext];

    return self;
}

- (void)dealloc
{
    // By removing the observer before invalidating we ensure that the invalidation handler is not invoked.
    [self removeObserver:self forKeyPath:@"valid" context:&_LLBSDConnectionValidObservationContext];
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
    if (context == &_LLBSDConnectionValidObservationContext) {
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

static dispatch_data_t _createFramedMessageData(LLBSDMessage *message, LLBSDProcessInfo *info, NSError **errorRef)
{
    NSMutableDictionary *content = [NSMutableDictionary dictionary];
    [content setValue:message.name forKey:kLLBSDConnectionMessageNameKey];
    [content setValue:message.userInfo forKey:kLLBSDConnectionMessageUserInfoKey];
    [content setValue:info forKey:kLLBSDConnectionMessageConnectionInfoKey];

    NSMutableData *contentData = [NSMutableData data];

    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:contentData];
    archiver.requiresSecureCoding = YES;

    @try {
        [archiver encodeObject:content forKey:NSKeyedArchiveRootObjectKey];
        [archiver finishEncoding];
    }
    @catch (NSException *exception) {
        [archiver finishEncoding];
        if ([exception.name isEqualToString:NSInvalidUnarchiveOperationException]) {
            if (errorRef != NULL) {
                *errorRef = [NSError errorWithDomain:LLBSDMessagingErrorDomain code:LLBSDMessagingEncodingError userInfo:@{NSLocalizedDescriptionKey : exception.reason}];
            }
            return NULL;
        }
        @throw exception;
        return NULL;
    }

    CFHTTPMessageRef response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 200, NULL, kCFHTTPVersion1_1);
    CFHTTPMessageSetHeaderFieldValue(response, (__bridge CFStringRef)@"Content-Length", (__bridge CFStringRef)[NSString stringWithFormat:@"%ld", (unsigned long)[contentData length]]);
    CFHTTPMessageSetBody(response, (__bridge CFDataRef)contentData);

    NSData *messageData = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(response));
    CFRelease(response);

    dispatch_data_t message_data = dispatch_data_create([messageData bytes], [messageData length], NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    return message_data;
}

static LLBSDMessage *_createMessageFromHTTPMessage(CFHTTPMessageRef message, NSSet *allowedClasses, LLBSDProcessInfo **infoRef, NSError **errorRef)
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

        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:bodyData];
        unarchiver.requiresSecureCoding = YES;

        NSSet *classes = [NSSet setWithObjects:[NSDictionary class], [NSString class], [NSNumber class], [LLBSDProcessInfo class], nil];
        classes = [classes setByAddingObjectsFromSet:allowedClasses];

        @try {
            content = [unarchiver decodeObjectOfClasses:classes forKey:NSKeyedArchiveRootObjectKey];
            [unarchiver finishDecoding];
        }
        @catch (NSException *exception) {
            [unarchiver finishDecoding];
            if ([exception.name isEqualToString:NSInvalidUnarchiveOperationException]) {
                if (errorRef != NULL) {
                    *errorRef = [NSError errorWithDomain:LLBSDMessagingErrorDomain code:LLBSDMessagingDecodingError userInfo:@{NSLocalizedDescriptionKey : exception.reason}];
                }
                break;
            }
            @throw exception;
        }
    } while (0);

    if (!content) {
        return nil;
    }

    if (infoRef != NULL) {
        *infoRef = content[kLLBSDConnectionMessageConnectionInfoKey];
    }
    return [LLBSDMessage messageWithName:content[kLLBSDConnectionMessageNameKey] userInfo:content[kLLBSDConnectionMessageUserInfoKey]];
}

- (void)_completeReadingWithMessage:(LLBSDMessage *)message info:(LLBSDProcessInfo *)info
{
    __strong id <LLBSDConnectionDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(connection:didReceiveMessage:fromProcess:)]) {
        [delegate connection:self didReceiveMessage:message fromProcess:info];
    }
}

- (void)_completeReadingWithError:(NSError *)error
{
    __strong id <LLBSDConnectionDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(connection:didFailToReceiveMessageWithError:)]) {
        [delegate connection:self didFailToReceiveMessageWithError:error];
    }
}

@end

#pragma mark - LLBSDConnectionServer

static const int kLLBSDServerConnectionsBacklog = 1024;

@interface LLBSDConnectionServer ()

@property (strong, nonatomic) dispatch_source_t listeningSource;

@property (strong, nonatomic) NSMutableDictionary *fdToChannelMap;
@property (strong, nonatomic) NSMutableDictionary *infoToFdMap;
@property (strong, nonatomic) NSMutableDictionary *fdToFramedMessageMap;

@end

@implementation LLBSDConnectionServer

- (instancetype)initWithApplicationGroupIdentifier:(NSString *)applicationGroupIdentifier connectionIdentifier:(uint8_t)connectionIdentifier
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

- (void)broadcastMessage:(LLBSDMessage *)message completion:(void (^)(NSError *error))completion
{
    dispatch_async(self.queue, ^ {
        [self _broadcastMessageOnSerialQueue:message completion:completion];
    });
}

- (void)sendMessage:(LLBSDMessage *)message toClient:(LLBSDProcessInfo *)info completion:(void (^)(NSError *error))completion
{
    dispatch_async(self.queue, ^ {
        [self _sendMessageOnSerialQueue:message toClient:info completion:completion];
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

    int listening = listen(fd, kLLBSDServerConnectionsBacklog);
    if (listening < 0) {
        return;
    }

    dispatch_source_t listeningSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, self.queue);
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

- (void)_broadcastMessageOnSerialQueue:(LLBSDMessage *)message completion:(void (^)(NSError *error))completion
{
    for (LLBSDProcessInfo *info in self.infoToFdMap.allKeys) {
        [self sendMessage:message toClient:info completion:completion];
    }
}

- (void)_sendMessageOnSerialQueue:(LLBSDMessage *)message toClient:(LLBSDProcessInfo *)info completion:(void (^)(NSError *error))completion
{
    dispatch_fd_t fd = [self.infoToFdMap[info] intValue];
    dispatch_io_t channel = self.fdToChannelMap[@(fd)];

    if (!channel) {
        completion([NSError errorWithDomain:LLBSDMessagingErrorDomain code:LLBSDMessagingInvalidChannelError userInfo:nil]);
        return;
    }

    NSError *messageError = nil;
    dispatch_data_t message_data = _createFramedMessageData(message, info, &messageError);

    if (!message_data) {
        if (completion) {
            completion(messageError);
        }
        return;
    }

    dispatch_io_write(channel, 0, message_data, self.queue, ^ (bool done, __unused dispatch_data_t data, int write_error) {
        if (done && completion) {
            completion((write_error != 0 ? [NSError errorWithDomain:NSPOSIXErrorDomain code:write_error userInfo:nil] : nil));
        }
    });
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

static NSString *_findProcessNameForProcessIdentifier(pid_t pid)
{
    if (pid == kInvalidPid) {
        return NULL;
    }

    static const int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};

    size_t proc_list_len = 0;

    // Use an empty buffer to get the length to allocate
    int length_retrieved = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, NULL, &proc_list_len, NULL, 0);
    if (length_retrieved != 0) {
        return nil;
    }

    struct kinfo_proc *proc_list = malloc(proc_list_len);

    // Retrieve the process list now that we have allocated a buffer of the correct length
    int list_retrieved = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, proc_list, &proc_list_len, NULL, 0);
    if (list_retrieved != 0) {
        free(proc_list);
        return nil;
    }

    char *proc_name = NULL;

    for (size_t idx = 0; idx < (proc_list_len / sizeof(struct kinfo_proc)); idx++) {
        if (proc_list[idx].kp_proc.p_pid == pid) {
            proc_name = proc_list[idx].kp_proc.p_comm;
            break;
        }
    }

    NSString *processName = (proc_name ? [NSString stringWithUTF8String:proc_name] : nil);

    free(proc_list);

    return processName;
}

- (LLBSDProcessInfo *)_findSocketInfo:(dispatch_fd_t)fd
{
    pid_t processIdentifier = _findProcessIdentifierBehindSocket(fd);
    NSString *processName = _findProcessNameForProcessIdentifier(processIdentifier);

    if (processIdentifier == kInvalidPid || processName == nil) {
        return nil;
    }

    return [[LLBSDProcessInfo alloc] initWithProcessName:processName processIdentifier:processIdentifier];
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

    LLBSDProcessInfo *info = [self _findSocketInfo:client_fd];
    if (info) {
        id <LLBSDConnectionServerDelegate> delegate = self.delegate;
        accepted = [delegate server:self shouldAcceptNewConnection:info];
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
    dispatch_io_t channel = dispatch_io_create(DISPATCH_IO_STREAM, fd, self.queue, ^ (__unused int error) {});
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

        CFHTTPMessageAppendBytes(framedMessage, bytes, (CFIndex)bytesLength);
    }

    if (framedMessage && CFHTTPMessageIsHeaderComplete(framedMessage)) {
        NSInteger contentLength = [CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(framedMessage, CFSTR("Content-Length"))) integerValue];
        NSInteger bodyLength = (NSInteger)[CFBridgingRelease(CFHTTPMessageCopyBody(framedMessage)) length];

        if (contentLength == bodyLength) {
            NSError *error = nil;
            LLBSDProcessInfo *info = nil;
            LLBSDMessage *message = _createMessageFromHTTPMessage(framedMessage, self.allowedMessageClasses, &info, &error);

            [self.fdToFramedMessageMap removeObjectForKey:@(fd)];

            if (message) {
                [self _completeReadingWithMessage:message info:info];
            } else {
                [self _completeReadingWithError:error];
            }
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

    __block LLBSDProcessInfo *info = nil;
    [self.infoToFdMap enumerateKeysAndObjectsUsingBlock:^ (LLBSDProcessInfo *connectionInfo, NSNumber *fileDescriptor, BOOL *stop) {
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

#pragma mark - LLBSDConnectionClient

@interface LLBSDConnectionClient ()

@property (strong, nonatomic) dispatch_io_t channel;
@property (strong, nonatomic) id /* CFHTTPMessageRef */ framedMessage;

@end

@implementation LLBSDConnectionClient

- (void)sendMessage:(LLBSDMessage *)message completion:(void (^)(NSError *error))completion
{
    dispatch_async(self.queue, ^ {
        [self _sendMessageOnSerialQueue:message completion:completion];
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

- (void)_sendMessageOnSerialQueue:(LLBSDMessage *)message completion:(void (^)(NSError *error))completion
{
    if (!self.channel) {
        completion([NSError errorWithDomain:LLBSDMessagingErrorDomain code:LLBSDMessagingInvalidChannelError userInfo:nil]);
        return;
    }

    NSError *messageError = nil;
    dispatch_data_t message_data = _createFramedMessageData(message, self.processInfo, &messageError);

    if (!message_data) {
        if (completion) {
            completion(messageError);
        }
        return;
    }

    dispatch_io_write(self.channel, 0, message_data, self.queue, ^ (bool done, __unused dispatch_data_t data, int write_error) {
        if (done && completion) {
            completion((write_error != 0 ? [NSError errorWithDomain:NSPOSIXErrorDomain code:write_error userInfo:nil] : nil));
        }
    });
}

#pragma mark - Private

- (void)_setupChannel
{
    dispatch_io_t channel = dispatch_io_create(DISPATCH_IO_STREAM, self.fd, self.queue, ^ (__unused int error) {});
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

        CFHTTPMessageAppendBytes(framedMessage, bytes, (CFIndex)bytesLength);
    }

    if (framedMessage && CFHTTPMessageIsHeaderComplete(framedMessage)) {
        NSInteger contentLength = [CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(framedMessage, CFSTR("Content-Length"))) integerValue];
        NSInteger bodyLength = (NSInteger)[CFBridgingRelease(CFHTTPMessageCopyBody(framedMessage)) length];

        if (contentLength == bodyLength) {
            NSError *error = nil;
            LLBSDProcessInfo *info = nil;
            LLBSDMessage *message = _createMessageFromHTTPMessage(framedMessage, self.allowedMessageClasses, &info, &error);

            self.framedMessage = nil;

            if (message) {
                [self _completeReadingWithMessage:message info:info];
            } else {
                [self _completeReadingWithError:error];
            }
        }
    }
}

@end
