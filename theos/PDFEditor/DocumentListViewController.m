#import "DocumentListViewController.h"
#import "RootViewController.h"

@implementation DocumentListViewController

- (void)viewDidLoad {
	[super viewDidLoad];

	self.title = @"PDF Editor";
	self.pdfFiles = @[];

	self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
	self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.tableView.dataSource = self;
	self.tableView.delegate = self;
	[self.view addSubview:self.tableView];

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Recarregar"
																			  style:UIBarButtonItemStylePlain
																			 target:self
																			 action:@selector(reloadTapped:)];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadFiles];
}

- (void)reloadTapped:(id)sender {
	[self reloadFiles];
}

- (void)reloadFiles {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documents = [paths objectAtIndex:0];
	NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:documents error:NULL];

	NSMutableArray *files = [NSMutableArray array];
	for (NSString *name in contents) {
		if ([[name pathExtension] caseInsensitiveCompare:@"pdf"] == NSOrderedSame) {
			[files addObject:[NSURL fileURLWithPath:[documents stringByAppendingPathComponent:name]]];
		}
	}

	[files sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
		NSURL *a = (NSURL *)obj1;
		NSURL *b = (NSURL *)obj2;
		return [a.lastPathComponent compare:b.lastPathComponent];
	}];

	self.pdfFiles = files;
	[self.tableView reloadData];
	[self updateBackgroundView];
}

- (void)updateBackgroundView {
	if (self.pdfFiles.count > 0) {
		self.tableView.backgroundView = nil;
		return;
	}

	UILabel *label = [[UILabel alloc] initWithFrame:self.tableView.bounds];
	label.numberOfLines = 0;
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = [UIColor grayColor];
	label.font = [UIFont systemFontOfSize:16.0];
	label.text = @"Nenhum PDF encontrado.\n\n"
				 @"Copie arquivos PDF para a pasta Documentos deste app usando o 3uTools "
				 @"(Gerenciador de Arquivos) ou o iTunes (Compartilhamento de Arquivos).\n\n"
				 @"Depois toque em Recarregar.";
	self.tableView.backgroundView = label;
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return (NSInteger)self.pdfFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *identifier = @"PDFCell";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
	if (cell == nil) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}

	NSURL *url = [self.pdfFiles objectAtIndex:indexPath.row];
	cell.textLabel.text = url.lastPathComponent;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSURL *url = [self.pdfFiles objectAtIndex:indexPath.row];
	RootViewController *controller = [[RootViewController alloc] initWithPDFURL:url];
	[self.navigationController pushViewController:controller animated:YES];
}

@end
