#import "MJPEGServer.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <fcntl.h>
#import <dispatch/dispatch.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>

#define MJPEG_BOUNDARY "remoteaccess_boundary"

// Load UIGetScreenImage at runtime
static CGImageRef (*UIGetScreenImagePtr)(void) = NULL;

static void loadUIGetScreenImage() {
    if (!UIGetScreenImagePtr) {
        UIGetScreenImagePtr = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
        if (!UIGetScreenImagePtr) {
            NSLog(@"MJPEG: UIGetScreenImage not available");
        }
    }
}

#define UIGetScreenImage() (UIGetScreenImagePtr ? UIGetScreenImagePtr() : NULL)

@interface MJPEGServer ()
@property (nonatomic, assign) int listenFD;
@property (nonatomic, strong) dispatch_queue_t acceptQueue;
@end

@implementation MJPEGServer

- (instancetype)initWithPort:(uint16_t)port {
	self = [super init];
	if (self) {
		_port = port;
		_acceptQueue = dispatch_queue_create("com.remoteaccess.mjpeg.accept", DISPATCH_QUEUE_SERIAL);
		_running = NO;
	}
	return self;
}

- (void)start {
	if (_running) return;
	
	int fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd < 0) {
		NSLog(@"MJPEG: socket failed");
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
		NSLog(@"MJPEG: bind failed on port %u", _port);
		return;
	}
	if (listen(fd, 16) != 0) {
		close(fd);
		NSLog(@"MJPEG: listen failed");
		return;
	}
	
	_listenFD = fd;
	_running = YES;
	
	dispatch_async(_acceptQueue, ^{
		[self acceptLoop];
	});
	
	NSLog(@"MJPEG Server started on port %u", _port);
}

- (void)stop {
	_running = NO;
	if (_listenFD >= 0) {
		shutdown(_listenFD, SHUT_RDWR);
		close(_listenFD);
		_listenFD = -1;
	}
	NSLog(@"MJPEG Server stopped");
}

- (void)acceptLoop {
	while (_running) {
		struct sockaddr_in clientAddr;
		socklen_t addrLen = sizeof(clientAddr);
		int client = accept(_listenFD, (struct sockaddr*)&clientAddr, &addrLen);
		if (client < 0) {
			if (_running) {
				NSLog(@"MJPEG: accept failed");
			}
			break;
		}
		
		dispatch_queue_t clientQueue = dispatch_queue_create("com.remoteaccess.mjpeg.client", DISPATCH_QUEUE_SERIAL);
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
	
	// Parse request
	if (strncmp(buffer, "GET ", 4) != 0) {
		[self sendError:client code:400 message:@"Bad Request"];
		return;
	}
	
	// Check path
	if (strstr(buffer, "/screen.mjpeg") || strstr(buffer, "/ ") || strstr(buffer, "/mjpeg")) {
		[self sendMJPEGStream:client];
	} else {
		[self sendIndexPage:client];
	}
}

- (void)sendIndexPage:(int)client {
	char *html = 
		"HTTP/1.1 200 OK\r\n"
		"Content-Type: text/html; charset=utf-8\r\n"
		"Connection: close\r\n"
		"\r\n"
		"<!DOCTYPE html>"
		"<html><head><meta charset='utf-8'><title>Acesso Remoto LM</title>"
		"<meta name='viewport' content='width=device-width, initial-scale=1'>"
		"<style>"
		"body{font-family:-apple-system;margin:20px;background:#1a1a1a;color:#fff;text-align:center}"
		"h1{color:#00d4aa}.btn{display:inline-block;padding:15px 30px;margin:10px;"
		"background:#00d4aa;color:#000;text-decoration:none;border-radius:8px;font-size:18px}"
		".btn:active{background:#00b894}</style></head>"
		"<body>"
		"<h1>Acesso Remoto LM</h1>"
		"<p>Servidor MJPEG rodando na porta 8081</p>"
		"<a class='btn' href='/screen.mjpeg'>Ver Tela (MJPEG)</a><br>"
		"<p><small>Adicione à Tela de Início para acesso rápido</small></p>"
		"</body></html>";
	write(client, html, strlen(html));
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
	
	while (_running) {
		CGImageRef screenImage = UIGetScreenImage();
		if (!screenImage) {
			usleep(50000); // 20 FPS
			continue;
		}
		
		NSData *jpegData = [self jpegFromCGImage:screenImage quality:0.7];
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
		
		usleep(50000); // ~20 FPS
	}
}

- (void)sendError:(int)client code:(int)code message:(NSString *)msg {
	char header[512];
	snprintf(header, sizeof(header),
		"HTTP/1.1 %d %s\r\n"
		"Content-Type: text/plain\r\n"
		"Connection: close\r\n"
		"\r\n%s", code, [msg UTF8String], [msg UTF8String]);
	write(client, header, strlen(header));
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