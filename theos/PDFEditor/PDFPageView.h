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

@end
