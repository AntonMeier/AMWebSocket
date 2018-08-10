//
//  AMWebSocket.m
//  AM
//
//  Created by Anton Meier on 2018-08-01.
//  Creative Commons CC0 1.0 Licence
//

#import "AMWebSocket.h"
#import "GCDAsyncSocket.h"

/*
 
 WebSocket header definition (https://tools.ietf.org/html/rfc6455 5.2)
 
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-------+-+-------------+-------------------------------+
 |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
 |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
 |N|V|V|V|       |S|             |   (if payload len==126/127)   |
 | |1|2|3|       |K|             |                               |
 +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
 |     Extended payload length continued, if payload len == 127  |
 + - - - - - - - - - - - - - - - +-------------------------------+
 |                               |Masking-key, if MASK set to 1  |
 +-------------------------------+-------------------------------+
 | Masking-key (continued)       |          Payload Data         |
 +-------------------------------- - - - - - - - - - - - - - - - +
 :                     Payload Data continued ...                :
 + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
 |                     Payload Data continued ...                |
 +---------------------------------------------------------------+
 
 */

#define AMWEBSOCKET_DEBUG 0

#if AMWEBSOCKET_DEBUG == 1
#define AMWebSocketLog(args...) do { NSLog(args); } while(0)
#else
#define AMWebSocketLog(args...) do {} while(0)
#endif

NSString * const AMWebSocketErrorDomain = @"AMWebSocketErrorDomain"; // Change to reverse-DNS format if you prefer that.

enum
{
    AMWebSocketTagHandshake = 0,
    AMWebSocketTagMessage = 1,
    AMWebSocketTagIncomingMessageHeader = 2,
    AMWebSocketTagIncomingMessageShortPayloadLength = 3,
    AMWebSocketTagIncomingMessageLongPayloadLength = 4,
    AMWebSocketTagIncomingMessagePayload = 5,
};

struct AMWebSocketBaseHeader
{
    uint8_t     opcode:4;
    uint8_t     reserved:3;
    uint8_t     fin:1;
    uint8_t     payload_length:7;
    uint8_t     mask:1;
} __attribute((packed));
typedef struct AMWebSocketBaseHeader AMWebSocketBaseHeader;

struct AMWebSocketShortPayloadLength
{
    uint8_t     b1:8;
    uint8_t     b2:8;
} __attribute((packed));
typedef struct AMWebSocketShortPayloadLength AMWebSocketShortPayloadLength;

struct AMWebSocketLongPayloadLength
{
    uint8_t     b1:8;
    uint8_t     b2:8;
    uint8_t     b3:8;
    uint8_t     b4:8;
    uint8_t     b5:8;
    uint8_t     b6:8;
    uint8_t     b7:8;
    uint8_t     b8:8;
} __attribute((packed));
typedef struct AMWebSocketLongPayloadLength AMWebSocketLongPayloadLength;

@interface AMWebSocket () <GCDAsyncSocketDelegate>
{
    dispatch_queue_t _socketQueue;
    GCDAsyncSocket *_socket;
}

@property (nonatomic, readwrite, strong) AMWebSocketConfiguration *configuration;
@property (copy) void (^ _Nullable outgoingEventCompletion)(NSError * _Nullable, NSData * _Nullable);
@property (copy) void (^ _Nullable openSocketCompletion)(NSError * _Nullable);
@property (copy) void (^ _Nullable closeSocketCompletion)(NSError * _Nullable);

@end

@implementation AMWebSocket

+ (instancetype)webSocketWithConfiguration:(AMWebSocketConfiguration *)configuration;
{
    return [[AMWebSocket alloc] initWithConfiguration:configuration];
}

- (instancetype)initWithConfiguration:(AMWebSocketConfiguration *)configuration;
{
    self = [super init];
    
    if (self)
    {
        _configuration = configuration;
        _socketQueue = dispatch_queue_create("AMWebSocketQueue", NULL);
        _socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:_socketQueue];
    }
    
    return self;
}

- (void)notifyFailure:(NSNumber*)code;
{
    AMWebSocketLog(@"notifyFailure");
    
    if (self.openSocketCompletion)
    {
        NSError *returnErr = [NSError errorWithDomain:AMWebSocketErrorDomain code:code.integerValue userInfo:@{NSLocalizedDescriptionKey: @"Could not connect."}];
        void (^completion)(NSError * e) = self.openSocketCompletion;
        self.openSocketCompletion = nil;
        completion(returnErr);
    }
}

- (void)notifyClosed;
{
    AMWebSocketLog(@"notifyClosed");
    
    if (self.openSocketCompletion)
    {
        NSError *returnErr = [NSError errorWithDomain:AMWebSocketErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Socked closed."}];
        void (^completion)(NSError * e) = self.openSocketCompletion;
        self.openSocketCompletion = nil;
        completion(returnErr);
    }
    
    if (self.closeSocketCompletion)
    {
        void (^completion)(NSError * e) = self.closeSocketCompletion;
        self.closeSocketCompletion = nil;
        completion(nil);
    }
}

- (void)notifyOpened;
{
    AMWebSocketLog(@"notifyOpened");
    if (self.openSocketCompletion)
    {
        void (^completion)(NSError * e) = self.openSocketCompletion;
        self.openSocketCompletion = nil;
        completion(nil);
    }
}

- (void)notifyMessageReceived:(NSData*)data;
{
    AMWebSocketLog(@"notify: %@", data);
    
    if (self.outgoingEventCompletion)
    {
        void (^completion)( NSError * e, NSData *m ) = self.outgoingEventCompletion;
        self.outgoingEventCompletion = nil;
        completion(nil, data);
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(socket:didReceiveData:)])
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate socket:self didReceiveData:data];
        });
    }
}

- (void)notifyMessageWriteTimeout;
{
    if (self.outgoingEventCompletion)
    {
        NSError *returnErr = [NSError errorWithDomain:AMWebSocketErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Could not send message due to timeout."}];
        void (^completion)( NSError * e, NSData *m ) = self.outgoingEventCompletion;
        self.outgoingEventCompletion = nil;
        completion(returnErr, nil);
    }
}

- (void)notifyMessageSent;
{
    // In case anyone wants this at some point.
}

- (void)readNextMessage;
{
    AMWebSocketLog(@"readNextMessage");
    [_socket readDataToLength:2 withTimeout:-1 tag:AMWebSocketTagIncomingMessageHeader];
}

- (void)close;
{
    [_socket disconnectAfterReadingAndWriting];
}

- (void)closeWithCompletion:(void (^)(NSError *error))completion;
{
    if (completion)
    {
        self.closeSocketCompletion = completion;
    }
    [self close];
}

- (void)openWithCompletion:(void (^)(NSError *error))completion;
{
    if (!_connected)
    {
        if (completion)
        {
            self.openSocketCompletion = completion;
        }
        AMWebSocketLog(@"Connecting to host: %@", self.configuration.url.absoluteString);
        [_socket connectToHost:self.configuration.url.host onPort:self.configuration.port != 0 ? self.configuration.port : self.configuration.ssl ? 443 : 80 withTimeout:5 error:nil];
    }
    else
    {
        if (completion)
        {
            completion(nil);
            self.openSocketCompletion = nil;
        }
    }
}

// Right now, when sending with completion, you may only have one outgoing event at a time.
// Also not super reliable unless you know for sure that no other data will be sent to the client by the server.
// If your protocol is not strictly request-response based then I recommend setting the completion to nil and instead use the didReceiveData: delegate callback.
- (void)sendData:(NSData *)data completion:(void (^)(NSError *error, NSData *response))completion;
{
    if (completion)
    {
        self.outgoingEventCompletion = completion;
    }
    
    AMWebSocketBaseHeader header = { 0 };
    
    header.fin = 1;
    header.reserved = 0;
    header.opcode = 1;
    header.mask = 1;
    header.payload_length = data.length < 126 ? data.length : data.length < 65537 ? 126 : 127;
    
    NSMutableData *fullData;
    
    if (header.payload_length == 126) // = 126 Short extended payload
    {
        struct { AMWebSocketBaseHeader header; AMWebSocketShortPayloadLength payload_length; uint32_t masking_key; } __attribute((packed)) packet = {header, {0}, 0};
        packet.payload_length.b1 = data.length >> 8;
        packet.payload_length.b2 = data.length;
        fullData = [NSMutableData dataWithBytes:&packet length:sizeof(packet)];
    }
    else if (header.payload_length == 127) // = 127 Long extended payload
    {
        struct { AMWebSocketBaseHeader header; AMWebSocketLongPayloadLength payload_length; uint32_t masking_key; } __attribute((packed)) packet = {header, {0}, 0};
        // More than 32 bits payload lengths are ignored at the moment, feel free to add it if you like.
        packet.payload_length.b5 = data.length >> 24;
        packet.payload_length.b6 = data.length >> 16;
        packet.payload_length.b7 = data.length >> 8;
        packet.payload_length.b8 = data.length;
        fullData = [NSMutableData dataWithBytes:&packet length:sizeof(packet)];
    }
    else // < 126 No extended payload
    {
        struct { AMWebSocketBaseHeader header; uint32_t masking_key; } __attribute((packed)) packet = {header, 0};
        fullData = [NSMutableData dataWithBytes:&packet length:sizeof(packet)];
    }
    
    [fullData appendData:data];
    [_socket writeData:fullData withTimeout:5 tag:AMWebSocketTagMessage];
}

- (NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutWriteWithTag:(long)tag elapsed:(NSTimeInterval)elapsed bytesDone:(NSUInteger)length;
{
    if (tag == AMWebSocketTagMessage)
    {
        [self notifyMessageWriteTimeout];
    }
    else if (tag == AMWebSocketTagHandshake)
    {
        [self notifyFailure:[NSNumber numberWithInt:AMWebSocketErrorHandshakeFailed]];
    }
    
    return -1;
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err;
{
    AMWebSocketLog(@"socketDidDisconnect: withError: %@", err);
    _connected = NO;
    [self notifyClosed];
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port;
{
    AMWebSocketLog(@"socket: didConnectToHost: %@ port: %d", host, port);
    if (self.configuration.ssl)
    {
        [sock startTLS:self.configuration.manualTrustEvaluation ? @{@"GCDAsyncSocketManuallyEvaluateTrust": @(YES)} : nil];
    }
    else
    {
        [self upgradeHTTPToWssOnSocket:sock];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didReceiveTrust:(SecTrustRef)trust completionHandler:(void (^)(BOOL shouldTrustPeer))completionHandler;
{
    AMWebSocketLog(@"socket: didReceiveTrust: completionHandler:");
    // TODO: Implement your own SSL pinning code here if you need it. For now I just accept everything.
    completionHandler(YES);
    return;
}

- (void)socketDidSecure:(GCDAsyncSocket *)sock;
{
    AMWebSocketLog(@"socketDidSecure:");
    [self upgradeHTTPToWssOnSocket:sock];
}

- (void)upgradeHTTPToWssOnSocket:(GCDAsyncSocket *)sock;
{
    NSString *requestPath = self.configuration.url.path;
    
    if (self.configuration.url.query)
    {
        requestPath = [requestPath stringByAppendingFormat:@"?%@", self.configuration.url.query];
    }
    
    NSMutableDictionary *additionalHeaders = [NSMutableDictionary dictionaryWithDictionary:self.configuration.additionalHeaders];
    
    if (self.configuration.origin)
    {
        [additionalHeaders setObject:self.configuration.origin forKey:@"Origin"];
    }
    
    if (self.configuration.secWebSocketProtocol)
    {
        [additionalHeaders setObject:self.configuration.secWebSocketProtocol forKey:@"Sec-WebSocket-Protocol"];
    }
    
    if (self.configuration.secWebSocketExtensions)
    {
        [additionalHeaders setObject:self.configuration.secWebSocketExtensions forKey:@"Sec-WebSocket-Extensions"];
    }
    
    NSMutableString *additionalHeadersString = [NSMutableString stringWithFormat:@""];
    
    for (NSString *key in additionalHeaders)
    {
        [additionalHeadersString appendString:[NSString stringWithFormat:@"%@: %@\r\n", key, additionalHeaders[key]]];
    }
    
    NSString *request = [NSString stringWithFormat:@"GET %@ HTTP/1.1\r\n"
                         "Host: %@\r\n"
                         "Upgrade: WebSocket\r\n"
                         "Connection: Upgrade\r\n"
                         "Sec-WebSocket-Key: %@\r\n"
                         "Sec-WebSocket-Version: %d\r\n"
                         "%@"
                         "\r\n",
                         requestPath, [NSString stringWithFormat:@"%@:%d", self.configuration.url.host, self.configuration.port], self.configuration.secWebSocketKey, self.configuration.secWebSocketVersion, additionalHeadersString];
    
    NSLog(@"%@", request);
    
    [_socket writeData:[request dataUsingEncoding:NSASCIIStringEncoding] withTimeout:5 tag:AMWebSocketTagHandshake];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag;
{
    AMWebSocketLog(@"socket: didWriteDataWithTag: %ld", tag);
    
    if (tag == AMWebSocketTagHandshake)
    {
        [sock readDataToData:[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding] withTimeout:-1 tag:AMWebSocketTagHandshake];
    }
    else if (tag == AMWebSocketTagMessage)
    {
        [self notifyMessageSent];
    }
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag;
{
    if (tag == AMWebSocketTagHandshake)
    {
        NSString *response = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
        AMWebSocketLog(@"Handshake response: %@", response);
        
        // Not the coolest handshake evaluation ever, but should work well enough.
        NSString *check1 = @"101";//@"HTTP/1.1 101";
        NSString *check2 = @"Sec-WebSocket-Accept:";
        
        if ([response containsString:check1] && [response containsString:check2])
        {
            _connected = YES;
            [self readNextMessage];
            [self notifyOpened];
        }
        else
        {
            [self notifyFailure:[NSNumber numberWithInt:AMWebSocketErrorHandshakeFailed]];
        }
    }
    else if (tag == AMWebSocketTagIncomingMessageHeader)
    {
        AMWebSocketLog(@"AMWebSocketTagIncomingMessageHeader");
        AMWebSocketBaseHeader header = { 0 };
        [data getBytes:&header length:2];
        
        // If we want to we can check the header.opcode to handle ping and stuff...
        AMWebSocketLog(@"Payload length: %d", header.payload_length);
        
        if (header.payload_length < 126) // No extended payload
        {
            [_socket readDataToLength:header.payload_length withTimeout:-1 tag:AMWebSocketTagIncomingMessagePayload];
        }
        else if (header.payload_length == 126) // Short extended payload
        {
            [_socket readDataToLength:2 withTimeout:-1 tag:AMWebSocketTagIncomingMessageShortPayloadLength];
        }
        else // (==127) Long extended payload
        {
            [_socket readDataToLength:8 withTimeout:-1 tag:AMWebSocketTagIncomingMessageLongPayloadLength];
        }
    }
    else if (tag == AMWebSocketTagIncomingMessageShortPayloadLength)
    {
        AMWebSocketLog(@"AMWebSocketTagIncomingMessageShortPayloadLength");
        AMWebSocketShortPayloadLength lp = { 0 };
        [data getBytes:&lp length:2];
        uint16_t payload_length = lp.b1 << 8 | lp.b2;
        AMWebSocketLog(@"Reading short extended payload of length: %d", payload_length);
        [_socket readDataToLength:payload_length withTimeout:-1 tag:AMWebSocketTagIncomingMessagePayload];
    }
    else if (tag == AMWebSocketTagIncomingMessageLongPayloadLength)
    {
        AMWebSocketLog(@"AMWebSocketTagIncomingMessageLongPayloadLength");
        AMWebSocketLongPayloadLength lp = { 0 };
        [data getBytes:&lp length:8];
        uint32_t payload_length = lp.b5 << 24 | lp.b6 << 16 | lp.b7 << 8 | lp.b8; // More than 32 bits payload lengths are ignored at the moment.
        AMWebSocketLog(@"Reading long extended payload of length: %d", payload_length);
        [_socket readDataToLength:payload_length withTimeout:-1 tag:AMWebSocketTagIncomingMessagePayload];
    }
    else if (tag == AMWebSocketTagIncomingMessagePayload)
    {
        AMWebSocketLog(@"AMWebSocketTagIncomingMessagePayload");
        [self notifyMessageReceived:data];
        [self readNextMessage];
    }
}

- (NSString *)host;
{
    return self.configuration.url.host;
}

@end

@implementation AMWebSocketConfiguration

+ (instancetype)configurationWithURLString:(NSString *)urlString ssl:(BOOL)ssl port:(int)port;
{
    return [[AMWebSocketConfiguration alloc] initWithURLString:urlString ssl:ssl port:port];
}

- (instancetype)initWithURLString:(NSString *)urlString ssl:(BOOL)ssl port:(int)port;
{
    self = [super init];
    
    if (self)
    {
        _url = [NSURL URLWithString:urlString];
        _ssl = ssl;
        _manualTrustEvaluation = NO;
        _port = port;
        _secWebSocketVersion = 13;
        uint8_t randBuf[16] = {0};
        arc4random_buf(randBuf, sizeof(randBuf));
        _secWebSocketKey = [[NSData dataWithBytes:randBuf length:sizeof(randBuf)] base64EncodedStringWithOptions:0]; // Randomly selected 16-byte value that has been base64-encoded according to the stadard.
    }
    
    return self;
}

@end
