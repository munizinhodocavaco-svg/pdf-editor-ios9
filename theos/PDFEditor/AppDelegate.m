#import "AppDelegate.h"
#import "DocumentListViewController.h"
#import "Log.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	PDFLog(@"AppDelegate: didFinishLaunching inicio");
	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	PDFLog(@"AppDelegate: janela criada %@", NSStringFromCGRect(self.window.frame));

	DocumentListViewController *list = [[DocumentListViewController alloc] init];
	PDFLog(@"AppDelegate: lista criada");
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
	self.window.rootViewController = nav;
	PDFLog(@"AppDelegate: rootViewController definido");

	self.window.backgroundColor = [UIColor whiteColor];
	[self.window makeKeyAndVisible];
	PDFLog(@"AppDelegate: janela visivel");
	return YES;
}

@end
