#import "RootViewController.h"
#import "VNCServer.h"
#import "MJPEGServer.h"
#import <ifaddrs.h>
#import <arpa/inet.h>

@interface RootViewController ()
@property (nonatomic, strong) NSTimer *ipUpdateTimer;
@end

@implementation RootViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Acesso Remoto LM";
	self.view.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
	
	[self setupUI];
	[self startServers];
	[self startIPUpdateTimer];
}

- (void)setupUI {
	// Container view
	UIView *container = [[UIView alloc] init];
	container.translatesAutoresizingMaskIntoConstraints = NO;
	container.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
	container.layer.cornerRadius = 12;
	container.layer.borderWidth = 1;
	container.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
	[self.view addSubview:container];
	
	// Title
	UILabel *titleLabel = [[UILabel alloc] init];
	titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
	titleLabel.text = @"Servidor de Acesso Remoto";
	titleLabel.font = [UIFont boldSystemFontOfSize:20];
	titleLabel.textColor = [UIColor whiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	[container addSubview:titleLabel];
	
	// IP Label
	_ipLabel = [[UILabel alloc] init];
	_ipLabel.translatesAutoresizingMaskIntoConstraints = NO;
	_ipLabel.text = @"IP: Detectando...";
	_ipLabel.font = [UIFont systemFontOfSize:16];
	_ipLabel.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
	_ipLabel.textAlignment = NSTextAlignmentCenter;
	[container addSubview:_ipLabel];
	
	// VNC Section
	UISwitch *vncSwitch = nil;
	UILabel *vncStatus = nil;
	UIView *vncSection = [self createServiceSection:@"VNC (Controle Total)" 
	                                   description:@"Porta 5900 - Use Mocha VNC, RealVNC, etc."
	                                             switch_:&vncSwitch
	                                       statusLabel:&vncStatus
	                                       action:@selector(vncToggled:)];
	_vncSwitch = vncSwitch;
	_vncStatusLabel = vncStatus;
	[container addSubview:vncSection];
	
	// MJPEG Section
	UISwitch *mjpegSwitch = nil;
	UILabel *mjpegStatus = nil;
	UIView *mjpegSection = [self createServiceSection:@"MJPEG (Visualização no Safari)" 
	                                       description:@"Porta 8081 - Abra http://IP:8081/screen.mjpeg"
	                                             switch_:&mjpegSwitch
	                                       statusLabel:&mjpegStatus
	                                           action:@selector(mjpegToggled:)];
	_mjpegSwitch = mjpegSwitch;
	_mjpegStatusLabel = mjpegStatus;
	[container addSubview:mjpegSection];
	
	// Instructions
	UILabel *instructions = [[UILabel alloc] init];
	instructions.translatesAutoresizingMaskIntoConstraints = NO;
	instructions.text = @"No iPhone 14 Pro Max:\n• VNC: App Mocha VNC Lite → IP:5900\n• MJPEG: Safari → http://IP:8081/screen.mjpeg";
	instructions.font = [UIFont systemFontOfSize:13];
	instructions.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
	instructions.textAlignment = NSTextAlignmentCenter;
	instructions.numberOfLines = 0;
	[container addSubview:instructions];
	
	// Constraints
	NSDictionary *views = NSDictionaryOfVariableBindings(container, titleLabel, _ipLabel, vncSection, mjpegSection, instructions);
	[self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-20-[container]-20-|" options:0 metrics:nil views:views]];
	[self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-80-[container]-20-|" options:0 metrics:nil views:views]];
	
	[container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-20-[titleLabel]-20-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(titleLabel)]];
	[container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-20-[_ipLabel]-20-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_ipLabel)]];
	[container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-15-[vncSection]-15-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(vncSection)]];
	[container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-15-[mjpegSection]-15-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(mjpegSection)]];
	[container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-20-[instructions]-20-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(instructions)]];
	
	[container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-20-[titleLabel]-15-[_ipLabel]-20-[vncSection]-15-[mjpegSection]-20-[instructions]-20-|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(titleLabel, _ipLabel, vncSection, mjpegSection, instructions)]];
}

- (UIView *)createServiceSection:(NSString *)title description:(NSString *)desc switch_:(UISwitch **)switchRef statusLabel:(UILabel **)statusRef action:(SEL)action {
	UIView *section = [[UIView alloc] init];
	section.translatesAutoresizingMaskIntoConstraints = NO;
	section.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
	section.layer.cornerRadius = 8;
	
	UILabel *titleLbl = [[UILabel alloc] init];
	titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
	titleLbl.text = title;
	titleLbl.font = [UIFont boldSystemFontOfSize:16];
	titleLbl.textColor = [UIColor whiteColor];
	[section addSubview:titleLbl];
	
	UILabel *descLbl = [[UILabel alloc] init];
	descLbl.translatesAutoresizingMaskIntoConstraints = NO;
	descLbl.text = desc;
	descLbl.font = [UIFont systemFontOfSize:12];
	descLbl.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
	[section addSubview:descLbl];
	
	*switchRef = [[UISwitch alloc] init];
	(*switchRef).translatesAutoresizingMaskIntoConstraints = NO;
	(*switchRef).onTintColor = [UIColor colorWithRed:0.0 green:0.7 blue:0.3 alpha:1.0];
	[(*switchRef) addTarget:self action:action forControlEvents:UIControlEventValueChanged];
	[section addSubview:*switchRef];
	
	*statusRef = [[UILabel alloc] init];
	(*statusRef).translatesAutoresizingMaskIntoConstraints = NO;
	(*statusRef).font = [UIFont systemFontOfSize:13];
	(*statusRef).textAlignment = NSTextAlignmentRight;
	(*statusRef).text = @"Parado";
	(*statusRef).textColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
	[section addSubview:*statusRef];
	
	NSDictionary *views = NSDictionaryOfVariableBindings(titleLbl, descLbl, *switchRef, *statusRef);
	[section addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-15-[titleLbl]" options:0 metrics:nil views:views]];
	[section addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-15-[descLbl]" options:0 metrics:nil views:views]];
	[section addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[*statusRef]-15-|" options:0 metrics:nil views:views]];
	[section addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:[*switchRef]-15-|" options:0 metrics:nil views:views]];
	[section addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-12-[titleLbl]-4-[descLbl]-12-|" options:0 metrics:nil views:views]];
	[section addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-12-[*switchRef]" options:0 metrics:nil views:views]];
	[section addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[*statusRef]-12-|" options:0 metrics:nil views:views]];
	[section addConstraint:[NSLayoutConstraint constraintWithItem:*switchRef attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:section multiplier:1.0 constant:0]];
	
	return section;
}

- (void)startServers {
	_vncServer = [[VNCServer alloc] initWithPort:5900 password:@"123456"];
	_mjpegServer = [[MJPEGServer alloc] initWithPort:8081];
}

- (IBAction)vncToggled:(UISwitch *)sender {
	if (sender.isOn) {
		[_vncServer start];
	} else {
		[_vncServer stop];
	}
	[self updateStatusLabels];
}

- (IBAction)mjpegToggled:(UISwitch *)sender {
	if (sender.isOn) {
		[_mjpegServer start];
	} else {
		[_mjpegServer stop];
	}
	[self updateStatusLabels];
}

- (void)updateStatusLabels {
	_vncStatusLabel.text = _vncServer.running ? @"Rodando" : @"Parado";
	_vncStatusLabel.textColor = _vncServer.running ? [UIColor colorWithRed:0.0 green:0.8 blue:0.3 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
	_vncSwitch.on = _vncServer.running;
	
	_mjpegStatusLabel.text = _mjpegServer.running ? @"Rodando" : @"Parado";
	_mjpegStatusLabel.textColor = _mjpegServer.running ? [UIColor colorWithRed:0.0 green:0.8 blue:0.3 alpha:1.0] : [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];
	_mjpegSwitch.on = _mjpegServer.running;
}

- (void)startIPUpdateTimer {
	_ipUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(updateIPLabel) userInfo:nil repeats:YES];
	[self updateIPLabel];
}

- (void)updateIPLabel {
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *ip = [self getWiFiIPAddress];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (ip) {
				_ipLabel.text = [NSString stringWithFormat:@"IP: %@", ip];
			} else {
				_ipLabel.text = @"IP: Não conectado ao Wi-Fi";
			}
		});
	});
}

- (NSString *)getWiFiIPAddress {
	struct ifaddrs *interfaces = NULL;
	struct ifaddrs *temp_addr = NULL;
	NSString *wifiIP = nil;
	
	if (getifaddrs(&interfaces) == 0) {
		temp_addr = interfaces;
		while (temp_addr != NULL) {
			if (temp_addr->ifa_addr->sa_family == AF_INET) {
				if ([[NSString stringWithUTF8String:temp_addr->ifa_name] isEqualToString:@"en0"] ||
				    [[NSString stringWithUTF8String:temp_addr->ifa_name] hasPrefix:@"en"]) {
					char addr_buf[INET_ADDRSTRLEN];
					void *addr = &((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr;
					if (inet_ntop(AF_INET, addr, addr_buf, INET_ADDRSTRLEN)) {
						wifiIP = [NSString stringWithUTF8String:addr_buf];
						break;
					}
				}
			}
			temp_addr = temp_addr->ifa_next;
		}
		freeifaddrs(interfaces);
	}
	return wifiIP;
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[_ipUpdateTimer invalidate];
	_ipUpdateTimer = nil;
}

@end