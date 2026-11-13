#import "RootViewController.h"
#import "PDFPageView.h"
#import "AnnotationStore.h"
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
@property (nonatomic, strong) NSMutableArray *colorButtons;
@property (nonatomic, strong) UILabel *pageLabel;
@property (nonatomic, strong) UIButton *undoButton;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UIButton *prevButton;
@property (nonatomic, strong) UIButton *nextButton;

/* Pilha de desfazer propria: o NSUndoManager do iOS 9 lanca excecao
   ("must begin a group before registering undo") quando groupsByEvent = NO,
   o que derrubava o app no primeiro traco. */
@property (nonatomic, strong) NSMutableArray *undoStack;
@property (nonatomic, strong) UIColor *currentColor;
@property (nonatomic, assign) EditorTool currentTool;

@end

@implementation RootViewController

- (instancetype)initWithPDFURL:(NSURL *)pdfURL {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_pdfURL = pdfURL;
		_currentPage = 1;
		_currentTool = EditorToolPencil;
		_currentColor = [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:1.0];
		_undoStack = [NSMutableArray array];
		_store = [[AnnotationStore alloc] initWithPDFURL:pdfURL];
		_document = CGPDFDocumentCreateWithURL((__bridge CFURLRef)pdfURL);
		_pageCount = (_document != NULL) ? CGPDFDocumentGetNumberOfPages(_document) : 0;
		_colorButtons = [NSMutableArray array];
	}
	return self;
}

- (void)dealloc {
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
	self.pageView.strokeWidth = 3.0;
	self.pageView.tool = self.currentTool;
	[self.view addSubview:self.pageView];

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
	CGFloat toolbarHeight = 52.0;
	CGFloat bottomHeight = 44.0;
	CGFloat itemY = (toolbarHeight - 32.0) / 2.0;

	self.toolbar.frame = CGRectMake(0, 0, width, toolbarHeight);
	self.toolControl.frame = CGRectMake(8, itemY, 250, 32);

	CGFloat colorX = 270.0;
	for (UIButton *button in self.colorButtons) {
		button.frame = CGRectMake(colorX, itemY + 1.0, 30, 30);
		colorX += 36.0;
	}

	CGFloat right = width - 8.0;
	self.shareButton.frame = CGRectMake(right - 90.0, itemY, 90, 32);
	right -= 96.0;
	self.saveButton.frame = CGRectMake(right - 90.0, itemY, 90, 32);
	right -= 96.0;
	self.undoButton.frame = CGRectMake(right - 70.0, itemY, 70, 32);

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

	self.toolControl = [[UISegmentedControl alloc] initWithItems:@[@"Lapis", @"Borracha", @"Marcador"]];
	self.toolControl.selectedSegmentIndex = 0;
	[self.toolControl addTarget:self action:@selector(toolChanged:) forControlEvents:UIControlEventValueChanged];
	[self.toolbar addSubview:self.toolControl];

	NSArray *colors = [self availableColors];
	for (NSUInteger i = 0; i < colors.count; i++) {
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.backgroundColor = [colors objectAtIndex:i];
		button.tag = (NSInteger)i;
		button.layer.cornerRadius = 5.0;
		button.layer.borderWidth = 2.0;
		button.layer.borderColor = [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
		[button addTarget:self action:@selector(colorTapped:) forControlEvents:UIControlEventTouchUpInside];
		[self.colorButtons addObject:button];
		[self.toolbar addSubview:button];
	}

	self.undoButton = [self makeButton:@"Desfazer" action:@selector(undoTapped:)];
	self.saveButton = [self makeButton:@"Salvar PDF" action:@selector(saveTapped:)];
	self.shareButton = [self makeButton:@"Compartilhar" action:@selector(shareTapped:)];
	[self.toolbar addSubview:self.undoButton];
	[self.toolbar addSubview:self.saveButton];
	[self.toolbar addSubview:self.shareButton];
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
		[UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:1.0],
		[UIColor colorWithRed:0.85 green:0.10 blue:0.10 alpha:1.0],
		[UIColor colorWithRed:0.10 green:0.30 blue:0.90 alpha:1.0],
		[UIColor colorWithRed:0.10 green:0.60 blue:0.20 alpha:1.0],
		[UIColor colorWithRed:1.0 green:0.80 blue:0.0 alpha:1.0]
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
	self.pageView.tool = self.currentTool;
}

- (void)colorTapped:(UIButton *)sender {
	NSArray *colors = [self availableColors];
	if (sender.tag < 0 || sender.tag >= (NSInteger)colors.count) {
		return;
	}
	self.currentColor = [colors objectAtIndex:sender.tag];
	self.pageView.strokeColor = self.currentColor;

	for (UIButton *button in self.colorButtons) {
		button.layer.borderColor = (button == sender)
			? [UIColor colorWithRed:0.1 green:0.45 blue:0.9 alpha:1.0].CGColor
			: [UIColor colorWithWhite:0.75 alpha:1.0].CGColor;
		button.layer.borderWidth = (button == sender) ? 3.0 : 2.0;
	}
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
	NSString *path = [documents stringByAppendingPathComponent:name];

	if ([self writeAnnotatedPDFToPath:path]) {
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"PDF salvo"
														message:[NSString stringWithFormat:@"Arquivo salvo em Documentos:\n%@", name]
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
