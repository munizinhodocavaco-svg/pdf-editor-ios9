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

	/* ECONOMIA DE ENERGIA: o servidor web NAO sobe junto com o app.
	   Ele so e ligado quando o usuario abre a tela "Importar" (e desligado
	   ao sair dela, a menos que o usuario tenha ligado manualmente).
	   Mantendo o socket fechado o resto do tempo, o radio Wi-Fi do iPad 2
	   fica ocioso e a bateria dura muito mais. */
	PDFLog(@"AppDelegate: servidor web em espera (sobe na tela Importar)");

	return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	/* Volta do segundo plano: reaplica o brilho do modo Eco. */
	[[Power shared] resumeFromBackground];
}

- (void)applicationWillResignActive:(UIApplication *)application {
	/* Vai para segundo plano: devolve o brilho ao sistema e desliga o
	   servidor de rede (nada de ficar com o socket aberto sem uso). */
	[[Power shared] suspendForBackground];
	[[WebServer sharedServer] stop];
	PDFLog(@"AppDelegate: app inativo, servidor web desligado");
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
	[[Power shared] suspendForBackground];
	[[WebServer sharedServer] stop];
	PDFLog(@"AppDelegate: segundo plano");
}

@end
