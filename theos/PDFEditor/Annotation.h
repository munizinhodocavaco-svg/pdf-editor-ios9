#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSInteger, AnnotationType) {
	AnnotationTypePencil = 0,
	AnnotationTypeHighlighter = 1
};

/**
 * Uma anotacao (traco de lapis ou marcador de texto).
 * Os pontos sao normalizados (0..1) em relacao a area visivel da pagina,
 * de forma que continuem corretos em qualquer tamanho de tela ou exportacao.
 */
@interface Annotation : NSObject

@property (nonatomic, assign) AnnotationType type;
@property (nonatomic, assign) CGFloat red;
@property (nonatomic, assign) CGFloat green;
@property (nonatomic, assign) CGFloat blue;
@property (nonatomic, assign) CGFloat alpha;
@property (nonatomic, assign) CGFloat width; /* largura normalizada (fracao da largura da pagina) */
@property (nonatomic, strong, readonly) NSMutableArray *points;

- (void)addPoint:(CGPoint)point;
- (UIBezierPath *)pathInRect:(CGRect)rect;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)annotationFromDictionary:(NSDictionary *)dictionary;

@end

/* Desenha a anotacao num CGContext, usando coordenadas UIKit (origem no topo-esquerda). */
void DrawAnnotationInContext(CGContextRef context, Annotation *annotation, CGRect rect);
