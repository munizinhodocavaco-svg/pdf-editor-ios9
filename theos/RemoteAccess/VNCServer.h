#import <Foundation/Foundation.h>

@interface VNCServer : NSObject

@property (nonatomic, assign) uint16_t port;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, assign) BOOL running;

- (instancetype)initWithPort:(uint16_t)port password:(NSString *)password;
- (void)start;
- (void)stop;

@end