#import <Foundation/Foundation.h>

@interface MJPEGServer : NSObject

@property (nonatomic, assign) uint16_t port;
@property (nonatomic, assign) BOOL running;

- (instancetype)initWithPort:(uint16_t)port;
- (void)start;
- (void)stop;

@end