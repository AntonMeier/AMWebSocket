# AMWebSocket

AMWebSocket is a light weight WebSocket client implementation written in Objective-C. It only contains the minimum required features to run a web socket so make sure that you test it properly before deploying it in anything critical. I made this because I wanted a staight-forward and minimalistic implementation.

**Dependencies**

The only third party code that you will need to include in your project is the GCDAsyncSocket.h and GCDAsyncSocket.m files of the CocoaAsyncSocket library: https://github.com/robbiehanson/CocoaAsyncSocket/tree/master/Source/GCD

**Usage**

```obj-c
AMWebSocketConfiguration *configuration = [AMWebSocketConfiguration configurationWithURLString:@"wss://192.168.1.30:1443/websocket" ssl:YES port:1443];

configuration.secWebSocketProtocol = @"some.protocol.string";
configuration.secWebSocketExtensions = @"permessage-deflate; client_max_window_bits";
configuration.additionalHeaders = @{
                                    @"X-My-App-Header": @"63323478-B503-49C6-A5B6-F79F8D2B5367"
                                    };

AMWebSocket *webSocket = [AMWebSocket webSocketWithConfiguration:configuration];
self.webSocket = webSocket; // Remember to keep reference

[webSocket openWithCompletion:^(NSError *error) {
  
  NSArray *jsonMessage = @[
	@{
      @"key1": @"value1",
      @"key2": @"value2"
    },
    @{
      @"hello": @"world"
    }
  ];
  
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonMessage options:0 error:nil];
  [webSocket sendData:jsonData completion:^(NSError *error, NSData *response) { // If you know that the server will immediately respond. Use with caution.
  
    id jsonResponse = [NSJSONSerialization JSONObjectWithData:response options:0 error:nil];
    NSLog(@"Got JSON response: %@", jsonResponse);
    
    [webSocket closeWithCompletion:^(NSError *error) {
      NSLog(@"Socket closed");
    }];
  }];
	
}];
```

Alternatively you can just set the delegate and receive the data as a callback:

```obj-c
webSocket.delegate = self;

[webSocket sendData:jsonData completion:nil]; // Keep completion nil;

- (void)socket:(AMWebSocket *)socket didReceiveData:(NSData *)data;
{
  NSLog(@"Data arrived!");
}

```

**Known limitations**

* Payload lengths longer than 32 bits are not supported. The WebSocket specification specifies up to 64 bits payloads, but unless you are sending individual packets lagrer than ~4 GB's each then you should be fine with just 32 bits. 
* All outgoing packets will have the Mask bit set to 1 and the Mask Data set to 0, thus resulting in "unmasked" data being sent. If you are concerned about possible network security issues then you can go ahead and implement the actual masking yourself.
* The Sec-WebSocket-Accept value calculated by the server is not validated by this client after the handshake.
* When closing the WebSocket, I just close the underlying TCP socket and don't bother to actually initiate the WebSocket Closing Handshake procedure.
* WebSocket ping/pong is not implemented, but it would be easy to add for anyone who needs it.
* WebSocket fragmended packets are not supporded.

**Licence**

Creative Commons
CC0 1.0 Universal