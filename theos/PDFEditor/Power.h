#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/* Avisado quando o modo Eco liga ou desliga. */
extern NSString *const PowerModeDidChangeNotification;

/*
 Gerenciador de economia de energia do app.

 Modo Eco (ativado pelo usuario na toolbar do editor):
   - Reduz o brilho da tela para 35% (restaurado ao desativar ou sair do app)
   - Limita o redesenho do traço a 30 FPS (economiza CPU/GPU no iPad 2)
   - Nao altera nenhuma funcionalidade: lápis, marcador, borracha e cores
     continuam iguais, apenas a taxa de quadros e o brilho mudam.

 Tudo e reversivel e seguro: o brilho original do sistema e guardado e
 devolvido exatamente como estava.
 */
@interface Power : NSObject

+ (instancetype)shared;

/* YES quando o modo Eco esta ativo.
   Alterar esta propriedade ja aplica o brilho: ao ligar, o brilho atual do
   sistema e guardado e a tela fica a 35%; ao desligar, o brilho original e
   devolvido exatamente como estava. */
@property (nonatomic, assign) BOOL ecoMode;

/* YES quando o redesenho do traço deve ser limitado a 30 FPS. */
@property (nonatomic, assign, readonly) BOOL throttleDrawing;

/* App indo para segundo plano: devolve o brilho ao sistema. */
- (void)suspendForBackground;

/* App voltando para primeiro plano: reaplica o brilho do modo Eco. */
- (void)resumeFromBackground;

@end
