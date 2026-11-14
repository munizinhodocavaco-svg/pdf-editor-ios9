#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@protocol RemoteControlDelegate <NSObject>

/* Imagem da pagina atual (largura pedida) ou nil se nao houver PDF aberto. */
- (UIImage *)remotePageImageWithWidth:(CGFloat)width;

/* Estado do editor (dicionario com pagina, ferramenta, tamanho, cor...). */
- (NSDictionary *)remoteState;

/* Executa uma acao remota: undo, save, next, prev, tool, size, color, replace.
   Devolve YES se a acao foi executada. */
- (BOOL)remotePerformAction:(NSString *)action value:(NSString *)value;

/* Injeta um toque. O ponto vem em pixels da imagem enviada ao celular. */
- (void)remoteTouchAtPoint:(CGPoint)point phase:(NSInteger)phase;

@end

/*
 Controle remoto do editor via navegador do celular.

 O iPad 2 (iOS 9) roda o app com um servidor HTTP proprio. Este modulo
 transforma esse servidor em um controle remoto completo:

   /remote            -> pagina de controle (otimizada para celular)
   /remote/view.jpg   -> foto da pagina atual do PDF
   /remote/state      -> estado do editor em JSON
   /remote/touch      -> injeta um toque (desenhar/apagar)
   /remote/action     -> acoes (desfazer, salvar, trocar pagina, ferramenta...)

 Tudo funciona na mesma rede Wi-Fi, sem internet e sem instalar nada no
 celular: basta abrir o endereco no Safari do iPhone.
 */
@interface RemoteControl : NSObject

+ (instancetype)shared;

@property (nonatomic, weak) id<RemoteControlDelegate> delegate;

/* Pagina HTML de controle (gerada em tempo de execucao). */
+ (NSString *)controlPageHTML;

/* Dados da imagem da pagina atual (JPEG). nil se nao houver PDF aberto. */
- (NSData *)pageJPEGWithWidth:(CGFloat)width;

/* Estado do editor em JSON. */
- (NSData *)stateJSON;

/* Processa um toque remoto. */
- (void)handleTouchX:(double)x y:(double)y phase:(NSInteger)phase;

/* Processa uma acao remota. */
- (BOOL)handleAction:(NSString *)action value:(NSString *)value;

@end
