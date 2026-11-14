#import <Foundation/Foundation.h>
#import "Annotation.h"

/**
 * Guarda as anotacoes por pagina e salva/carrega automaticamente em
 * <pdf>.annotations.json ao lado do proprio PDF.
 */
@interface AnnotationStore : NSObject

@property (nonatomic, strong, readonly) NSURL *pdfURL;

- (instancetype)initWithPDFURL:(NSURL *)pdfURL;
- (NSArray *)annotationsForPage:(NSUInteger)page; /* pagina comeca em 1 */
- (void)addAnnotation:(Annotation *)annotation toPage:(NSUInteger)page;
- (void)removeAnnotation:(Annotation *)annotation fromPage:(NSUInteger)page;
- (void)save;
/* Grava na hora (sem esperar o agrupamento). Usado ao sair do app. */
- (void)flushNow;
- (void)load;

@end
