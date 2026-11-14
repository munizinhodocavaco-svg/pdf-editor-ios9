#import "PDFPageView.h"
#import <math.h>
#import <QuartzCore/QuartzCore.h>

@interface PDFPageView () {
	/* Pagina PDF renderizada uma unica vez por tamanho de tela. Sem isso o
	   CGContextDrawPDFPage rodava a cada toque, o que travava o iPad 2. */
	CGImageRef _pageImage;
	CGSize _pageImageSize;
	/* Pagina + tracos ja concluidos. Durante um traco novo so ele e desenhado
	   por cima, entao o custo por quadro nao cresce com a quantidade de tracos. */
	CGImageRef _compositeImage;
	CGSize _compositeSize;
}

@property (nonatomic, strong) Annotation *currentAnnotation;
@property (nonatomic, assign) CGPoint lastPoint;
@property (nonatomic, strong) NSArray *sortedAnnotations;

/* Controle do throttle (modo Eco): limita o redesenho a 30 FPS. */
@property (nonatomic, assign) NSTimeInterval lastDrawTimestamp;
@property (nonatomic, assign) CGRect pendingDirtyRect;

- (void)invalidatePageImage;
- (void)invalidateCompositeImage;

@end

@implementation PDFPageView

static CGRect PageBoxRect(CGPDFPageRef page) {
	CGRect rect = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
	if (rect.size.width < 1.0 || rect.size.height < 1.0) {
		rect = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
	}
	return rect;
}

- (void)dealloc {
	if (_compositeImage != NULL) {
		CGImageRelease(_compositeImage);
		_compositeImage = NULL;
	}
	if (_pageImage != NULL) {
		CGImageRelease(_pageImage);
		_pageImage = NULL;
	}
	if (_page != NULL) {
		CGPDFPageRelease(_page);
		_page = NULL;
	}
}

- (void)setPage:(CGPDFPageRef)page {
	if (_page == page) {
		return;
	}
	if (_page != NULL) {
		CGPDFPageRelease(_page);
		_page = NULL;
	}
	if (page != NULL) {
		_page = CGPDFPageRetain(page);
	}
	[self invalidatePageImage];
}

- (void)setAnnotations:(NSArray *)annotations {
	_annotations = [annotations copy];
	/* Ordena uma vez (marcador atras do lapis) em vez de ordenar a cada quadro. */
	self.sortedAnnotations = [_annotations sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
		Annotation *a = (Annotation *)obj1;
		Annotation *b = (Annotation *)obj2;
		if (a.type == b.type) {
			return NSOrderedSame;
		}
		return (a.type < b.type) ? NSOrderedAscending : NSOrderedDescending;
	}];
	[self invalidateCompositeImage];
	[self setNeedsDisplay];
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor whiteColor];
		self.opaque = YES;
		self.clearsContextBeforeDrawing = NO;
		self.strokeColor = [UIColor blackColor];
		self.strokeWidth = 2.5;
		self.eraserWidth = 12.0;
		self.tool = EditorToolPencil;
		self.multipleTouchEnabled = NO;
		self.annotations = @[];
	}
	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	if (_pageImage != NULL && !CGSizeEqualToSize(_pageImageSize, self.bounds.size)) {
		[self invalidatePageImage];
	}
}

- (void)invalidatePageImage {
	if (_pageImage != NULL) {
		CGImageRelease(_pageImage);
		_pageImage = NULL;
	}
	_pageImageSize = CGSizeZero;
	[self invalidateCompositeImage];
	[self setNeedsDisplay];
}

- (void)invalidateCompositeImage {
	if (_compositeImage != NULL) {
		CGImageRelease(_compositeImage);
		_compositeImage = NULL;
	}
	_compositeSize = CGSizeZero;
}

/* Retangulo, em coordenadas da view, onde a pagina PDF e desenhada. */
- (CGRect)pageDisplayRect {
	if (self.page == NULL) {
		return self.bounds;
	}
	CGRect pageRect = PageBoxRect(self.page);
	if (pageRect.size.width < 1.0 || pageRect.size.height < 1.0) {
		return self.bounds;
	}
	CGFloat scale = MIN(self.bounds.size.width / pageRect.size.width,
						self.bounds.size.height / pageRect.size.height);
	CGSize size = CGSizeMake(pageRect.size.width * scale, pageRect.size.height * scale);
	return CGRectMake((self.bounds.size.width - size.width) / 2.0,
					  (self.bounds.size.height - size.height) / 2.0,
					  size.width, size.height);
}

#pragma mark - Cache da pagina

/* Renderiza a pagina para um CGImage (fundo branco + PDF + borda) e reaproveita
   nos quadros seguintes. Tambem evita o custo de desenhar o PDF durante o traco. */
- (CGImageRef)cachedPageImage {
	CGSize size = self.bounds.size;
	if (size.width < 1.0 || size.height < 1.0) {
		return NULL;
	}
	if (_pageImage != NULL && CGSizeEqualToSize(_pageImageSize, size)) {
		return _pageImage;
	}
	if (_pageImage != NULL) {
		CGImageRelease(_pageImage);
		_pageImage = NULL;
	}

	UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
	CGContextFillRect(context, CGRectMake(0.0, 0.0, size.width, size.height));

	CGRect display = [self pageDisplayRect];
	if (self.page != NULL) {
		CGRect pageRect = PageBoxRect(self.page);
		CGContextSaveGState(context);
		CGContextTranslateCTM(context, display.origin.x, display.origin.y + display.size.height);
		CGContextScaleCTM(context, 1.0, -1.0);
		CGFloat scale = display.size.width / pageRect.size.width;
		CGContextScaleCTM(context, scale, scale);
		CGContextTranslateCTM(context, -pageRect.origin.x, -pageRect.origin.y);
		CGContextDrawPDFPage(context, self.page);
		CGContextRestoreGState(context);
	}

	CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:0.75 alpha:1.0].CGColor);
	CGContextSetLineWidth(context, 1.0);
	CGContextStrokeRect(context, CGRectInset(display, 0.5, 0.5));

	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	if (image.CGImage != NULL) {
		_pageImage = CGImageRetain(image.CGImage);
		_pageImageSize = size;
	}
	UIGraphicsEndImageContext();
	return _pageImage;
}

- (void)drawAnnotatedPageInContext:(CGContextRef)context {
	CGImageRef page = [self cachedPageImage];
	CGRect display = [self pageDisplayRect];
	if (page != NULL) {
		CGContextSetInterpolationQuality(context, kCGInterpolationNone);
		CGContextDrawImage(context, self.bounds, page);
	} else {
		CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
		CGContextFillRect(context, self.bounds);
	}
	/* Marcador primeiro (fica por baixo do lapis). */
	for (Annotation *annotation in self.sortedAnnotations) {
		DrawAnnotationInContext(context, annotation, display);
	}
}

/* Pagina + tracos concluidos, pronta para ser "colada" a cada quadro. */
- (CGImageRef)cachedCompositeImage {
	CGSize size = self.bounds.size;
	if (size.width < 1.0 || size.height < 1.0) {
		return NULL;
	}
	if (_compositeImage != NULL && CGSizeEqualToSize(_compositeSize, size)) {
		return _compositeImage;
	}
	if (_compositeImage != NULL) {
		CGImageRelease(_compositeImage);
		_compositeImage = NULL;
	}

	UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
	CGContextRef context = UIGraphicsGetCurrentContext();
	[self drawAnnotatedPageInContext:context];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	if (image.CGImage != NULL) {
		_compositeImage = CGImageRetain(image.CGImage);
		_compositeSize = size;
	}
	UIGraphicsEndImageContext();
	return _compositeImage;
}

- (void)drawRect:(CGRect)rect {
	CGContextRef context = UIGraphicsGetCurrentContext();

	CGImageRef image = [self cachedCompositeImage];
	if (image != NULL) {
		CGContextSetInterpolationQuality(context, kCGInterpolationNone);
		CGContextDrawImage(context, self.bounds, image);
	} else {
		CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
		CGContextFillRect(context, rect);
	}

	/* Somente o traco em andamento e redesenhado a cada movimento. */
	if (self.currentAnnotation != nil) {
		DrawAnnotationInContext(context, self.currentAnnotation, [self pageDisplayRect]);
	}
}

#pragma mark - Toques

- (CGPoint)normalizedPoint:(CGPoint)point inRect:(CGRect)rect {
	if (rect.size.width < 1.0 || rect.size.height < 1.0) {
		return CGPointZero;
	}
	return CGPointMake((point.x - rect.origin.x) / rect.size.width,
					   (point.y - rect.origin.y) / rect.size.height);
}

/* Margem extra em volta do segmento recem-desenhado; so essa area e repintada. */
- (CGFloat)dirtyPadding {
	CGFloat width = (self.tool == EditorToolHighlighter) ? MAX(self.strokeWidth * 4.0, 14.0) : self.strokeWidth;
	return width / 2.0 + 8.0;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
	UITouch *touch = [touches anyObject];
	CGPoint point = [touch locationInView:self];
	CGRect display = [self pageDisplayRect];

	if (!CGRectContainsPoint(display, point)) {
		return;
	}

	if (self.tool == EditorToolEraser) {
		[self eraseAtPoint:point];
		return;
	}

	Annotation *annotation = [[Annotation alloc] init];
	annotation.type = (self.tool == EditorToolHighlighter) ? AnnotationTypeHighlighter : AnnotationTypePencil;

	CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 1.0;
	if ([self.strokeColor getRed:&red green:&green blue:&blue alpha:&alpha]) {
		annotation.red = red;
		annotation.green = green;
		annotation.blue = blue;
		annotation.alpha = alpha;
	}

	CGFloat screenWidth = (self.tool == EditorToolHighlighter) ? MAX(self.strokeWidth * 4.0, 14.0) : self.strokeWidth;
	annotation.width = screenWidth / display.size.width;

	self.lastPoint = point;
	[annotation addPoint:[self normalizedPoint:point inRect:display]];
	self.currentAnnotation = annotation;

	CGFloat padding = [self dirtyPadding];
	[self setNeedsDisplayInRect:CGRectInset(CGRectMake(point.x, point.y, 0.5, 0.5), -padding, -padding)];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
	UITouch *touch = [touches anyObject];

	if (self.tool == EditorToolEraser) {
		[self eraseAtPoint:[touch locationInView:self]];
		return;
	}

	if (self.currentAnnotation == nil) {
		return;
	}

	CGRect display = [self pageDisplayRect];
	CGFloat padding = [self dirtyPadding];

	/* coalescedTouchesForTouch entrega todos os pontos que o sistema capturou
	   entre dois quadros: traco mais suave sem custo extra de renderizacao. */
	NSArray *samples = [event coalescedTouchesForTouch:touch];
	if (samples.count == 0) {
		samples = @[touch];
	}

	CGRect dirty = CGRectNull;
	for (UITouch *sample in samples) {
		CGPoint point = [sample locationInView:self];
		CGFloat dx = point.x - self.lastPoint.x;
		CGFloat dy = point.y - self.lastPoint.y;
		if (sqrt(dx * dx + dy * dy) < 1.5) {
			continue;
		}

		CGRect segment = CGRectMake(MIN(self.lastPoint.x, point.x) - padding,
									MIN(self.lastPoint.y, point.y) - padding,
									fabs(dx) + padding * 2.0,
									fabs(dy) + padding * 2.0);
		dirty = CGRectIsNull(dirty) ? segment : CGRectUnion(dirty, segment);

		self.lastPoint = point;
		[self.currentAnnotation addPoint:[self normalizedPoint:point inRect:display]];
	}

	if (CGRectIsNull(dirty)) {
		return;
	}

	/* MODO ECO: limita o redesenho a 30 FPS. Todos os pontos continuam sendo
	   gravados no traco, apenas o desenho e adiado (o proximo quadro mostra
	   o traço completo ate ali). Reduz o consumo de CPU/GPU no iPad 2. */
	if (self.throttleEnabled) {
		NSTimeInterval now = CACurrentMediaTime();
		if (now - self.lastDrawTimestamp < (1.0 / 30.0)) {
			// Ainda dentro do intervalo: guarda a area suja para o proximo quadro.
			self.pendingDirtyRect = CGRectIsNull(self.pendingDirtyRect)
				? dirty
				: CGRectUnion(self.pendingDirtyRect, dirty);
			return;
		}
		self.lastDrawTimestamp = now;
	}

	if (!CGRectIsNull(self.pendingDirtyRect)) {
		dirty = CGRectUnion(dirty, self.pendingDirtyRect);
		self.pendingDirtyRect = CGRectNull;
	}

	[self setNeedsDisplayInRect:dirty];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
	if (self.currentAnnotation == nil) {
		return;
	}

	Annotation *finished = self.currentAnnotation;
	self.currentAnnotation = nil;

	if (finished.points.count > 0) {
		NSMutableArray *updated = [NSMutableArray arrayWithArray:self.annotations];
		[updated addObject:finished];
		self.annotations = updated;
		[self.delegate pageView:self didAddAnnotation:finished];
	}

	/* Garante que a ultima parte do traco (adiada pelo throttle) apareca. */
	self.pendingDirtyRect = CGRectNull;
	[self setNeedsDisplay];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
	self.currentAnnotation = nil;
	self.pendingDirtyRect = CGRectNull;
	[self setNeedsDisplay];
}

#pragma mark - Borracha

static CGFloat DistanceToSegment(CGPoint point, CGPoint start, CGPoint end) {
	CGFloat dx = end.x - start.x;
	CGFloat dy = end.y - start.y;
	if (dx == 0.0 && dy == 0.0) {
		dx = point.x - start.x;
		dy = point.y - start.y;
		return sqrt(dx * dx + dy * dy);
	}
	CGFloat t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy);
	t = MAX(0.0, MIN(1.0, t));
	CGFloat px = start.x + t * dx;
	CGFloat py = start.y + t * dy;
	dx = point.x - px;
	dy = point.y - py;
	return sqrt(dx * dx + dy * dy);
}

- (BOOL)annotation:(Annotation *)annotation hitsPoint:(CGPoint)point {
	CGRect display = [self pageDisplayRect];
	/* A borracha acompanha o tamanho escolhido (1x, 2x, 3x). */
	CGFloat tolerance = MAX(6.0, self.eraserWidth * 0.5 + 6.0);

	if (annotation.type == AnnotationTypeHighlighter) {
		/* MARCADOR: hit-test no retângulo real desenhado (estende para baixo do traço).
		   O marcador desenha retângulos CENTRADOS horizontalmente no segmento,
		   com largura 2.5x o traço e altura 1.6x o traço, estendendo para BAIXO (+Y).
		   Verificamos se o ponto está dentro de qualquer um desses retângulos. */
		CGFloat strokeWidth = MAX(4.0 * display.size.width * [annotation width], 1.0);
		CGFloat markerWidth = strokeWidth * 2.5;
		CGFloat highlighterHeight = strokeWidth * 1.6;
		CGFloat halfMarkerW = markerWidth / 2.0;

		for (NSUInteger i = 1; i < annotation.points.count; i++) {
			CGPoint p0 = [[annotation.points objectAtIndex:i - 1] CGPointValue];
			CGPoint p1 = [[annotation.points objectAtIndex:i] CGPointValue];
			// INVERTE Y: normalizado -> coordenadas da view (mesmo que DrawAnnotationInContext)
			CGFloat x0 = display.origin.x + p0.x * display.size.width;
			CGFloat y0 = display.origin.y + (1.0 - p0.y) * display.size.height;
			CGFloat x1 = display.origin.x + p1.x * display.size.width;
			CGFloat y1 = display.origin.y + (1.0 - p1.y) * display.size.height;

			CGFloat dx = x1 - x0;
			CGFloat dy = y1 - y0;
			CGFloat len = sqrt(dx * dx + dy * dy);
			if (len < 0.5) continue;

			CGFloat ux = dx / len;
			CGFloat uy = dy / len;
			// Perpendicular horizontal (largura do marcador)
			CGFloat px = -uy * halfMarkerW;
			CGFloat py = ux * halfMarkerW;
			// Vetor para baixo (altura do marcador)
			CGFloat down_x = -uy * highlighterHeight;
			CGFloat down_y = ux * highlighterHeight;

			// Verifica se o ponto está dentro do quadrilátero do marcador
			// 4 vértices: topo-esq, topo-dir, base-dir, base-esq
			CGPoint verts[4] = {
				{x0 + px, y0 + py},                          // topo-esq
				{x1 + px, y1 + py},                          // topo-dir
				{x1 + px + down_x, y1 + py + down_y},        // base-dir
				{x0 + px + down_x, y0 + py + down_y}         // base-esq
			};
			if ([self pointInConvexQuad:point vertices:verts]) {
				return YES;
			}
		}

		// Único ponto: retângulo centrado horizontalmente, abaixo do ponto
		if (annotation.points.count == 1) {
			CGPoint p0 = [[annotation.points objectAtIndex:0] CGPointValue];
			CGFloat x0 = display.origin.x + p0.x * display.size.width;
			CGFloat y0 = display.origin.y + (1.0 - p0.y) * display.size.height;
			CGRect r = CGRectMake(x0 - halfMarkerW, y0, markerWidth, highlighterHeight);
			if (CGRectContainsPoint(r, point)) {
				return YES;
			}
		}
		return NO;
	} else {
		/* LÁPIS: hit-test na linha central com tolerância. */
		CGPoint previous = CGPointZero;
		for (NSUInteger i = 0; i < annotation.points.count; i++) {
			CGPoint normalized = [[annotation.points objectAtIndex:i] CGPointValue];
			// INVERTE Y para coincidir com o desenho das anotacoes
			CGPoint current = CGPointMake(display.origin.x + normalized.x * display.size.width,
										  display.origin.y + (1.0 - normalized.y) * display.size.height);
			if (i > 0 && DistanceToSegment(point, previous, current) <= tolerance) {
				return YES;
			}
			previous = current;
		}
		return NO;
	}
}

/* Testa se ponto está dentro de quadrilátero convexo (4 vértices em ordem). */
- (BOOL)pointInConvexQuad:(CGPoint)p vertices:(CGPoint[4])v {
	// Produto vetorial para verificar se está do mesmo lado de todas as arestas
	BOOL pos = NO, neg = NO;
	for (int i = 0; i < 4; i++) {
		CGPoint a = v[i];
		CGPoint b = v[(i + 1) % 4];
		CGFloat cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
		if (cross > 0) pos = YES;
		if (cross < 0) neg = YES;
		if (pos && neg) return NO;
	}
	return YES;
}

- (void)eraseAtPoint:(CGPoint)point {
	NSMutableArray *remaining = [NSMutableArray array];
	NSMutableArray *removed = [NSMutableArray array];

	for (Annotation *annotation in self.annotations) {
		if ([self annotation:annotation hitsPoint:point]) {
			[removed addObject:annotation];
		} else {
			[remaining addObject:annotation];
		}
	}

	if (removed.count == 0) {
		return;
	}

	self.annotations = remaining;
	for (Annotation *annotation in removed) {
		[self.delegate pageView:self didRemoveAnnotation:annotation];
	}
}

@end
