#import "AppDelegate.h"
#import "RootViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	@try {
		self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
		
		RootViewController *rootVC = [[RootViewController alloc] init];
		UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:rootVC];
		nav.navigationBar.barStyle = UIBarStyleBlack;
		
		self.window.rootViewController = nav;
		[self.window makeKeyAndVisible];
		
		return YES;
	}
	@catch (NSException *e) {
		NSLog(@"AppDelegate crashed: %@\n%@", e, [e callStackSymbols]);
		return NO;
	}
}

- (void)applicationWillResignActive:(UIApplication *)application {}
- (void)applicationDidEnterBackground:(UIApplication *)application {}
- (void)applicationWillEnterForeground:(UIApplication *)application {}
- (void)applicationDidBecomeActive:(UIApplication *)application {}
- (void)applicationWillTerminate:(UIApplication *)application {}

@end