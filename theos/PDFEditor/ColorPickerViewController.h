#import <UIKit/UIKit.h>

/* Seletor de cores com espectro (matiz + saturacao/brilho), no estilo do
   "Escolher cor" do iOS. Usado porque o UIColorPickerViewController so existe
   a partir do iOS 14. */
@interface ColorPickerViewController : UIViewController

@property (nonatomic, strong) UIColor *initialColor;
/* Chamado quando o usuario confirma a cor escolhida. */
@property (nonatomic, copy) void (^onColorSelected)(UIColor *color);

@end
