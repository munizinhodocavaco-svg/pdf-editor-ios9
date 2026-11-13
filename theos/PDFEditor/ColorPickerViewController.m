#import "ColorPickerViewController.h"

#pragma mark - Espectro

@class PDFColorSpectrumView;

@protocol PDFColorSpectrumViewDelegate <NSObject>
- (void)spectrumViewDidChangeColor:(PDFColorSpectrumView *)view;
@end

@interface PDFColorSpectrumView : UIView

@property (nonatomic, assign) CGFloat hue;			// 0..1
@property (nonatomic, assign) CGFloat saturation;	// 0..1
@property (nonatomic, assign) CGFloat brightness;	// 0..1
@property (nonatomic, weak) id<PDFColorSpectrumViewDelegate> delegate;

- (UIColor *)selectedColor;
- (void)setColor:(UIColor *)color;

@end

@implementation PDFColorSpectrumView

- (CGRect)squareRect {
	CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height - 60.0);
	side = MAX(side, 40.0);
	return CGRectMake((self.bounds.size.width - side) / 2.0, 0.0, side, side);
}

- (CGRect)hueRect {
	CGRect square = [self squareRect];
	return CGRectMake(square.origin.x, CGRectGetMaxY(square) + 18.0, square.size.width, 36.0);
}

- (void)setColor:(UIColor *)color {
	CGFloat h = 0.0, s = 0.0, b = 0.0, a = 1.0;
	if (color == nil || ![color getHue:&h saturation:&s brightness:&b alpha:&a]) {
		CGFloat white = 0.0;
		if (color != nil) {
			[color getWhite:&white alpha:&a];
		}
		h = 0.0;
		s = 0.0;
		b = white;
	}
	self.hue = h;
	self.saturation = s;
	self.brightness = b;
	[self setNeedsDisplay];
}

- (UIColor *)selectedColor {
	return [UIColor colorWithHue:self.hue saturation:self.saturation brightness:self.brightness alpha:1.0];
}

static CGGradientRef PDFCreateGradient(const CGFloat *components, size_t count, CGFloat *locations) {
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, locations, count);
	CGColorSpaceRelease(space);
	return gradient;
}

- (void)drawRect:(CGRect)rect {
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGRect square = [self squareRect];

	UIColor *pure = [UIColor colorWithHue:self.hue saturation:1.0 brightness:1.0 alpha:1.0];
	CGContextSetFillColorWithColor(context, pure.CGColor);
	CGContextFillRect(context, square);

	CGGradientRef white = NULL;
	CGGradientRef black = NULL;
	CGContextSaveGState(context);
	CGContextClipToRect(context, square);

	/* Saturacao: branco a esquerda, cor pura a direita. */
	CGFloat whiteComponents[8] = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0 };
	white = PDFCreateGradient(whiteComponents, 2, NULL);
	CGContextDrawLinearGradient(context, white,
								CGPointMake(CGRectGetMinX(square), CGRectGetMidY(square)),
								CGPointMake(CGRectGetMaxX(square), CGRectGetMidY(square)), 0);
	CGGradientRelease(white);

	/* Brilho: transparente em cima, preto embaixo. */
	CGFloat blackComponents[8] = { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0 };
	black = PDFCreateGradient(blackComponents, 2, NULL);
	CGContextDrawLinearGradient(context, black,
								CGPointMake(CGRectGetMidX(square), CGRectGetMinY(square)),
								CGPointMake(CGRectGetMidX(square), CGRectGetMaxY(square)), 0);
	CGGradientRelease(black);
	CGContextRestoreGState(context);

	CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:0.70 alpha:1.0].CGColor);
	CGContextSetLineWidth(context, 1.0);
	CGContextStrokeRect(context, CGRectInset(square, 0.5, 0.5));

	/* Barra de matiz (arco-iris). */
	CGRect hueRect = [self hueRect];
	CGFloat hueComponents[7 * 4] = {
		1.0, 0.0, 0.0, 1.0,
		1.0, 1.0, 0.0, 1.0,
		0.0, 1.0, 0.0, 1.0,
		0.0, 1.0, 1.0, 1.0,
		0.0, 0.0, 1.0, 1.0,
		1.0, 0.0, 1.0, 1.0,
		1.0, 0.0, 0.0, 1.0
	};
	CGGradientRef hueGradient = PDFCreateGradient(hueComponents, 7, NULL);
	CGContextSaveGState(context);
	CGContextClipToRect(context, hueRect);
	CGContextDrawLinearGradient(context, hueGradient,
								CGPointMake(CGRectGetMinX(hueRect), CGRectGetMidY(hueRect)),
								CGPointMake(CGRectGetMaxX(hueRect), CGRectGetMidY(hueRect)), 0);
	CGContextRestoreGState(context);
	CGGradientRelease(hueGradient);

	CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:0.60 alpha:1.0].CGColor);
	CGContextSetLineWidth(context, 1.0);
	CGContextStrokeRect(context, CGRectInset(hueRect, 0.5, 0.5));

	/* Marcador da cor escolhida. */
	CGFloat markerX = CGRectGetMinX(square) + self.saturation * square.size.width;
	CGFloat markerY = CGRectGetMinY(square) + (1.0 - self.brightness) * square.size.height;
	CGContextSetLineWidth(context, 3.0);
	CGContextSetStrokeColorWithColor(context, [UIColor whiteColor].CGColor);
	CGContextStrokeEllipseInRect(context, CGRectMake(markerX - 9.0, markerY - 9.0, 18.0, 18.0));
	CGContextSetLineWidth(context, 1.0);
	CGContextSetStrokeColorWithColor(context, [UIColor blackColor].CGColor);
	CGContextStrokeEllipseInRect(context, CGRectMake(markerX - 10.5, markerY - 10.5, 21.0, 21.0));

	/* Marcador do matiz. */
	CGFloat hueX = CGRectGetMinX(hueRect) + self.hue * hueRect.size.width;
	CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
	CGContextFillRect(context, CGRectMake(hueX - 3.0, hueRect.origin.y - 3.0, 6.0, hueRect.size.height + 6.0));
	CGContextSetStrokeColorWithColor(context, [UIColor blackColor].CGColor);
	CGContextStrokeRect(context, CGRectMake(hueX - 3.5, hueRect.origin.y - 3.5, 7.0, hueRect.size.height + 7.0));
}

#pragma mark - Toques

- (void)updateWithTouch:(UITouch *)touch {
	CGPoint point = [touch locationInView:self];
	CGRect square = [self squareRect];
	CGRect hueRect = [self hueRect];

	if (CGRectContainsPoint(square, point)) {
		CGFloat saturation = (point.x - CGRectGetMinX(square)) / square.size.width;
		CGFloat brightness = 1.0 - (point.y - CGRectGetMinY(square)) / square.size.height;
		self.saturation = MAX(0.0, MIN(1.0, saturation));
		self.brightness = MAX(0.0, MIN(1.0, brightness));
	} else if (CGRectContainsPoint(CGRectInset(hueRect, -12.0, -12.0), point)) {
		CGFloat hue = (point.x - CGRectGetMinX(hueRect)) / hueRect.size.width;
		self.hue = MAX(0.0, MIN(1.0, hue));
	} else {
		return;
	}

	[self setNeedsDisplay];
	[self.delegate spectrumViewDidChangeColor:self];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
	[self updateWithTouch:[touches anyObject]];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
	[self updateWithTouch:[touches anyObject]];
}

@end

#pragma mark - Tela

@interface ColorPickerViewController () <PDFColorSpectrumViewDelegate>

@property (nonatomic, strong) PDFColorSpectrumView *spectrumView;
@property (nonatomic, strong) UIView *previewView;
@property (nonatomic, strong) UILabel *hexLabel;

@end

@implementation ColorPickerViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = @"Escolher cor";
	self.view.backgroundColor = [UIColor whiteColor];

	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
							 target:self
							 action:@selector(cancelTapped:)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithTitle:@"Usar cor"
				style:UIBarButtonItemStyleDone
			   target:self
			   action:@selector(doneTapped:)];

	self.spectrumView = [[PDFColorSpectrumView alloc] initWithFrame:CGRectZero];
	self.spectrumView.delegate = self;
	self.spectrumView.backgroundColor = [UIColor whiteColor];
	[self.spectrumView setColor:self.initialColor ?: [UIColor blackColor]];
	[self.view addSubview:self.spectrumView];

	self.previewView = [[UIView alloc] initWithFrame:CGRectZero];
	self.previewView.layer.borderWidth = 1.0;
	self.previewView.layer.borderColor = [UIColor colorWithWhite:0.70 alpha:1.0].CGColor;
	self.previewView.layer.cornerRadius = 8.0;
	[self.view addSubview:self.previewView];

	self.hexLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.hexLabel.font = [UIFont fontWithName:@"Courier" size:18.0];
	self.hexLabel.textColor = [UIColor darkGrayColor];
	[self.view addSubview:self.hexLabel];

	[self updatePreview];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGFloat width = self.view.bounds.size.width;
	CGFloat spectrumWidth = MIN(width - 64.0, 340.0);
	CGFloat spectrumHeight = spectrumWidth + 54.0;
	self.spectrumView.frame = CGRectMake((width - spectrumWidth) / 2.0, 24.0,
										 spectrumWidth, spectrumHeight);

	CGFloat y = CGRectGetMaxY(self.spectrumView.frame) + 24.0;
	self.previewView.frame = CGRectMake(width / 2.0 - 100.0, y, 56.0, 56.0);
	self.hexLabel.frame = CGRectMake(width / 2.0 - 32.0, y + 14.0, 140.0, 28.0);
}

- (void)updatePreview {
	UIColor *color = [self.spectrumView selectedColor];
	self.previewView.backgroundColor = color;

	CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 1.0;
	if ([color getRed:&red green:&green blue:&blue alpha:&alpha]) {
		self.hexLabel.text = [NSString stringWithFormat:@"#%02X%02X%02X",
							  (unsigned)(red * 255.0 + 0.5),
							  (unsigned)(green * 255.0 + 0.5),
							  (unsigned)(blue * 255.0 + 0.5)];
	} else {
		self.hexLabel.text = @"";
	}
}

#pragma mark - PDFColorSpectrumViewDelegate

- (void)spectrumViewDidChangeColor:(PDFColorSpectrumView *)view {
	[self updatePreview];
}

#pragma mark - Acoes

- (void)cancelTapped:(id)sender {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)doneTapped:(id)sender {
	UIColor *color = [self.spectrumView selectedColor];
	void (^callback)(UIColor *) = self.onColorSelected;
	[self dismissViewControllerAnimated:YES completion:^{
		if (callback != nil) {
			callback(color);
		}
	}];
}

@end
