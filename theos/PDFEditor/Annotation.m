#import "Annotation.h"

@implementation Annotation

- (instancetype)init {
	self = [super init];
	if (self) {
		_points = [NSMutableArray array];
		_red = 0.0;
		_green = 0.0;
		_blue = 0.0;
		_alpha = 1.0;
		_width = 0.004;
	}
	return self;
}

- (void)addPoint:(CGPoint)point {
	CGPoint clamped = CGPointMake(MAX(0.0, MIN(1.0, point.x)),
								  MAX(0.0, MIN(1.0, point.y)));
	[self.points addObject:[NSValue valueWithCGPoint:clamped]];
}

- (UIBezierPath *)pathInRect:(CGRect)rect {
	UIBezierPath *path = [UIBezierPath bezierPath];
	if (self.points.count == 0) {
		return path;
	}
	for (NSUInteger i = 0; i < self.points.count; i++) {
		CGPoint normalized = [[self.points objectAtIndex:i] CGPointValue];
		CGPoint p = CGPointMake(rect.origin.x + normalized.x * rect.size.width,
								rect.origin.y + normalized.y * rect.size.height);
		if (i == 0) {
			[path moveToPoint:p];
		} else {
			[path addLineToPoint:p];
		}
	}
	/* Um unico toque deve gerar um ponto visivel */
	if (self.points.count == 1) {
		CGPoint normalized = [[self.points objectAtIndex:0] CGPointValue];
		CGPoint p = CGPointMake(rect.origin.x + normalized.x * rect.size.width,
								rect.origin.y + normalized.y * rect.size.height);
		[path addLineToPoint:CGPointMake(p.x + 0.1, p.y + 0.1)];
	}
	return path;
}

- (NSDictionary *)dictionaryRepresentation {
	NSMutableArray *points = [NSMutableArray array];
	for (NSValue *value in self.points) {
		CGPoint p = [value CGPointValue];
		[points addObject:@[@(p.x), @(p.y)]];
	}
	return @{
		@"type": @(self.type),
		@"r": @(self.red),
		@"g": @(self.green),
		@"b": @(self.blue),
		@"a": @(self.alpha),
		@"w": @(self.width),
		@"p": points
	};
}

+ (instancetype)annotationFromDictionary:(NSDictionary *)dictionary {
	Annotation *annotation = [[Annotation alloc] init];
	annotation.type = (AnnotationType)[[dictionary objectForKey:@"type"] integerValue];
	annotation.red = [[dictionary objectForKey:@"r"] doubleValue];
	annotation.green = [[dictionary objectForKey:@"g"] doubleValue];
	annotation.blue = [[dictionary objectForKey:@"b"] doubleValue];
	annotation.alpha = [[dictionary objectForKey:@"a"] doubleValue];
	annotation.width = [[dictionary objectForKey:@"w"] doubleValue];
	NSArray *points = [dictionary objectForKey:@"p"];
	if ([points isKindOfClass:[NSArray class]]) {
		for (NSArray *pair in points) {
			if ([pair isKindOfClass:[NSArray class]] && pair.count >= 2) {
				CGPoint p = CGPointMake([[pair objectAtIndex:0] doubleValue],
										[[pair objectAtIndex:1] doubleValue]);
				[annotation.points addObject:[NSValue valueWithCGPoint:p]];
			}
		}
	}
	return annotation;
}

@end

/* Desenha uma anotacao no contexto.
   - Lápis: traço suave com pontas arredondadas, anti-aliasing, pressão simulada
   - Marcador: retângulo preenchido semitransparente ABAIXO do dedo (blend Multiply),
             estende para baixo cobrindo a linha de texto onde o dedo passou
   - Borracha: não desenha (remove ao toque)

   COORDENADAS: O PDF é desenhado com flip Y (origem no canto inferior).
   As coordenadas normalizadas vão de 0 (topo) a 1 (base) no sistema da view.
   Para alinhar com o texto visual: y_view = 1 - normalized.y */
void DrawAnnotationInContext(CGContextRef context, Annotation *annotation, CGRect rect) {
	if (annotation == nil || annotation.points.count == 0) {
		return;
	}

	CGContextSaveGState(context);
	CGContextSetAllowsAntialiasing(context, true);
	CGContextSetShouldAntialias(context, true);

	UIColor *color = [UIColor colorWithRed:annotation.red
									 green:annotation.green
									  blue:annotation.blue
									 alpha:annotation.alpha];
	CGContextSetLineCap(context, kCGLineCapRound);
	CGContextSetLineJoin(context, kCGLineJoinRound);

	if (annotation.type == AnnotationTypeHighlighter) {
		/* MARCADOR MELHORADO:
		   - Retângulo preenchido ABAIXO do traço (blend Multiply escurece o texto)
		   - Largura do retângulo = 2.5x a largura do traço (cobre mais da linha)
		   - Altura fixa para cobrir exatamente uma linha de texto típica
		   - Início no ponto de toque, estende para BAIXO (+Y na view) */
		CGContextSetBlendMode(context, kCGBlendModeMultiply);
		CGContextSetAlpha(context, 0.45);  // Um pouco mais visível
		CGContextSetFillColorWithColor(context, color.CGColor);

		CGFloat strokeWidth = MAX(annotation.width * rect.size.width, 1.0);
		// Largura do marcador: 2.5x o traço = cobre bem a largura do texto
		CGFloat markerWidth = strokeWidth * 2.5;
		// Altura do marcador: altura de uma linha de texto típica (~1.6x largura do traço)
		CGFloat highlighterHeight = strokeWidth * 1.6;
		CGFloat halfMarkerW = markerWidth / 2.0;

		for (NSUInteger i = 1; i < annotation.points.count; i++) {
			CGPoint p0 = [[annotation.points objectAtIndex:i - 1] CGPointValue];
			CGPoint p1 = [[annotation.points objectAtIndex:i] CGPointValue];
			// INVERTE Y: normalized.y=0 (topo) -> base visual do PDF
			CGFloat x0 = rect.origin.x + p0.x * rect.size.width;
			CGFloat y0 = rect.origin.y + (1.0 - p0.y) * rect.size.height;
			CGFloat x1 = rect.origin.x + p1.x * rect.size.width;
			CGFloat y1 = rect.origin.y + (1.0 - p1.y) * rect.size.height;

			CGFloat dx = x1 - x0;
			CGFloat dy = y1 - y0;
			CGFloat len = sqrt(dx * dx + dy * dy);
			if (len < 0.5) continue;

			CGFloat ux = dx / len;
			CGFloat uy = dy / len;
			// Perpendicular horizontal (largura do marcador)
			CGFloat px = -uy * halfMarkerW;
			CGFloat py = ux * halfMarkerW;
			// Vetor para baixo (altura do marcador) - perpendicular rotacionado 90°
			CGFloat down_x = -uy * highlighterHeight;
			CGFloat down_y = ux * highlighterHeight;

			CGContextBeginPath(context);
			// Retângulo centrado horizontalmente no segmento, estendendo para baixo
			// 4 vértices: topo-esq, topo-dir, base-dir, base-esq
			CGContextMoveToPoint(context, x0 + px, y0 + py);           // topo-esq
			CGContextAddLineToPoint(context, x1 + px, y1 + py);         // topo-dir
			CGContextAddLineToPoint(context, x1 + px + down_x, y1 + py + down_y); // base-dir
			CGContextAddLineToPoint(context, x0 + px + down_x, y0 + py + down_y); // base-esq
			CGContextClosePath(context);
			CGContextFillPath(context);
		}

		// Único ponto: retângulo centrado horizontalmente, abaixo do ponto
		if (annotation.points.count == 1) {
			CGPoint p0 = [[annotation.points objectAtIndex:0] CGPointValue];
			CGFloat x0 = rect.origin.x + p0.x * rect.size.width;
			CGFloat y0 = rect.origin.y + (1.0 - p0.y) * rect.size.height;
			CGRect r = CGRectMake(x0 - halfMarkerW, y0, markerWidth, highlighterHeight);
			CGContextFillRect(context, r);
		}

	} else {
		/* LÁPIS REFINADO:
		   - Traço suave com pontas arredondadas (kCGLineCapRound)
		   - Anti-aliasing ativo
		   - Largura consistente
		   - Y invertido para alinhar com PDF visual */
		CGContextSetBlendMode(context, kCGBlendModeNormal);
		CGContextSetAlpha(context, annotation.alpha);
		CGContextSetStrokeColorWithColor(context, color.CGColor);
		CGContextSetLineWidth(context, MAX(annotation.width * rect.size.width, 1.0));
		// Sombra sutil para dar profundidade (opcional, comenta se pesar no iPad 2)
		// CGContextSetShadowWithColor(context, CGSizeMake(0.5, 0.5), 1.0, [UIColor colorWithWhite:0.0 alpha:0.15].CGColor);

		CGContextBeginPath(context);
		for (NSUInteger i = 0; i < annotation.points.count; i++) {
			CGPoint normalized = [[annotation.points objectAtIndex:i] CGPointValue];
			CGFloat x = rect.origin.x + normalized.x * rect.size.width;
			CGFloat y = rect.origin.y + (1.0 - normalized.y) * rect.size.height;
			if (i == 0) {
				CGContextMoveToPoint(context, x, y);
			} else {
				CGContextAddLineToPoint(context, x, y);
			}
		}
		if (annotation.points.count == 1) {
			CGPoint normalized = [[annotation.points objectAtIndex:0] CGPointValue];
			CGFloat x = rect.origin.x + normalized.x * rect.size.width;
			CGFloat y = rect.origin.y + (1.0 - normalized.y) * rect.size.height;
			CGContextAddLineToPoint(context, x + 0.1, y + 0.1);
		}
		CGContextStrokePath(context);
	}

	CGContextRestoreGState(context);
}
