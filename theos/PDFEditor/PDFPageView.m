#import "PDFPageView.h"

@interface PDFPageView ()
@property (nonatomic, strong) Annotation *currentAnnotation;
@property (nonatomic, assign) CGPoint lastPoint;
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
	[self setNeedsDisplay];
}

- (instancetype)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.backgroundColor = [UIColor whiteColor];
		self.strokeColor = [UIColor blackColor];
		self.strokeWidth = 3.0;
		self.tool = EditorToolPencil;
		self.annotations = @[];
		self.multipleTouchEnabled = NO;
	}
	return self;
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

- (void)drawRect:(CGRect)rect {
	CGContextRef context = UIGraphicsGetCurrentContext();

	[[UIColor whiteColor] setFill];
	CGContextFillRect(context, self.bounds);

	if (self.page == NULL) {
		return;
	}

	CGRect display = [self pageDisplayRect];
	CGRect pageRect = PageBoxRect(self.page);

	/* Desenha a pagina PDF (sistema de coordenadas do PDF tem origem embaixo). */
	CGContextSaveGState(context);
	CGContextTranslateCTM(context, display.origin.x, display.origin.y + display.size.height);
	CGContextScaleCTM(context, 1.0, -1.0);
	CGFloat scale = display.size.width / pageRect.size.width;
	CGContextScaleCTM(context, scale, scale);
	CGContextTranslateCTM(context, -pageRect.origin.x, -pageRect.origin.y);
	CGContextDrawPDFPage(context, self.page);
	CGContextRestoreGState(context);

	/* Borda da pagina */
	CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:0.75 alpha:1.0].CGColor);
	CGContextSetLineWidth(context, 1.0);
	CGContextStrokeRect(context, display);

	/* Marcador primeiro (fica por baixo do lapis). */
	NSArray *sorted = [self.annotations sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
		Annotation *a = (Annotation *)obj1;
		Annotation *b = (Annotation *)obj2;
		if (a.type == b.type) {
			return NSOrderedSame;
		}
		return (a.type < b.type) ? NSOrderedAscending : NSOrderedDescending;
	}];

	for (Annotation *annotation in sorted) {
		DrawAnnotationInContext(context, annotation, display);
	}

	if (self.currentAnnotation != nil) {
		DrawAnnotationInContext(context, self.currentAnnotation, display);
	}
}

- (CGPoint)normalizedPoint:(CGPoint)point inRect:(CGRect)rect {
	if (rect.size.width < 1.0 || rect.size.height < 1.0) {
		return CGPointZero;
	}
	return CGPointMake((point.x - rect.origin.x) / rect.size.width,
					   (point.y - rect.origin.y) / rect.size.height);
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
	[self setNeedsDisplay];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
	UITouch *touch = [touches anyObject];
	CGPoint point = [touch locationInView:self];

	if (self.tool == EditorToolEraser) {
		[self eraseAtPoint:point];
		return;
	}

	if (self.currentAnnotation == nil) {
		return;
	}

	CGFloat dx = point.x - self.lastPoint.x;
	CGFloat dy = point.y - self.lastPoint.y;
	if (sqrt(dx * dx + dy * dy) < 2.0) {
		return;
	}

	self.lastPoint = point;
	CGRect display = [self pageDisplayRect];
	[self.currentAnnotation addPoint:[self normalizedPoint:point inRect:display]];
	[self setNeedsDisplay];
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
	CGFloat tolerance = 12.0;
	if (annotation.type == AnnotationTypeHighlighter) {
		tolerance = 16.0;
	}

	CGPoint previous = CGPointZero;
	for (NSUInteger i = 0; i < annotation.points.count; i++) {
		CGPoint normalized = [[annotation.points objectAtIndex:i] CGPointValue];
		CGPoint current = CGPointMake(display.origin.x + normalized.x * display.size.width,
									  display.origin.y + normalized.y * display.size.height);
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
	[self setNeedsDisplay];
}

@end
