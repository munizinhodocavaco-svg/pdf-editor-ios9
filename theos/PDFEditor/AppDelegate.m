#import "AppDelegate.h"
#import "DocumentListViewController.h"
#import "WebServer.h"
#import "Power.h"
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

	/* Servidor de rede no ar o tempo todo em que o app esta aberto:
	   e por ele que o celular (iPhone) controla o editor e envia arquivos.
	   Ele desliga sozinho quando o app vai para o segundo plano. */
	WebServer *server = [WebServer sharedServer];
	BOOL started = [server startOnPort:8080];
	PDFLog(@"AppDelegate: servidor web %@ (erro=%@)", started ? @"ativo" : @"falhou", server.lastError);

	return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	/* Volta do segundo plano: reaplica o brilho do modo Eco. */
	[[Power shared] resumeFromBackground];
	[[WebServer sharedServer] startOnPort:8080];
}

- (void)applicationWillResignActive:(UIApplication *)application {
	/* Sai do app: devolve o brilho ao sistema.
	   O servidor web NAO e parado aqui: o controle remoto pelo celular
	   precisa continuar funcionando enquanto o app esta em primeiro plano. */
	[[Power shared] suspendForBackground];
	PDFLog(@"AppDelegate: app inativo");
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
	[[Power shared] suspendForBackground];
	[[WebServer sharedServer] stop];
	PDFLog(@"AppDelegate: segundo plano");
}

@end
