#import "ScreenMirror.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <fcntl.h>
#import <dispatch/dispatch.h>
#import <CoreGraphics/CoreGraphics.h>

#define MJPEG_BOUNDARY "screenmirror_boundary"

@interface ScreenMirror ()
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, assign) int listenFD;
@property (nonatomic, strong) dispatch_queue_t acceptQueue;
@property (nonatomic, assign) BOOL running;
@end

@implementation ScreenMirror

- (instancetype)initWithPort:(uint16_t)port {
	self = [super init];
	if (self) {
		_port = port;
		_acceptQueue = dispatch_queue_create("com.screenmirror.accept", DISPATCH_QUEUE_SERIAL);
		_running = NO;
	}
	return self;
}

- (void)start {
	if (_running) return;
	
	int fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd < 0) {
		NSLog(@"ScreenMirror: socket failed");
		return;
	}
	int reuse = 1;
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
	
	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(INADDR_ANY);
	addr.sin_port = htons(_port);
	
	if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
		close(fd);
		NSLog(@"ScreenMirror: bind failed on port %u", _port);
		return;
	}
	if (listen(fd, 16) != 0) {
		close(fd);
		NSLog(@"ScreenMirror: listen failed");
		return;
	}
	
	_listenFD = fd;
	_running = YES;
	
	dispatch_async(_acceptQueue, ^{
		[self acceptLoop];
	});
}

- (void)stop {
	_running = NO;
	if (_listenFD >= 0) {
		shutdown(_listenFD, SHUT_RDWR);
		close(_listenFD);
		_listenFD = -1;
	}
}

- (void)acceptLoop {
	while (_running) {
		struct sockaddr_in clientAddr;
		socklen_t addrLen = sizeof(clientAddr);
		int client = accept(_listenFD, (struct sockaddr*)&clientAddr, &addrLen);
		if (client < 0) {
			if (_running) {
				NSLog(@"ScreenMirror: accept failed");
			}
			break;
		}
		
		// Handle each client on a separate queue
		dispatch_queue_t clientQueue = dispatch_queue_create("com.screenmirror.client", DISPATCH_QUEUE_SERIAL);
		dispatch_async(clientQueue, ^{
			[self handleClient:client];
			close(client);
		});
	}
}

- (void)handleClient:(int)client {
	char buffer[4096];
	ssize_t n = read(client, buffer, sizeof(buffer) - 1);
	if (n <= 0) return;
	buffer[n] = '\0';
	
	// Parse request - just check if it's GET /
	if (strncmp(buffer, "GET ", 4) != 0) {
		[self sendError:client code:400 message:@"Bad Request"];
		return;
	}
	
	// Send MJPEG stream
	[self sendMJPEGStream:client];
}

- (void)sendMJPEGStream:(int)client {
	// HTTP headers for MJPEG
	char header[1024];
	snprintf(header, sizeof(header),
		"HTTP/1.1 200 OK\r\n"
		"Content-Type: multipart/x-mixed-replace; boundary=%s\r\n"
		"Cache-Control: no-cache\r\n"
		"Connection: close\r\n"
		"\r\n", MJPEG_BOUNDARY);
	
	write(client, header, strlen(header));
	
	// Capture and send frames
	UIApplication *app = [UIApplication sharedApplication];
	if (app == nil) {
		// No UIApplication - create one for UIGetScreenImage
		int argc = 1;
		char *argv[] = { "ScreenMirror", NULL };
		UIApplicationMain(argc, argv, nil, nil);
		app = [UIApplication sharedApplication];
	}
	
	while (_running) {
		// Capture screen using private API
		CGImageRef screenImage = UIGetScreenImage();
		if (!screenImage) {
			usleep(50000); // 20 FPS
			continue;
		}
		
		// Convert to JPEG
		NSData *jpegData = [self jpegFromCGImage:screenImage quality:0.6];
		CGImageRelease(screenImage);
		
		if (!jpegData) continue;
		
		// Write MJPEG frame
		char frameHeader[512];
		snprintf(frameHeader, sizeof(frameHeader),
			"\r\n--%s\r\n"
			"Content-Type: image/jpeg\r\n"
			"Content-Length: %lu\r\n"
			"\r\n", MJPEG_BOUNDARY, (unsigned long)jpegData.length);
		
		ssize_t written = write(client, frameHeader, strlen(frameHeader));
		if (written != (ssize_t)strlen(frameHeader)) break;
		
		written = write(client, jpegData.bytes, jpegData.length);
		if (written != (ssize_t)jpegData.length) break;
		
		// ~20 FPS
		usleep(50000);
	}
}

- (NSData *)jpegFromCGImage:(CGImageRef)image quality:(CGFloat)quality {
	size_t width = CGImageGetWidth(image);
	size_t height = CGImageGetHeight(image);
	
	// Create bitmap context
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace, kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(colorSpace);
	
	if (!context) return nil;
	
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
	
	// Create new image from context
	CGImageRef newImage = CGBitmapContextCreateImage(context);
	CGContextRelease(context);
	
	if (!newImage) return nil;
	
	// Convert to JPEG using UIImage
	UIImage *uiImage = [UIImage imageWithCGImage:newImage];
	CGImageRelease(newImage);
	
	return UIImageJPEGRepresentation(uiImage, quality);
}

@end

// Private API declaration
extern CGImageRef UIGetScreenImage(void);