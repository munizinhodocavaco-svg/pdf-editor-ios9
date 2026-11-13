#import <Foundation/Foundation.h>

/* Avisado sempre que um arquivo entra ou sai da pasta Documents. */
extern NSString *const WebServerFilesDidChangeNotification;

/* Servidor HTTP/WebDAV embutido: permite enviar PDFs pelo navegador do PC ou
   montar a pasta do app como unidade de rede (WebDAV) usando o IP do iPad. */
@interface WebServer : NSObject

@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) NSString *lastError;

+ (instancetype)sharedServer;

/* IP do iPad na rede Wi-Fi (nil se estiver sem rede). */
+ (NSString *)deviceIPAddress;

- (BOOL)startOnPort:(uint16_t)port;
- (void)stop;

@end
