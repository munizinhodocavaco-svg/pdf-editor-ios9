#import <UIKit/UIKit.h>

@class VNCServer;
@class MJPEGServer;

@interface RootViewController : UIViewController

@property (nonatomic, strong) VNCServer *vncServer;
@property (nonatomic, strong) MJPEGServer *mjpegServer;
@property (nonatomic, strong) UILabel *ipLabel;
@property (nonatomic, strong) UISwitch *vncSwitch;
@property (nonatomic, strong) UISwitch *mjpegSwitch;
@property (nonatomic, strong) UILabel *vncStatusLabel;
@property (nonatomic, strong) UILabel *mjpegStatusLabel;

- (IBAction)vncToggled:(UISwitch *)sender;
- (IBAction)mjpegToggled:(UISwitch *)sender;
- (void)updateIPLabel;
- (void)updateStatusLabels;

@end