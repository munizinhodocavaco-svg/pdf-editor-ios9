#import "AppDelegate.h"
#import "DocumentListViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	DocumentListViewController *list = [[DocumentListViewController alloc] init];
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
	self.window.rootViewController = nav;
	self.window.backgroundColor = [UIColor whiteColor];
	[self.window makeKeyAndVisible];
	return YES;
}

@end
