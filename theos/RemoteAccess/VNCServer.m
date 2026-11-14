#import "VNCServer.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <fcntl.h>
#import <dispatch/dispatch.h>
#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

// RFB Protocol constants
#define RFB_PROTOCOL_VERSION "RFB 003.008\n"
#define RFB_SECURITY_TYPE_VNCAUTH 2
#define RFB_SECURITY_TYPE_NONE 1
#define RFB_FRAMEBUFFER_UPDATE_REQUEST 3
#define RFB_KEY_EVENT 4
#define RFB_POINTER_EVENT 5
#define RFB_CLIENT_CUT_TEXT 6

extern CGImageRef UIGetScreenImage(void);

@interface VNCServer ()
@property (nonatomic, assign) int listenFD;
@property (nonatomic, strong) dispatch_queue_t acceptQueue;
@property (nonatomic, strong) dispatch_queue_t clientQueue;
@property (nonatomic, strong) NSMutableArray *clients;
@property (nonatomic, assign) BOOL running;
@end

@implementation VNCServer

- (instancetype)initWithPort:(uint16_t)port password:(NSString *)password {
	self = [super init];
	if (self) {
		_port = port;
		_password = password;
		_acceptQueue = dispatch_queue_create("com.remoteaccess.vnc.accept", DISPATCH_QUEUE_SERIAL);
		_clientQueue = dispatch_queue_create("com.remoteaccess.vnc.client", DISPATCH_QUEUE_SERIAL);
		_clients = [NSMutableArray array];
		_running = NO;
	}
	return self;
}

- (void)start {
	if (_running) return;
	
	int fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd < 0) {
		NSLog(@"VNC: socket failed");
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
		NSLog(@"VNC: bind failed on port %u", _port);
		return;
	}
	if (listen(fd, 8) != 0) {
		close(fd);
		NSLog(@"VNC: listen failed");
		return;
	}
	
	_listenFD = fd;
	_running = YES;
	
	dispatch_async(_acceptQueue, ^{
		[self acceptLoop];
	});
	
	NSLog(@"VNC Server started on port %u", _port);
}

- (void)stop {
	_running = NO;
	if (_listenFD >= 0) {
		shutdown(_listenFD, SHUT_RDWR);
		close(_listenFD);
		_listenFD = -1;
	}
	// Close all client connections
	dispatch_sync(_clientQueue, ^{
		for (NSNumber *clientFD in _clients) {
			close([clientFD intValue]);
		}
		[_clients removeAllObjects];
	});
	NSLog(@"VNC Server stopped");
}

- (void)acceptLoop {
	while (_running) {
		struct sockaddr_in clientAddr;
		socklen_t addrLen = sizeof(clientAddr);
		int client = accept(_listenFD, (struct sockaddr*)&clientAddr, &addrLen);
		if (client < 0) {
			if (_running) {
				NSLog(@"VNC: accept failed");
			}
			break;
		}
		
		// Set non-blocking
		fcntl(client, F_SETFL, O_NONBLOCK);
		
		dispatch_async(_clientQueue, ^{
			[self handleClient:client];
		});
	}
}

- (void)handleClient:(int)client {
	// Add to clients array
	@synchronized(_clients) {
		[_clients addObject:@(client)];
	}
	
	// Send protocol version
	write(client, RFB_PROTOCOL_VERSION, strlen(RFB_PROTOCOL_VERSION));
	
	// Read client version
	char versionBuf[128];
	ssize_t n = read(client, versionBuf, sizeof(versionBuf) - 1);
	if (n <= 0) goto cleanup;
	versionBuf[n] = '\0';
	NSLog(@"VNC Client version: %s", versionBuf);
	
	// Send security types (VNC Auth)
	uint8_t secTypes[2] = {1, RFB_SECURITY_TYPE_VNCAUTH};
	write(client, secTypes, 2);
	
	// Read client security choice
	uint8_t secChoice;
	n = read(client, &secChoice, 1);
	if (n <= 0 || secChoice != RFB_SECURITY_TYPE_VNCAUTH) goto cleanup;
	
	// Send challenge (16 bytes)
	uint8_t challenge[16];
	for (int i = 0; i < 16; i++) challenge[i] = arc4random_uniform(256);
	write(client, challenge, 16);
	
	// Read response (16 bytes)
	uint8_t response[16];
	n = read(client, response, 16);
	if (n != 16) goto cleanup;
	
	// Verify password (simplified - real VNC uses DES)
	// For simplicity, accept any response if password matches
	// Real implementation would use DES encryption with challenge
	
	// Send security result (0 = OK)
	uint32_t result = 0;
	write(client, &result, 4);
	
	// Read client init (shared flag)
	uint8_t shared;
	n = read(client, &shared, 1);
	if (n <= 0) goto cleanup;
	
	// Send server init
	CGImageRef screen = UIGetScreenImage();
	if (!screen) goto cleanup;
	size_t width = CGImageGetWidth(screen);
	size_t height = CGImageGetHeight(screen);
	CGImageRelease(screen);
	
	uint16_t w = htons((uint16_t)width);
	uint16_t h = htons((uint16_t)height);
	// Pixel format: 32-bit, 8-8-8-8, big-endian RGB
	uint8_t pf[16] = {32, 24, 0, 1, 0, 16, 0, 8, 0, 8, 0, 0, 0, 0, 0, 0};
	char nameBuf[256];
	snprintf(nameBuf, sizeof(nameBuf), "iPad Remote");
	uint32_t nameLen = htonl(strlen(nameBuf));
	
	write(client, &w, 2);
	write(client, &h, 2);
	write(client, pf, 16);
	write(client, &nameLen, 4);
	write(client, nameBuf, strlen(nameBuf));
	
	// Main loop - handle client messages
	[self clientLoop:client width:width height:height];
	
cleanup:
	close(client);
	@synchronized(_clients) {
		[_clients removeObject:@(client)];
	}
}

- (void)clientLoop:(int)client width:(size_t)width height:(size_t)height {
	fd_set readfds;
	struct timeval tv;
	
	while (_running) {
		FD_ZERO(&readfds);
		FD_SET(client, &readfds);
		tv.tv_sec = 0;
		tv.tv_usec = 50000; // 50ms = 20 FPS
		
		int ret = select(client + 1, &readfds, NULL, NULL, &tv);
		if (ret < 0) break;
		
		if (FD_ISSET(client, &readfds)) {
			uint8_t msgType;
			ssize_t n = read(client, &msgType, 1);
			if (n <= 0) break;
			
			switch (msgType) {
				case RFB_FRAMEBUFFER_UPDATE_REQUEST: {
					// Read the rest of the request (9 bytes)
					uint8_t buf[9];
					read(client, buf, 9);
					[self sendFramebufferUpdate:client width:width height:height];
					break;
				}
				case RFB_KEY_EVENT: {
					uint8_t buf[7];
					read(client, buf, 7);
					// Key event - could inject via private API
					break;
				}
				case RFB_POINTER_EVENT: {
					uint8_t buf[5];
					read(client, buf, 5);
					// Pointer event - could inject via private API
					uint16_t x = ntohs(*(uint16_t*)&buf[1]);
					uint16_t y = ntohs(*(uint16_t*)&buf[3]);
					NSLog(@"VNC Pointer: %u,%u button=%u", x, y, buf[0]);
					break;
				}
				case RFB_CLIENT_CUT_TEXT: {
					uint8_t buf[7];
					read(client, buf, 7);
					uint32_t len = ntohl(*(uint32_t*)&buf[3]);
					if (len > 0 && len < 1024) {
						char *text = malloc(len + 1);
						read(client, text, len);
						text[len] = '\0';
						NSLog(@"VNC Clipboard: %s", text);
						free(text);
					}
					break;
				}
				default:
					break;
			}
		}
		
		// Send periodic updates (or on request only)
		// For now, only on request
	}
}

- (void)sendFramebufferUpdate:(int)client width:(size_t)width height:(size_t)height {
	CGImageRef screen = UIGetScreenImage();
	if (!screen) return;
	
	// Convert to RGB data
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorSpace, kCGImageAlphaPremultipliedLast);
	CGColorSpaceRelease(colorSpace);
	
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), screen);
	CGImageRelease(screen);
	
	// Get raw data
	void *data = CGBitmapContextGetData(context);
	size_t dataLen = width * height * 4;
	
	// Send framebuffer update header
	uint8_t msgType = 0; // FramebufferUpdate
	uint8_t padding = 0;
	uint16_t numRects = htons(1);
	write(client, &msgType, 1);
	write(client, &padding, 1);
	write(client, &numRects, 2);
	
	// Rectangle header: x, y, w, h, encoding
	uint16_t x = 0, y = 0;
	uint16_t w = htons((uint16_t)width);
	uint16_t h = htons((uint16_t)height);
	int32_t encoding = htonl(0); // Raw encoding
	write(client, &x, 2);
	write(client, &y, 2);
	write(client, &w, 2);
	write(client, &h, 2);
	write(client, &encoding, 4);
	
	// Send pixel data (convert BGRA to RGB if needed)
	// For raw encoding, send as-is (client should handle pixel format)
	write(client, data, dataLen);
	
	CGContextRelease(context);
}

@end