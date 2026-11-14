#import "RootViewController.h"
#import "PDFPageView.h"
#import "AnnotationStore.h"
#import "ColorPickerViewController.h"
#import "Power.h"
#import "Log.h"

static CGRect PageBoxRectForPage(CGPDFPageRef page) {
	CGRect rect = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
	if (rect.size.width < 1.0 || rect.size.height < 1.0) {
		rect = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
	}
	return rect;
}

@interface RootViewController () <PDFPageViewDelegate>

@property (nonatomic, strong) NSURL *pdfURL;
@property (nonatomic, assign) CGPDFDocumentRef document;
@property (nonatomic, assign) NSUInteger pageCount;
@property (nonatomic, assign) NSUInteger currentPage;
@property (nonatomic, strong) AnnotationStore *store;

@property (nonatomic, strong) PDFPageView *pageView;
@property (nonatomic, strong) UIView *toolbar;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UISegmentedControl *toolControl;
@property (nonatomic, strong) UISegmentedControl *sizeControl;
@property (nonatomic, strong) NSMutableArray *colorButtons;
@property (nonatomic, strong) UIButton *spectrumButton;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic, strong) UIButton *undoButton;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UIButton *replaceButton;
@property (nonatomic, strong) UIButton *prevButton;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) UIButton *ecoButton;

@property (nonatomic, assign) BOOL replaceOriginal;

/* Pilha de desfazer propria: o NSUndoManager do iOS 9 lanca excecao
   ("must begin a group before registering undo") quando groupsByEvent = NO,
   o que derrubava o app no primeiro traco. */
@property (nonatomic, strong) NSMutableArray *undoStack;
@property (nonatomic, strong) UIColor *currentColor;
@property (nonatomic, assign) EditorTool currentTool;
@property (nonatomic, assign) CGFloat strokeScale;

@end

@implementation RootViewController

- (instancetype)initWithPDFURL:(NSURL *)pdfURL {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_pdfURL = pdfURL;
		_currentPage = 1;
		_currentTool = EditorToolPencil;
		_currentColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:1.0];
		_strokeScale = 1.0;
		_undoStack = [NSMutableArray array];
		_store = [[AnnotationStore alloc] initWithPDFURL:pdfURL];
		_document = CGPDFDocumentCreateWithURL((__bridge CFURLRef)pdfURL);
		_pageCount = (_document != NULL) ? CGPDFDocumentGetNumberOfPages(_document) : 0;
		_colorButtons = [NSMutableArray array];
	}
	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if (_document != NULL) {
		CGPDFDocumentRelease(_document);
		_document = NULL;
	}
}

- (void)viewDidLoad {
	[super viewDidLoad];
	PDFLog(@"Editor: viewDidLoad inicio (paginas=%lu)", (unsigned long)self.pageCount);

	self.title = [self.pdfURL.lastPathComponent stringByDeletingPathExtension];
	self.edgesForExtendedLayout = UIRectEdgeNone;
	self.view.backgroundColor = [UIColor colorWithWhite:0.90 alpha:1.0];

	[self setupToolbar];
	[self setupBottomBar];

	self.pageView = [[PDFPageView alloc] initWithFrame:CGRectZero];
	self.pageView.delegate = self;
	self.pageView.strokeColor = self.currentColor;
	[self applyStrokeSettings];
	[self.view addSubview:self.pageView];

	/* Fica de olho no modo Eco (pode ser ligado/desligado em outro ponto). */
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(powerModeChanged:)
												 name:PowerModeDidChangeNotification
											   object:nil];
	[self applyPowerMode];

	if (self.pageCount == 0) {
		UILabel *error = [[UILabel alloc] initWithFrame:CGRectZero];
		error.text = @"Nao foi possivel abrir este PDF.";
		error.textAlignment = NSTextAlignmentCenter;
		error.numberOfLines = 0;
		error.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		error.tag = 999;
		[self.view addSubview:error];
	} else {
		[self showPage:1];
	}
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGFloat width = self.view.bounds.size.width;
	CGFloat height = self.view.bounds.size.height;
	CGFloat toolbarHeight = 110.0;  // Aumentado para ícones maiores
	CGFloat bottomHeight = 44.0;
	CGFloat row1 = 6.0;
	CGFloat row2 = 58.0;  // Ajustado para toolbar mais alto

	self.toolbar.frame = CGRectMake(0, 0, width, toolbarHeight);
	// Ferramentas + tamanhos na mesma linha superior - aumentados
	self.toolControl.frame = CGRectMake(8, row1, 180, 44);   // Mais largo e alto
	self.sizeControl.frame = CGRectMake(196, row1, 130, 44);  // Mais alto

	// Cores: 3 botões + arco-íris
	CGFloat colorX = 8.0;
	for (UIButton *button in self.colorButtons) {
		button.frame = CGRectMake(colorX, row2 + 1.0, 30, 30);
		colorX += 36.0;
	}
	self.spectrumButton.frame = CGRectMake(colorX, row2 + 1.0, 30, 30);

	// Botão de economia de energia (modo Eco)
	self.ecoButton.frame = CGRectMake(colorX + 38.0, row2 + 1.0, 66, 30);

	CGFloat right = width - 8.0;
	self.shareButton.frame = CGRectMake(right - 90.0, row2, 90, 32);
	right -= 96.0;
	self.saveButton.frame = CGRectMake(right - 90.0, row2, 90, 32);
	right -= 96.0;
	self.replaceButton.frame = CGRectMake(right - 130.0, row2, 130, 32);
	right -= 136.0;
	self.undoButton.frame = CGRectMake(right - 70.0, row2, 70, 32);

	self.pageView.frame = CGRectMake(0, toolbarHeight, width, height - toolbarHeight - bottomHeight);

	self.bottomBar.frame = CGRectMake(0, height - bottomHeight, width, bottomHeight);
	self.prevButton.frame = CGRectMake(8, 6, 90, 32);
	self.nextButton.frame = CGRectMake(width - 98, 6, 90, 32);
	self.pageLabel.frame = CGRectMake(106, 6, width - 212, 32);

	UIView *error = [self.view viewWithTag:999];
	if (error != nil) {
		error.frame = self.view.bounds;
	}

	[self.pageView setNeedsDisplay];
}

#pragma mark - Interface

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	/* Garante que as anotacoes fiquem salvas antes de sair da tela
	   (a gravacao normal e agrupada para economizar energia). */
	[self.store flushNow];
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)action {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	[button setTitle:title forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont systemFontOfSize:14.0];
	button.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1.0];
	button.layer.cornerRadius = 5.0;
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return button;
}

- (void)setupToolbar {
	self.toolbar = [[UIView alloc] initWithFrame:CGRectZero];
	self.toolbar.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
	self.toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.view addSubview:self.toolbar];

	/* Ferramentas com símbolos maiores e mais visíveis. */
	// Aumenta altura do segmented control para ícones maiores
	self.toolControl = [[UISegmentedControl alloc] initWithItems:@[@"✏️", @"🧽", @"🖍️"]];
	self.toolControl.selectedSegmentIndex = 0;
	// Aumenta fonte dos segmentos para ícones maiores
	[self.toolControl setTitleTextAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:22.0]} forState:UIControlStateNormal];
	[self.toolControl addTarget:self action:@selector(toolChanged:) forControlEvents:UIControlEventValueChanged];
	[self.toolbar addSubview:self.toolControl];

	self.sizeControl = [[UISegmentedControl alloc] initWithItems:@[@"1x", @"2x", @"3x"]];
	self.sizeControl.selectedSegmentIndex = 0;
	[self.sizeControl setTitleTextAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:16.0]} forState:UIControlStateNormal];
	[self.sizeControl addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged];
	[self.toolbar addSubview:self.sizeControl];

	NSArray *colors = [self availableColors];
	for (NSUInteger i = 0; i < colors.count; i++) {
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.backgroundColor = [colors objectAtIndex:i];
		button.tag = (NSInteger)i;
		button.layer.cornerRadius = 5.0;
		button.layer.borderWidth = 2.0;
		button.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
		// Branco precisa de borda visível
		if (i == 1) {
			button.layer.borderColor = [UIColor colorWithWhite:0.5 alpha:1.0].CGColor;
		}
		[button addTarget:self action:@selector(colorTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.colorButtons addObject:button];
		[self.toolbar addSubview:button];
	}

	/* Botão do seletor HSV (arco-íris) — substitui o espectro de cores antigo. */
	self.spectrumButton = [UIButton buttonWithType:UIButtonTypeCustom];
	[self.spectrumButton setBackgroundImage:[self spectrumImageWithSize:CGSizeMake(30.0, 30.0)]
								  forState:UIControlStateNormal];
	self.spectrumButton.layer.cornerRadius = 5.0;
	self.spectrumButton.layer.borderWidth = 2.0;
	self.spectrumButton.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
	[self.spectrumButton addTarget:self action:@selector(spectrumTapped:)
				  forControlEvents:UIControlEventTouchUpInside];
	[self.toolbar addSubview:self.spectrumButton];
	[self updateColorSelection];

	/* Botão do modo Eco: liga/desliga o economy de energia. */
	self.ecoButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[self.ecoButton setTitle:@"Eco" forState:UIControlStateNormal];
	self.ecoButton.titleLabel.font = [UIFont systemFontOfSize:14.0];
	self.ecoButton.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1.0];
	self.ecoButton.layer.cornerRadius = 5.0;
	self.ecoButton.layer.borderWidth = 1.0;
	self.ecoButton.layer.borderColor = [UIColor colorWithWhite:0.70 alpha:1.0].CGColor;
	[self.ecoButton addTarget:self action:@selector(ecoTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self.toolbar addSubview:self.ecoButton];

	self.undoButton = [self makeButton:@"Desfazer" action:@selector(undoTapped:)];
	self.saveButton = [self makeButton:@"Salvar PDF" action:@selector(saveTapped:)];
	self.shareButton = [self makeButton:@"Compartilhar" action:@selector(shareTapped:)];
	self.replaceButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[self.replaceButton setTitle:@"Substituir original" forState:UIControlStateNormal];
	self.replaceButton.titleLabel.font = [UIFont systemFontOfSize:13.0];
	[self.replaceButton setTitleColor:[UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0] forState:UIControlStateNormal];
	[self.replaceButton addTarget:self action:@selector(replaceToggled:) forControlEvents:UIControlEventTouchUpInside];
	[self.toolbar addSubview:self.undoButton];
	[self.toolbar addSubview:self.saveButton];
	[self.toolbar addSubview:self.shareButton];
	[self.toolbar addSubview:self.replaceButton];
}

- (void)setupBottomBar {
	self.bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
	self.bottomBar.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
	self.bottomBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	[self.view addSubview:self.bottomBar];

	self.prevButton = [self makeButton:@"Anterior" action:@selector(prevTapped:)];
	self.nextButton = [self makeButton:@"Proxima" action:@selector(nextTapped:)];
	self.pageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.pageLabel.textAlignment = NSTextAlignmentCenter;
	self.pageLabel.font = [UIFont systemFontOfSize:14.0];

	[self.bottomBar addSubview:self.prevButton];
	[self.bottomBar addSubview:self.nextButton];
	[self.bottomBar addSubview:self.pageLabel];
}

- (NSArray *)availableColors {
	return @[
		[UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:1.0],   // Preto
		[UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0],   // Branco
		[UIColor colorWithRed:0.9 green:0.15 blue:0.15 alpha:1.0]  // Vermelho
	];
}

#pragma mark - Acoes

- (void)toolChanged:(UISegmentedControl *)sender {
	NSInteger index = sender.selectedSegmentIndex;
	if (index == 0) {
		self.currentTool = EditorToolPencil;
	} else if (index == 1) {
		self.currentTool = EditorToolEraser;
	} else {
		self.currentTool = EditorToolHighlighter;
	}
	[self applyStrokeSettings];
	// Borracha não usa cor: desabilita botões de cor
	BOOL colorEnabled = (self.currentTool != EditorToolEraser);
	for (UIButton *button in self.colorButtons) {
		button.enabled = colorEnabled;
		button.alpha = colorEnabled ? 1.0 : 0.4;
	}
	self.spectrumButton.enabled = colorEnabled;
	self.spectrumButton.alpha = colorEnabled ? 1.0 : 0.4;
}

- (void)sizeChanged:(UISegmentedControl *)sender {
	self.strokeScale = (CGFloat)(sender.selectedSegmentIndex + 1);
	[self applyStrokeSettings];
	PDFLog(@"Editor: tamanho %ldx", (long)(sender.selectedSegmentIndex + 1));
}

/* Espessuras proporcionais: 1x, 2x e 3x para lapis, borracha e marcador. */
- (void)applyStrokeSettings {
	CGFloat scale = self.strokeScale > 0.0 ? self.strokeScale : 1.0;
	CGFloat base = (self.currentTool == EditorToolHighlighter) ? 4.0 : 2.5;
	self.pageView.tool = self.currentTool;
	self.pageView.strokeWidth = base * scale;
	self.pageView.eraserWidth = 12.0 * scale;
}

#pragma mark - Modo Eco (economia de energia)

- (void)ecoTapped:(id)sender {
	Power *power = [Power shared];
	[power setEcoMode:!power.ecoMode];
	[self applyPowerMode];
}

- (void)powerModeChanged:(NSNotification *)notification {
	[self applyPowerMode];
}

/* Aplica o estado do modo Eco: brilho (feito pelo Power) + throttle do redesenho. */
- (void)applyPowerMode {
	Power *power = [Power shared];
	BOOL eco = power.ecoMode;

	self.pageView.throttleEnabled = power.throttleDrawing;

	[self.ecoButton setTitle:(eco ? @"Eco ✓" : @"Eco") forState:UIControlStateNormal];
	[self.ecoButton setTitleColor:(eco ? [UIColor colorWithRed:0.15 green:0.55 blue:0.15 alpha:1.0]
									  : [UIColor darkGrayColor])
						forState:UIControlStateNormal];
	self.ecoButton.layer.borderColor = (eco
		? [UIColor colorWithRed:0.15 green:0.55 blue:0.15 alpha:1.0].CGColor
		: [UIColor colorWithWhite:0.70 alpha:1.0].CGColor);
	self.ecoButton.backgroundColor = (eco
		? [UIColor colorWithRed:0.88 green:0.97 blue:0.88 alpha:1.0]
		: [UIColor colorWithWhite:0.97 alpha:1.0]);

	PDFLog(@"Editor: modo ECO %@", eco ? @"LIGADO" : @"desligado");
}

- (void)colorTapped:(UIButton *)sender {
	NSArray *colors = [self availableColors];
	if (sender.tag < 0 || sender.tag >= (NSInteger)colors.count) {
		return;
	}
	[self applyColor:[colors objectAtIndex:sender.tag]];
}

- (void)spectrumTapped:(id)sender {
	ColorPickerViewController *picker = [[ColorPickerViewController alloc] init];
	picker.initialColor = self.currentColor;
	__weak RootViewController *weakSelf = self;
	picker.onColorSelected = ^(UIColor *color) {
		if (color != nil) {
			[weakSelf applyColor:color];
		}
	};
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
	nav.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentViewController:nav animated:YES completion:nil];
}

- (void)applyColor:(UIColor *)color {
	_currentColor = color;
	self.pageView.strokeColor = color;
	[self updateColorSelection];
}

- (void)replaceToggled:(id)sender {
	_replaceOriginal = !_replaceOriginal;
	[self.replaceButton setTitle:_replaceOriginal ? @"✓ Substituir original" : @"Substituir original"
						 forState:UIControlStateNormal];
	[self.replaceButton setTitleColor:_replaceOriginal ? [UIColor colorWithRed:0.2 green:0.7 blue:0.2 alpha:1.0]
														  : [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:1.0]
						  forState:UIControlStateNormal];
	PDFLog(@"Editor: substituir original = %@", _replaceOriginal ? @"SIM" : @"NÃO");
}

- (void)updateColorSelection {
	NSArray *colors = [self availableColors];
	for (NSUInteger i = 0; i < self.colorButtons.count; i++) {
		UIButton *button = [self.colorButtons objectAtIndex:i];
		UIColor *color = i < colors.count ? [colors objectAtIndex:i] : nil;
		BOOL selected = (color != nil && [color isEqual:self.currentColor]);
		button.layer.borderColor = selected
			? [UIColor colorWithRed:0.1 green:0.45 blue:0.9 alpha:1.0].CGColor
			: [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
		button.layer.borderWidth = selected ? 3.0 : 2.0;
	}

	BOOL custom = YES;
	for (UIColor *color in colors) {
		if ([color isEqual:self.currentColor]) {
			custom = NO;
			break;
		}
	}
	self.spectrumButton.layer.borderColor = custom
		? [UIColor colorWithRed:0.1 green:0.45 blue:0.9 alpha:1.0].CGColor
		: [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
	self.spectrumButton.layer.borderWidth = custom ? 3.0 : 2.0;
}

/* Imagem arco-iris para o botao do espectro de cores. */
- (UIImage *)spectrumImageWithSize:(CGSize)size {
	UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
	NSInteger strips = 60;
	for (NSInteger i = 0; i < strips; i++) {
		CGFloat hue = (CGFloat)i / (CGFloat)strips;
		[[UIColor colorWithHue:hue saturation:1.0 brightness:1.0 alpha:1.0] setFill];
		CGRect strip = CGRectMake(size.width * (CGFloat)i / (CGFloat)strips, 0.0,
								  size.width / (CGFloat)strips + 1.0, size.height);
		UIRectFill(strip);
	}
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return image;
}

- (void)undoTapped:(id)sender {
	if (self.undoStack.count == 0) {
		return;
	}
	void (^action)(void) = [self.undoStack lastObject];
	[self.undoStack removeLastObject];
	action();
	[self refreshAnnotations];
	PDFLog(@"Editor: desfazer (%lu restantes)", (unsigned long)self.undoStack.count);
}

- (void)prevTapped:(id)sender {
	if (self.currentPage > 1) {
		[self showPage:self.currentPage - 1];
	}
}

- (void)nextTapped:(id)sender {
	if (self.currentPage < self.pageCount) {
		[self showPage:self.currentPage + 1];
	}
}

- (void)saveTapped:(id)sender {
	NSString *name = [[self.pdfURL.lastPathComponent stringByDeletingPathExtension] stringByAppendingString:@"-anotado.pdf"];
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documents = [paths objectAtIndex:0];
	
	NSString *path;
	if (_replaceOriginal) {
		path = self.pdfURL.path;
	} else {
		path = [documents stringByAppendingPathComponent:name];
	}

	if ([self writeAnnotatedPDFToPath:path]) {
		NSString *message = _replaceOriginal
			? [NSString stringWithFormat:@"Arquivo original substituído:\n%@", self.pdfURL.lastPathComponent]
			: [NSString stringWithFormat:@"Arquivo salvo em Documentos:\n%@", name];
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"PDF salvo"
														message:message
													   delegate:nil
											  cancelButtonTitle:@"OK"
											  otherButtonTitles:nil];
		[alert show];
	} else {
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Erro"
														message:@"Nao foi possivel salvar o PDF."
													   delegate:nil
											  cancelButtonTitle:@"OK"
											  otherButtonTitles:nil];
		[alert show];
	}
}

- (void)shareTapped:(id)sender {
	NSString *name = [[self.pdfURL.lastPathComponent stringByDeletingPathExtension] stringByAppendingString:@"-anotado.pdf"];
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];

	if (![self writeAnnotatedPDFToPath:path]) {
		return;
	}

	NSURL *url = [NSURL fileURLWithPath:path];
	UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
	activity.popoverPresentationController.sourceView = self.shareButton;
	activity.popoverPresentationController.sourceRect = self.shareButton.bounds;
	[self presentViewController:activity animated:YES completion:nil];
}

#pragma mark - Paginas

- (void)showPage:(NSUInteger)page {
	if (page < 1 || page > self.pageCount) {
		return;
	}
	self.currentPage = page;
	PDFLog(@"Editor: exibindo pagina %lu de %lu", (unsigned long)page, (unsigned long)self.pageCount);

	CGPDFPageRef pdfPage = CGPDFDocumentGetPage(self.document, page);
	self.pageView.page = pdfPage;
	self.pageView.pageNumber = page;
	self.pageView.tool = self.currentTool;
	self.pageView.strokeColor = self.currentColor;
	self.pageView.annotations = [self.store annotationsForPage:page];
	self.pageLabel.text = [NSString stringWithFormat:@"Pagina %lu de %lu",
						   (unsigned long)page, (unsigned long)self.pageCount];
	[self.pageView setNeedsDisplay];
}

- (void)refreshAnnotations {
	self.pageView.annotations = [self.store annotationsForPage:self.currentPage];
	[self.pageView setNeedsDisplay];
}

#pragma mark - PDFPageViewDelegate

- (void)pageView:(PDFPageView *)pageView didAddAnnotation:(Annotation *)annotation {
	NSUInteger page = self.currentPage;
	[self.store addAnnotation:annotation toPage:page];

	__weak RootViewController *weakSelf = self;
	void (^undoBlock)(void) = ^{
		[weakSelf.store removeAnnotation:annotation fromPage:page];
		[weakSelf refreshAnnotations];
	};
	[self pushUndoBlock:undoBlock];
}

- (void)pageView:(PDFPageView *)pageView didRemoveAnnotation:(Annotation *)annotation {
	NSUInteger page = self.currentPage;
	[self.store removeAnnotation:annotation fromPage:page];

	__weak RootViewController *weakSelf = self;
	void (^undoBlock)(void) = ^{
		[weakSelf.store addAnnotation:annotation toPage:page];
		[weakSelf refreshAnnotations];
	};
	[self pushUndoBlock:undoBlock];
}

- (void)pushUndoBlock:(void (^)(void))block {
	if (block == nil) {
		return;
	}
	[self.undoStack addObject:[block copy]];
	// Limite de memoria: mantem as ultimas 300 acoes.
	while (self.undoStack.count > 300) {
		[self.undoStack removeObjectAtIndex:0];
	}
}

#pragma mark - Exportacao

- (BOOL)writeAnnotatedPDFToPath:(NSString *)path {
	if (self.document == NULL || self.pageCount == 0) {
		return NO;
	}

	CGRect firstRect = PageBoxRectForPage(CGPDFDocumentGetPage(self.document, 1));
	UIGraphicsBeginPDFContextToFile(path, firstRect, nil);

	for (NSUInteger page = 1; page <= self.pageCount; page++) {
		CGPDFPageRef pdfPage = CGPDFDocumentGetPage(self.document, page);
		CGRect pageRect = PageBoxRectForPage(pdfPage);
		UIGraphicsBeginPDFPageWithInfo(pageRect, nil);
		CGContextRef context = UIGraphicsGetCurrentContext();

		/* Pagina original */
		CGContextSaveGState(context);
		CGContextTranslateCTM(context, 0, pageRect.size.height);
		CGContextScaleCTM(context, 1.0, -1.0);
		CGContextTranslateCTM(context, -pageRect.origin.x, -pageRect.origin.y);
		CGContextDrawPDFPage(context, pdfPage);
		CGContextRestoreGState(context);

		/* Anotacoes em coordenadas UIKit (origem no topo-esquerda) */
		CGRect annotationRect = CGRectMake(0, 0, pageRect.size.width, pageRect.size.height);
		NSArray *annotations = [self.store annotationsForPage:page];
		NSArray *sorted = [annotations sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
			Annotation *a = (Annotation *)obj1;
			Annotation *b = (Annotation *)obj2;
			if (a.type == b.type) {
				return NSOrderedSame;
			}
			return (a.type < b.type) ? NSOrderedAscending : NSOrderedDescending;
		}];

		for (Annotation *annotation in sorted) {
			DrawAnnotationInContext(context, annotation, annotationRect);
		}
	}

	UIGraphicsEndPDFContext();
	return YES;
}

@end
