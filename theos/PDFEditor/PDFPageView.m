#import "PDFPageView.h"
#import <math.h>

@interface PDFPageView () {
	/* Pagina PDF renderizada uma unica vez por tamanho de tela. Sem isso o
	   CGContextDrawPDFPage rodava a cada toque, o que travava o iPad 2. */
	CGImageRef _pageImage;
	CGSize _pageImageSize;
	/* Pagina + tracos ja concluidos. Durante um traco novo so ele e desenhado
	   por cima, entao o custo por quadro nao cresce com a quantidade de tracos. */
	CGImageRef _compositeImage;
	CGSize _compositeSize;
	/* Cursor visual da borracha (circulo que segue o dedo). */
	UIView *_eraserCursor;
}

@property (nonatomic, strong) Annotation *currentAnnotation;
@property (nonatomic, assign) CGPoint lastPoint;
@property (nonatomic, strong) NSArray *sortedAnnotations;

- (void)invalidatePageImage;
- (void)invalidateCompositeImage;
- (void)updateEraserCursorAtPoint:(CGPoint)point;
- (void)hideEraserCursor;

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

		/* Cursor da borracha: circulo tracejado que segue o dedo. */
		_eraserCursor = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
		_eraserCursor.hidden = YES;
		_eraserCursor.userInteractionEnabled = NO;
		_eraserCursor.backgroundColor = [UIColor clearColor];
		_eraserCursor.layer.borderColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.9].CGColor;
		_eraserCursor.layer.borderWidth = 2.0;
		_eraserCursor.layer.cornerRadius = 14.0;
		_eraserCursor.layer.borderDashPattern = @[@4, @3];
		[self addSubview:_eraserCursor];
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

#pragma mark - Cursor da Borracha

- (void)updateEraserCursorAtPoint:(CGPoint)point {
	if (self.tool != EditorToolEraser) {
		[self hideEraserCursor];
		return;
	}
	CGRect display = [self pageDisplayRect];
	// So mostra se estiver sobre a pagina
	if (!CGRectContainsPoint(display, point)) {
		[self hideEraserCursor];
		return;
	}
	CGFloat radius = self.eraserWidth / 2.0 + 6.0; // raio visual um pouco maior que a area de apagamento
	_eraserCursor.frame = CGRectMake(point.x - radius, point.y - radius, radius * 2.0, radius * 2.0);
	_eraserCursor.hidden = NO;
	// Atualiza cor da borda para combinar com a cor do lapis atual (feedback visual)
	_eraserCursor.layer.borderColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.9].CGColor;
}

- (void)hideEraserCursor {
	_eraserCursor.hidden = YES;
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
		[self updateEraserCursorAtPoint:point];
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

	if (!CGRectIsNull(dirty)) {
		[self setNeedsDisplayInRect:dirty];
	}
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

	[self setNeedsDisplay];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
	self.currentAnnotation = nil;
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
		tolerance += 4.0;
	}

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
