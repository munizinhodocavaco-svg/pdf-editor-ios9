#import "NetworkViewController.h"
#import "WebServer.h"
#import "Log.h"

@interface NetworkViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *urlLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *toggleButton;
@property (nonatomic, strong) UITextField *linkField;
@property (nonatomic, strong) UIButton *downloadButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, assign) BOOL downloadedSomething;

@end

@implementation NetworkViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = @"Importar por rede";
	self.view.backgroundColor = [UIColor whiteColor];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemDone
							 target:self
							 action:@selector(closeTapped:)];

	self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
	self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.scrollView.alwaysBounceVertical = YES;
	[self.view addSubview:self.scrollView];

	[self buildContent];
	[self updateState];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[[WebServer sharedServer] startOnPort:8080];
	[self updateState];
}

- (void)viewDidDisappear:(BOOL)animated {
	[super viewDidDisappear:animated];
	if (self.downloadedSomething) {
		[[NSNotificationCenter defaultCenter] postNotificationName:WebServerFilesDidChangeNotification
															object:nil];
	}
}

- (void)buildContent {
	UILabel *title = [self makeLabel:@"Enviar arquivos do computador"
								font:[UIFont boldSystemFontOfSize:22]
							   color:[UIColor blackColor]];
	title.tag = 100;
	[self.scrollView addSubview:title];

	UILabel *steps = [self makeLabel:
		@"1. Deixe o iPad e o computador na mesma rede Wi-Fi.\n"
		 "2. No navegador do computador, abra o endereco abaixo.\n"
		 "3. Escolha os PDFs e toque em \"Enviar para o iPad\".\n\n"
		 "Enquanto esta tela estiver aberta (ou o app estiver em primeiro plano), "
		 "o servidor fica ativo. Os arquivos recebidos aparecem na lista na hora."
								font:[UIFont systemFontOfSize:15]
							   color:[UIColor darkGrayColor]];
	steps.tag = 101;
	[self.scrollView addSubview:steps];

	self.urlLabel = [self makeLabel:@"http://..."
							   font:[UIFont boldSystemFontOfSize:24]
							  color:[UIColor colorWithRed:0.13 green:0.36 blue:0.85 alpha:1.0]];
	self.urlLabel.tag = 102;
	self.urlLabel.adjustsFontSizeToFitWidth = YES;
	self.urlLabel.minimumScaleFactor = 0.6;
	[self.scrollView addSubview:self.urlLabel];

	UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
	[copy setTitle:@"Copiar endereco" forState:UIControlStateNormal];
	copy.titleLabel.font = [UIFont systemFontOfSize:15];
	copy.layer.borderColor = [UIColor colorWithWhite:0.80 alpha:1.0].CGColor;
	copy.layer.borderWidth = 1.0;
	copy.layer.cornerRadius = 8.0;
	copy.tag = 103;
	[copy addTarget:self action:@selector(copyTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self.scrollView addSubview:copy];

	self.toggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.toggleButton.titleLabel.font = [UIFont systemFontOfSize:15];
	self.toggleButton.layer.borderColor = [UIColor colorWithWhite:0.80 alpha:1.0].CGColor;
	self.toggleButton.layer.borderWidth = 1.0;
	self.toggleButton.layer.cornerRadius = 8.0;
	self.toggleButton.tag = 104;
	[self.toggleButton addTarget:self action:@selector(toggleTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self.scrollView addSubview:self.toggleButton];

	self.statusLabel = [self makeLabel:@"" font:[UIFont systemFontOfSize:14] color:[UIColor grayColor]];
	self.statusLabel.tag = 105;
	[self.scrollView addSubview:self.statusLabel];

	UILabel *separator = [self makeLabel:@"Ou baixe direto de um link"
								   font:[UIFont boldSystemFontOfSize:18]
								  color:[UIColor blackColor]];
	separator.tag = 106;
	[self.scrollView addSubview:separator];

	UILabel *linkHelp = [self makeLabel:
		@"Cole o endereco de um PDF na sua rede local (por exemplo o computador "
		 "rodando um servidor de arquivos) e o app baixa para a pasta do iPad."
								font:[UIFont systemFontOfSize:15]
							   color:[UIColor darkGrayColor]];
	linkHelp.tag = 107;
	[self.scrollView addSubview:linkHelp];

	self.linkField = [[UITextField alloc] init];
	self.linkField.tag = 108;
	self.linkField.borderStyle = UITextBorderStyleRoundedRect;
	self.linkField.placeholder = @"http://192.168.0.10/arquivo.pdf";
	self.linkField.keyboardType = UIKeyboardTypeURL;
	self.linkField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.linkField.autocorrectionType = UITextAutocorrectionTypeNo;
	self.linkField.returnKeyType = UIReturnKeyGo;
	self.linkField.delegate = self;
	self.linkField.clearButtonMode = UITextFieldViewModeWhileEditing;
	[self.scrollView addSubview:self.linkField];

	self.downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[self.downloadButton setTitle:@"Baixar PDF" forState:UIControlStateNormal];
	[self.downloadButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	self.downloadButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
	self.downloadButton.backgroundColor = [UIColor colorWithRed:0.18 green:0.44 blue:0.93 alpha:1.0];
	self.downloadButton.layer.cornerRadius = 9.0;
	self.downloadButton.tag = 109;
	[self.downloadButton addTarget:self action:@selector(downloadTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self.scrollView addSubview:self.downloadButton];

	self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
	self.spinner.hidesWhenStopped = YES;
	self.spinner.tag = 110;
	[self.scrollView addSubview:self.spinner];

	UILabel *davHelp = [self makeLabel:
		@"Dica para Windows: abra o Explorador de Arquivos e digite o endereco acima para "
		 "copiar arquivos como em uma pasta de rede (WebDAV), ou use no Prompt de Comando:\n"
		 "net use Z: http://ENDERECO_DO_IPAD:8080/"
								font:[UIFont systemFontOfSize:13]
							   color:[UIColor grayColor]];
	davHelp.tag = 111;
	[self.scrollView addSubview:davHelp];
}

- (UILabel *)makeLabel:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
	UILabel *label = [[UILabel alloc] init];
	label.text = text;
	label.font = font;
	label.textColor = color;
	label.numberOfLines = 0;
	label.lineBreakMode = NSLineBreakByWordWrapping;
	return label;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGFloat side = 24.0;
	CGFloat width = MIN(640.0, self.scrollView.bounds.size.width - side * 2.0);
	CGFloat x = (self.scrollView.bounds.size.width - width) / 2.0;
	if (x < side) {
		x = side;
		width = self.scrollView.bounds.size.width - side * 2.0;
	}
	CGFloat y = 28.0;

	UILabel *title = (UILabel *)[self.scrollView viewWithTag:100];
	UILabel *steps = (UILabel *)[self.scrollView viewWithTag:101];
	UIButton *copy = (UIButton *)[self.scrollView viewWithTag:103];
	UILabel *separator = (UILabel *)[self.scrollView viewWithTag:106];
	UILabel *linkHelp = (UILabel *)[self.scrollView viewWithTag:107];
	UILabel *davHelp = (UILabel *)[self.scrollView viewWithTag:111];

	title.frame = CGRectMake(x, y, width, [self heightForLabel:title width:width]);
	y = CGRectGetMaxY(title.frame) + 8.0;
	steps.frame = CGRectMake(x, y, width, [self heightForLabel:steps width:width]);
	y = CGRectGetMaxY(steps.frame) + 18.0;
	self.urlLabel.frame = CGRectMake(x, y, width, 34.0);
	y = CGRectGetMaxY(self.urlLabel.frame) + 10.0;
	copy.frame = CGRectMake(x, y, (width - 12.0) / 2.0, 38.0);
	self.toggleButton.frame = CGRectMake(x + (width + 12.0) / 2.0, y, (width - 12.0) / 2.0, 38.0);
	y = CGRectGetMaxY(copy.frame) + 12.0;
	self.statusLabel.frame = CGRectMake(x, y, width, [self heightForLabel:self.statusLabel width:width]);
	y = CGRectGetMaxY(self.statusLabel.frame) + 26.0;
	separator.frame = CGRectMake(x, y, width, [self heightForLabel:separator width:width]);
	y = CGRectGetMaxY(separator.frame) + 8.0;
	linkHelp.frame = CGRectMake(x, y, width, [self heightForLabel:linkHelp width:width]);
	y = CGRectGetMaxY(linkHelp.frame) + 14.0;
	self.linkField.frame = CGRectMake(x, y, width, 40.0);
	y = CGRectGetMaxY(self.linkField.frame) + 10.0;
	self.downloadButton.frame = CGRectMake(x, y, 170.0, 42.0);
	self.spinner.center = CGPointMake(CGRectGetMaxX(self.downloadButton.frame) + 26.0,
									  self.downloadButton.center.y);
	y = CGRectGetMaxY(self.downloadButton.frame) + 26.0;
	davHelp.frame = CGRectMake(x, y, width, [self heightForLabel:davHelp width:width]);
	y = CGRectGetMaxY(davHelp.frame) + 30.0;

	self.scrollView.contentSize = CGSizeMake(self.scrollView.bounds.size.width, y);
}

- (CGFloat)heightForLabel:(UILabel *)label width:(CGFloat)width {
	if (label.text.length == 0) {
		return 0.0;
	}
	CGSize size = [label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
	return ceil(size.height) + 2.0;
}

- (void)updateState {
	WebServer *server = [WebServer sharedServer];
	NSString *ip = [WebServer deviceIPAddress];
	BOOL running = server.isRunning;

	if (running && ip != nil) {
		self.urlLabel.text = [NSString stringWithFormat:@"http://%@:%u", ip, server.port];
		self.urlLabel.textColor = [UIColor colorWithRed:0.13 green:0.36 blue:0.85 alpha:1.0];
		self.statusLabel.text = @"Servidor ativo. O iPad precisa estar na mesma rede Wi-Fi do computador.";
	} else if (ip == nil) {
		self.urlLabel.text = @"Sem conexao Wi-Fi";
		self.urlLabel.textColor = [UIColor darkGrayColor];
		self.statusLabel.text = @"Conecte o iPad a uma rede Wi-Fi para importar arquivos.";
	} else {
		self.urlLabel.text = @"Servidor parado";
		self.urlLabel.textColor = [UIColor darkGrayColor];
		self.statusLabel.text = server.lastError ?: @"Toque em \"Iniciar servidor\" para comecar.";
	}

	[self.toggleButton setTitle:(running ? @"Parar servidor" : @"Iniciar servidor")
					   forState:UIControlStateNormal];
	[self refreshLayout];
}

- (void)refreshLayout {
	[self.view setNeedsLayout];
	[self.view layoutIfNeeded];
}

- (void)copyTapped:(id)sender {
	if (![WebServer sharedServer].isRunning) {
		[self updateState];
		return;
	}
	[UIPasteboard generalPasteboard].string = self.urlLabel.text;
	self.statusLabel.text = @"Endereco copiado. Abra no navegador do computador.";
}

- (void)toggleTapped:(id)sender {
	WebServer *server = [WebServer sharedServer];
	if (server.isRunning) {
		[server stop];
	} else {
		[server startOnPort:8080];
	}
	[self updateState];
}

- (void)closeTapped:(id)sender {
	[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Download por link

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	[self downloadTapped:nil];
	return YES;
}

- (void)downloadTapped:(id)sender {
	NSString *text = [self.linkField.text stringByTrimmingCharactersInSet:
					  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (text.length == 0) {
		self.statusLabel.text = @"Digite o endereco de um PDF.";
		return;
	}
	NSURL *url = [NSURL URLWithString:text];
	if (url == nil || url.scheme.length == 0) {
		self.statusLabel.text = @"Endereco invalido. Use algo como http://192.168.0.10/arquivo.pdf";
		return;
	}

	[self.linkField resignFirstResponder];
	[self.spinner startAnimating];
	self.downloadButton.enabled = NO;
	self.statusLabel.text = [NSString stringWithFormat:@"Baixando %@...", url.absoluteString];
	PDFLog(@"Rede: baixando %@", url.absoluteString);

	NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url
		completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.spinner stopAnimating];
				self.downloadButton.enabled = YES;
				if (error != nil || location == nil) {
					self.statusLabel.text = [NSString stringWithFormat:@"Falha ao baixar: %@",
											 error.localizedDescription ?: @"erro desconhecido"];
					return;
				}

				NSString *name = response.suggestedFilename;
				if (name.length == 0) {
					name = url.lastPathComponent;
				}
				if (name.length == 0) {
					name = @"baixado.pdf";
				}
				if (![[name pathExtension].lowercaseString isEqualToString:@"pdf"]) {
					name = [name stringByAppendingPathExtension:@"pdf"];
				}
				name = [name lastPathComponent];

				NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
				NSString *directory = paths.count > 0 ? paths[0] : NSTemporaryDirectory();
				NSString *destination = [directory stringByAppendingPathComponent:name];
				NSFileManager *fm = [NSFileManager defaultManager];
				if ([fm fileExistsAtPath:destination]) {
					NSString *base = [name stringByDeletingPathExtension];
					destination = [directory stringByAppendingPathComponent:
								   [NSString stringWithFormat:@"%@ (%@).pdf", base,
									[[[NSUUID UUID] UUIDString] substringToIndex:4]];
				}
				NSError *moveError = nil;
				if (![fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:destination] error:&moveError]) {
					self.statusLabel.text = [NSString stringWithFormat:@"Falha ao salvar: %@",
											 moveError.localizedDescription];
					return;
				}

				self.downloadedSomething = YES;
				self.statusLabel.text = [NSString stringWithFormat:@"Salvo: %@", destination.lastPathComponent];
				[[NSNotificationCenter defaultCenter] postNotificationName:WebServerFilesDidChangeNotification
																	object:nil];
				PDFLog(@"Rede: baixado e salvo em %@", destination);
			});
		}];
	[task resume];
}

@end


