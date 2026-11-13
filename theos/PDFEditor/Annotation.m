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

void DrawAnnotationInContext(CGContextRef context, Annotation *annotation, CGRect rect) {
	if (annotation == nil || annotation.points.count == 0) {
		return;
	}

	CGContextSaveGState(context);

	UIColor *color = [UIColor colorWithRed:annotation.red
									 green:annotation.green
									  blue:annotation.blue
									 alpha:annotation.alpha];
	CGContextSetStrokeColorWithColor(context, color.CGColor);
	CGContextSetLineWidth(context, MAX(annotation.width * rect.size.width, 1.0));
	CGContextSetLineCap(context, kCGLineCapRound);
	CGContextSetLineJoin(context, kCGLineJoinRound);

	if (annotation.type == AnnotationTypeHighlighter) {
		CGContextSetAlpha(context, 0.35);
		CGContextSetBlendMode(context, kCGBlendModeMultiply);
	}

	CGContextBeginPath(context);
	for (NSUInteger i = 0; i < annotation.points.count; i++) {
		CGPoint normalized = [[annotation.points objectAtIndex:i] CGPointValue];
		CGFloat x = rect.origin.x + normalized.x * rect.size.width;
		CGFloat y = rect.origin.y + normalized.y * rect.size.height;
		if (i == 0) {
			CGContextMoveToPoint(context, x, y);
		} else {
			CGContextAddLineToPoint(context, x, y);
		}
	}
	if (annotation.points.count == 1) {
		CGPoint normalized = [[annotation.points objectAtIndex:0] CGPointValue];
		CGFloat x = rect.origin.x + normalized.x * rect.size.width;
		CGFloat y = rect.origin.y + normalized.y * rect.size.height;
		CGContextAddLineToPoint(context, x + 0.1, y + 0.1);
	}
	CGContextStrokePath(context);

	CGContextRestoreGState(context);
}
