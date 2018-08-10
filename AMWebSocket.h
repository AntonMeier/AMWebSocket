//
//  AMWebSocket.h
//  AM
//
//  Created by Anton Meier on 2018-08-01.
//  Creative Commons CC0 1.0 Licence
//

#import <Foundation/Foundation.h>

@class AMWebSocketConfiguration;

enum
{
    AMWebSocketErrorConnectionFailed = 1,
    AMWebSocketErrorHandshakeFailed = 2
};

extern NSString * const AMWebSocketErrorDomain;

@protocol AMWebSocketDelegate;

@interface AMWebSocket : NSObject

@property (readonly) BOOL connected;
@property (readonly) NSString *host;
@property (weak, nonatomic, nullable) id<AMWebSocketDelegate> delegate; // Optional

+ (instancetype)webSocketWithConfiguration:(AMWebSocketConfiguration *)configuration;
- (instancetype)initWithConfiguration:(AMWebSocketConfiguration *)configuration;

- (void)openWithCompletion:(void (^)(NSError *error))completion;
- (void)closeWithCompletion:(void (^)(NSError *error))completion;
- (void)close;
- (void)sendData:(NSData *)data completion:(void (^)(NSError *error, NSData *response))completion;

@end

@protocol AMWebSocketDelegate <NSObject>

@optional

// Optional. You may be able to use the completion handler in the sendData method insted if you know that your server will only send one response per message sent to it.
- (void)socket:(AMWebSocket *)socket didReceiveData:(NSData *)data;

@end

@interface AMWebSocketConfiguration : NSObject

+ (instancetype)configurationWithURLString:(NSString *)urlString ssl:(BOOL)ssl port:(int)port;
- (instancetype)initWithURLString:(NSString *)urlString ssl:(BOOL)ssl port:(int)port;

// - Connection settings -

@property (nonatomic, readwrite, strong) NSURL *url;
@property (readwrite) BOOL ssl;
// If you wish to evaluate the certificates yourself then set manualTrustEvaluation in addition to the ssl flag.
// You will have to implement the validation code yourself in the socket:didReceiveTrust:completionHandler: method in AMWebSocket.m.
@property (readwrite) BOOL manualTrustEvaluation;
@property (readwrite) int port; // Setting this to 0 will result in either port 80 or 443 being used depending on ssl setting

// - Optional HTTP Headers -

@property (nonatomic, readwrite, strong) NSString *secWebSocketProtocol;    // Not included if nil
@property (nonatomic, readwrite, strong) NSString *secWebSocketKey;         // Defaults to randomized base64 string
@property (nonatomic, readwrite, strong) NSString *secWebSocketExtensions;  // Semicolon separated string, ex: "permessage-deflate; client_max_window_bits". Not included if nil.
@property (nonatomic, readwrite, strong) NSString *origin;                  // Not included if nil
@property (nonatomic) int secWebSocketVersion;                              // Defaults to 13

@property (nonatomic, readwrite, strong) NSDictionary *additionalHeaders;   // Any other headers that you wish to include, ex: "X-My-Header": "my-value"

@end





