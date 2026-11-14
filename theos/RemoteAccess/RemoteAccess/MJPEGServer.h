#import <Foundation/Foundation.h>

@interface MJPEGServer : NSObject

@property (nonatomic, assign) uint16_t port;
@property (nonatomic, assign, getter=isRunning) BOOL running;

- (instancetype)initWithPort:(uint16_t)port;
- (void)start;
- (void)stop;

@end