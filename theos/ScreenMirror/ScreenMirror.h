#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ScreenMirror : NSObject

- (instancetype)initWithPort:(uint16_t)port;
- (void)start;
- (void)stop;

@end