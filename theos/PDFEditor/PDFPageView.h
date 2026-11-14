#import <UIKit/UIKit.h>
#import "Annotation.h"

typedef NS_ENUM(NSInteger, EditorTool) {
	EditorToolPencil = 0,
	EditorToolEraser = 1,
	EditorToolHighlighter = 2
};

@class PDFPageView;

@protocol PDFPageViewDelegate <NSObject>
- (void)pageView:(PDFPageView *)pageView didAddAnnotation:(Annotation *)annotation;
- (void)pageView:(PDFPageView *)pageView didRemoveAnnotation:(Annotation *)annotation;
@end

/**
 * Renderiza uma pagina PDF com CGPDFPage e permite desenhar por cima.
 * As anotacoes usam coordenadas normalizadas, entao funcionam em qualquer
 * tamanho de tela e tambem na exportacao para PDF.
 */
@interface PDFPageView : UIView

@property (nonatomic, assign) CGPDFPageRef page;
@property (nonatomic, assign) NSUInteger pageNumber;
@property (nonatomic, assign) EditorTool tool;
@property (nonatomic, strong) UIColor *strokeColor;
@property (nonatomic, assign) CGFloat strokeWidth;
@property (nonatomic, assign) CGFloat eraserWidth;
@property (nonatomic, strong) NSArray *annotations;
@property (nonatomic, weak) id<PDFPageViewDelegate> delegate;

/* Quando YES, o redesenho do traço e limitado a 30 FPS.
   Reduz bastante o consumo de CPU/GPU no iPad 2 sem perder suavidade.
   Os pontos do toque continuam sendo gravados todos, apenas o desenho
   acontece no maximo 30 vezes por segundo. */
@property (nonatomic, assign) BOOL throttleEnabled;

@end
