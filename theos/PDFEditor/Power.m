#import "Power.h"
#import "Log.h"

NSString *const PowerModeDidChangeNotification = @"PowerModeDidChangeNotification";

/* Brilho usado no modo Eco (35% = bem mais escuro que o padrao, economiza LCD). */
static const CGFloat kEcoBrightness = 0.35;

@implementation Power {
	/* Brilho original do sistema (guardado so no modo Eco). */
	CGFloat _originalBrightness;
	BOOL _hasOriginalBrightness;
}

+ (instancetype)shared {
	static Power *shared = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		shared = [[Power alloc] init];
	});
	return shared;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_ecoMode = NO;
		_throttleDrawing = NO;
		_originalBrightness = 1.0;
		_hasOriginalBrightness = NO;
	}
	return self;
}

- (void)setEcoMode:(BOOL)enabled {
	if (_ecoMode == enabled) {
		return;
	}
	_ecoMode = enabled;
	_throttleDrawing = enabled;

	if (enabled) {
		// Guarda o brilho atual do sistema antes de mexer nele.
		_originalBrightness = [UIScreen mainScreen].brightness;
		_hasOriginalBrightness = YES;
		[UIScreen mainScreen].brightness = kEcoBrightness;
		PDFLog(@"Power: modo ECO ligado (brilho %.2f -> %.2f, 30 FPS)",
			   _originalBrightness, kEcoBrightness);
	} else {
		[self restoreBrightness];
		PDFLog(@"Power: modo ECO desligado");
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:PowerModeDidChangeNotification object:nil];
}
- (void)restoreBrightness {
	if (_hasOriginalBrightness) {
		[UIScreen mainScreen].brightness = _originalBrightness;
		_hasOriginalBrightness = NO;
	}
}

- (void)suspendForBackground {
	/* Sai do app: devolve o brilho ao sistema para nao deixar a tela escura. */
	if (_ecoMode) {
		[UIScreen mainScreen].brightness = _originalBrightness;
	}
}

- (void)resumeFromBackground {
	/* Volta para o app: reaplica o brilho do modo Eco. */
	if (_ecoMode) {
		[UIScreen mainScreen].brightness = kEcoBrightness;
	}
}

@end
