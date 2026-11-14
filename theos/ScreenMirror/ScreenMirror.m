#import "ScreenMirror.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <fcntl.h>
#import <dispatch/dispatch.h>
#import <CoreGraphics/CoreGraphics.h>

#define MJPEG_BOUNDARY "screenmirror_boundary"

// Private API
extern CGImageRef UIGetScreenImage(void);

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
	
	if (strncmp(buffer, "GET ", 4) != 0) {
		[self sendError:client code:400 message:@"Bad Request"];
		return;
	}
	
	[self sendMJPEGStream:client];
}

- (void)sendError:(int)client code:(int)code message:(NSString *)msg {
	char header[512];
	snprintf(header, sizeof(header),
		"HTTP/1.1 %d %s\r\n"
		"Content-Type: text/plain\r\n"
		"Connection: close\r\n"
		"\r\n%s", code, msg.UTF8String, msg.UTF8String);
	write(client, header, strlen(header));
}

- (void)sendMJPEGStream:(int)client {
	char header[1024];
	snprintf(header, sizeof(header),
		"HTTP/1.1 200 OK\r\n"
		"Content-Type: multipart/x-mixed-replace; boundary=%s\r\n"
		"Cache-Control: no-cache\r\n"
		"Connection: close\r\n"
		"\r\n", MJPEG_BOUNDARY);
	
	write(client, header, strlen(header));
	
	while (_running) {
		CGImageRef screenImage = UIGetScreenImage();
		if (!screenImage) {
			usleep(50000);
			continue;
		}
		
		NSData *jpegData = [self jpegFromCGImage:screenImage quality:0.6];
		CGImageRelease(screenImage);
		
		if (!jpegData) continue;
		
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
		
		usleep(50000);
	}
}

- (NSData *)jpegFromCGImage:(CGImageRef)image quality:(CGFloat)quality {
	size_t width = CGImageGetWidth(image);
	size_t height = CGImageGetHeight(image);
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace, kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(colorSpace);
	
	if (!context) return nil;
	
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
	
	CGImageRef newImage = CGBitmapContextCreateImage(context);
	CGContextRelease(context);
	
	if (!newImage) return nil;
	
	UIImage *uiImage = [UIImage imageWithCGImage:newImage];
	CGImageRelease(newImage);
	
	return UIImageJPEGRepresentation(uiImage, quality);
}

@end