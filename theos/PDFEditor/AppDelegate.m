#import "AppDelegate.h"
#import "DocumentListViewController.h"
#import "WebServer.h"
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

	// Servidor de importacao por rede: fica ativo enquanto o app esta aberto.
	WebServer *server = [WebServer sharedServer];
	BOOL started = [server startOnPort:8080];
	PDFLog(@"AppDelegate: servidor web %@ (erro=%@)", started ? @"ativo" : @"falhou", server.lastError);

	return YES;
}

@end
