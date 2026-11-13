#import "WebServer.h"
#import "Log.h"

#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <unistd.h>
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <dispatch/dispatch.h>

NSString *const WebServerFilesDidChangeNotification = @"WebServerFilesDidChangeNotification";

static NSString *PDFDocumentsDirectory(void) {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	return paths.count > 0 ? [paths objectAtIndex:0] : NSTemporaryDirectory();
}

static NSString *PDFHTMLEscape(NSString *text) {
	NSMutableString *out = [NSMutableString stringWithString:(text ?: @"")];
	[out replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, out.length)];
	[out replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, out.length)];
	[out replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, out.length)];
	[out replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, out.length)];
	return out;
}

static NSString *PDFPercentEncode(NSString *text) {
	NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
	const unsigned char *bytes = data.bytes;
	NSMutableString *out = [NSMutableString stringWithCapacity:data.length + 8];
	for (NSUInteger i = 0; i < data.length; i++) {
		unsigned char c = bytes[i];
		if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
			c == '-' || c == '.' || c == '_' || c == '~') {
			[out appendFormat:@"%c", c];
		} else {
			[out appendFormat:@"%%%02X", c];
		}
	}
	return out;
}

static NSString *PDFHTTPDate(NSDate *date) {
	static NSDateFormatter *formatter = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		formatter = [[NSDateFormatter alloc] init];
		formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
		formatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
		formatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss 'GMT'";
	});
	return [formatter stringFromDate:date ?: [NSDate date]];
}

static NSString *PDFSanitizedFileName(NSString *name) {
	name = [name lastPathComponent];
	name = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"_"];
	name = [name stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
	name = [name stringByReplacingOccurrencesOfString:@":" withString:@"_"];
	name = [name stringByReplacingOccurrencesOfString:@"\0" withString:@""];
	name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (name.length == 0 || [name isEqualToString:@"."] || [name isEqualToString:@".."]) {
		name = @"arquivo.pdf";
	}
	return name;
}

static NSString *PDFUniquePath(NSString *directory, NSString *fileName) {
	NSString *candidate = [directory stringByAppendingPathComponent:fileName];
	NSFileManager *fm = [NSFileManager defaultManager];
	if (![fm fileExistsAtPath:candidate]) {
		return candidate;
	}
	NSString *base = [fileName stringByDeletingPathExtension];
	NSString *extension = [fileName pathExtension];
	NSInteger counter = 2;
	while (counter < 10000) {
		NSString *suffix = extension.length > 0
			? [NSString stringWithFormat:@"%@ (%ld).%@", base, (long)counter, extension]
			: [NSString stringWithFormat:@"%@ (%ld)", base, (long)counter];
		candidate = [directory stringByAppendingPathComponent:suffix];
		if (![fm fileExistsAtPath:candidate]) {
			return candidate;
		}
		counter++;
	}
	return [directory stringByAppendingPathComponent:fileName];
}

static NSArray *PDFListFiles(void) {
	NSString *directory = PDFDocumentsDirectory();
	NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL];
	NSMutableArray *files = [NSMutableArray array];
	for (NSString *name in contents) {
		if ([name hasPrefix:@"."]) {
			continue;
		}
		NSString *path = [directory stringByAppendingPathComponent:name];
		NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
		if (attributes == nil || ![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) {
			continue;
		}
		[files addObject:@{ @"name": name, @"path": path, @"size": attributes[NSFileSize] ?: @0,
							@"date": attributes[NSFileModificationDate] ?: [NSDate date] }];
	}
	[files sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
		return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
	}];
	return files;
}

static void PDFSendAll(int fd, const void *bytes, size_t length) {
	const uint8_t *cursor = bytes;
	size_t sent = 0;
	while (sent < length) {
		ssize_t written = send(fd, cursor + sent, length - sent, 0);
		if (written <= 0) {
			return;
		}
		sent += (size_t)written;
	}
}

static void PDFSendHead(int fd, int code, NSString *reason, NSString *contentType,
						unsigned long long contentLength, NSDictionary *extraHeaders) {
	NSMutableString *head = [NSMutableString string];
	[head appendFormat:@"HTTP/1.1 %d %@\r\n", code, reason];
	[head appendFormat:@"Date: %@\r\n", PDFHTTPDate(nil)];
	[head appendString:@"Server: PDF-LM/1.0\r\n"];
	if (contentType.length > 0) {
		[head appendFormat:@"Content-Type: %@\r\n", contentType];
	}
	[head appendFormat:@"Content-Length: %llu\r\n", contentLength];
	[head appendString:@"Connection: close\r\n"];
	[head appendString:@"Accept-Ranges: none\r\n"];
	for (NSString *key in extraHeaders) {
		[head appendFormat:@"%@: %@\r\n", key, extraHeaders[key]];
	}
	[head appendString:@"\r\n"];
	NSData *data = [head dataUsingEncoding:NSUTF8StringEncoding];
	PDFSendAll(fd, data.bytes, data.length);
}

static void PDFSendData(int fd, int code, NSString *reason, NSString *contentType, NSData *body) {
	PDFSendHead(fd, code, reason, contentType, body.length, nil);
	if (body.length > 0) {
		PDFSendAll(fd, body.bytes, body.length);
	}
}

static void PDFSendHTML(int fd, int code, NSString *reason, NSString *html) {
	NSData *body = [html dataUsingEncoding:NSUTF8StringEncoding];
	PDFSendHead(fd, code, reason, @"text/html; charset=utf-8", body.length, nil);
	PDFSendAll(fd, body.bytes, body.length);
}

static void PDFSendSimple(int fd, int code, NSString *reason, NSString *message) {
	NSString *html = [NSString stringWithFormat:
		@"<!doctype html><html lang=\"pt-BR\"><meta charset=\"utf-8\">"
		 "<title>%@</title><body style=\"font-family:-apple-system,Helvetica,Arial;padding:40px;color:#222\">"
		 "<h2>%@</h2><p>%@</p><p><a href=\"/\">Voltar</a></p></body></html>",
		reason, reason, PDFHTMLEscape(message)];
	PDFSendHTML(fd, code, reason, html);
}

static void PDFSendFile(int fd, NSString *path, BOOL headOnly) {
	NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
	if (attributes == nil) {
		PDFSendSimple(fd, 404, @"Nao encontrado", @"Arquivo inexistente.");
		return;
	}
	unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
	NSString *contentType = [[path pathExtension].lowercaseString isEqualToString:@"pdf"]
		? @"application/pdf" : @"application/octet-stream";
	PDFSendHead(fd, 200, @"OK", contentType, size,
				@{ @"Content-Disposition": [NSString stringWithFormat:@"inline; filename=\"%@\"",
											PDFPercentEncode([path lastPathComponent])] });
	if (headOnly) {
		return;
	}
	int file = open([path fileSystemRepresentation], O_RDONLY);
	if (file < 0) {
		return;
	}
	uint8_t buffer[65536];
	ssize_t got;
	while ((got = read(file, buffer, sizeof(buffer))) > 0) {
		PDFSendAll(fd, buffer, (size_t)got);
	}
	close(file);
}

#pragma mark - Multipart

static NSData *PDFMultipartBoundary(NSString *contentType) {
	NSRange range = [contentType rangeOfString:@"boundary=" options:NSCaseInsensitiveSearch];
	if (range.location == NSNotFound) {
		return nil;
	}
	NSString *boundary = [contentType substringFromIndex:NSMaxRange(range)];
	NSRange semicolon = [boundary rangeOfString:@";"];
	if (semicolon.location != NSNotFound) {
		boundary = [boundary substringToIndex:semicolon.location];
	}
	boundary = [boundary stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([boundary hasPrefix:@"\""] && [boundary hasSuffix:@"\""] && boundary.length >= 2) {
		boundary = [boundary substringWithRange:NSMakeRange(1, boundary.length - 2)];
	}
	return [boundary dataUsingEncoding:NSUTF8StringEncoding];
}

static NSString *PDFHeaderValue(NSString *headers, NSString *key) {
	NSArray *lines = [headers componentsSeparatedByString:@"\r\n"];
	for (NSString *line in lines) {
		NSRange colon = [line rangeOfString:@":"];
		if (colon.location == NSNotFound) {
			continue;
		}
		NSString *name = [[line substringToIndex:colon.location] stringByTrimmingCharactersInSet:
						  [NSCharacterSet whitespaceCharacterSet]];
		if ([name caseInsensitiveCompare:key] == NSOrderedSame) {
			return [[line substringFromIndex:NSMaxRange(colon)] stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceCharacterSet]];
		}
	}
	return nil;
}

/* Extrai os arquivos de um corpo multipart/form-data. Retorna a quantidade salva. */
static NSInteger PDFSaveMultipart(NSData *body, NSString *contentType, NSMutableArray *savedNames) {
	NSData *delimiter = PDFMultipartBoundary(contentType);
	if (delimiter == nil || body.length == 0) {
		return 0;
	}
	NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
	NSString *directory = PDFDocumentsDirectory();
	const uint8_t *bytes = body.bytes;
	NSUInteger position = 0;
	NSInteger saved = 0;

	while (position < body.length) {
		NSRange found = [body rangeOfData:delimiter options:0 range:NSMakeRange(position, body.length - position)];
		if (found.location == NSNotFound) {
			break;
		}
		NSUInteger partStart = NSMaxRange(found);
		if (partStart + 2 <= body.length && memcmp(bytes + partStart, "--", 2) == 0) {
			break;
		}
		if (partStart + 2 <= body.length && memcmp(bytes + partStart, "\r\n", 2) == 0) {
			partStart += 2;
		}
		NSRange next = [body rangeOfData:delimiter options:0
									range:NSMakeRange(partStart, body.length - partStart)];
		if (next.location == NSNotFound) {
			break;
		}
		NSUInteger partEnd = next.location;
		if (partEnd >= partStart + 2 && memcmp(bytes + partEnd - 2, "\r\n", 2) == 0) {
			partEnd -= 2;
		}
		NSData *part = [body subdataWithRange:NSMakeRange(partStart, partEnd - partStart)];
		NSRange headerBreak = [part rangeOfData:separator options:0 range:NSMakeRange(0, part.length)];
		if (headerBreak.location != NSNotFound) {
			NSString *headers = [[NSString alloc] initWithData:[part subdataWithRange:
				NSMakeRange(0, headerBreak.location)] encoding:NSUTF8StringEncoding];
			NSString *disposition = PDFHeaderValue(headers, @"Content-Disposition");
			NSRange nameRange = [disposition rangeOfString:@"filename=\""];
			if (disposition != nil && nameRange.location != NSNotFound) {
				NSUInteger start = NSMaxRange(nameRange);
				NSRange endQuote = [disposition rangeOfString:@"\""
													  options:0
														range:NSMakeRange(start, disposition.length - start)];
				NSString *fileName = nil;
				if (endQuote.location != NSNotFound) {
					fileName = [disposition substringWithRange:NSMakeRange(start, endQuote.location - start)];
				}
				NSData *fileData = [part subdataWithRange:
					NSMakeRange(NSMaxRange(headerBreak), part.length - NSMaxRange(headerBreak))];
				if (fileName.length > 0 && fileData.length > 0) {
					fileName = PDFSanitizedFileName(fileName);
					NSString *destination = PDFUniquePath(directory, fileName);
					if ([fileData writeToFile:destination atomically:YES]) {
						saved++;
						[savedNames addObject:[destination lastPathComponent]];
					}
				}
			}
		}
		position = next.location;
	}
	return saved;
}

#pragma mark - Paginas HTML

static NSString *PDFHTMLPage(void) {
	NSArray *files = PDFListFiles();
	NSMutableString *rows = [NSMutableString string];
	if (files.count == 0) {
		[rows appendString:@"<p class=\"empty\">Nenhum arquivo ainda. Envie um PDF pelo formul&aacute;rio acima.</p>"];
	}
	for (NSDictionary *file in files) {
		NSString *name = file[@"name"];
		NSString *encoded = PDFPercentEncode(name);
		unsigned long long size = [file[@"size"] unsignedLongLongValue];
		[rows appendFormat:
			@"<li><a href=\"/files/%@\">%@</a><span>%.1f KB</span></li>",
			encoded, PDFHTMLEscape(name), size / 1024.0];
	}

	NSString *ip = [WebServer deviceIPAddress] ?: @"iPad";
	uint16_t port = [WebServer sharedServer].port ?: 8080;
	return [NSString stringWithFormat:
		@"<!doctype html><html lang=\"pt-BR\"><head><meta charset=\"utf-8\">"
		 "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
		 "<title>Leitor / Editor Pdf LM - Importar</title><style>"
		 "body{font-family:-apple-system,Helvetica,Arial,sans-serif;background:#f4f5f7;color:#222;margin:0;padding:32px}"
		 ".card{max-width:720px;margin:0 auto;background:#fff;border-radius:14px;padding:28px;"
		 "box-shadow:0 6px 24px rgba(0,0,0,.10)}"
		 "h1{margin:0 0 4px;font-size:24px}p.sub{margin:0 0 24px;color:#666}"
		 "form{border:2px dashed #c9d2e3;border-radius:12px;padding:24px;text-align:center;margin-bottom:24px;background:#fafbff}"
		 "input[type=file]{margin-bottom:14px}"
		 "button{background:#2f6fed;color:#fff;border:0;border-radius:10px;padding:12px 22px;font-size:16px;font-weight:600}"
		 "ul{list-style:none;padding:0;margin:0}li{display:flex;justify-content:space-between;align-items:center;"
		 "padding:12px 4px;border-bottom:1px solid #eef0f4}li:last-child{border-bottom:0}"
		 "li a{color:#1b4fb8;text-decoration:none;font-weight:600}li span{color:#888;font-size:13px}"
		 ".empty{color:#888}.tip{margin-top:22px;font-size:13px;color:#777;line-height:1.5}"
		 "code{background:#eef1f7;padding:2px 6px;border-radius:5px}"
		 "</style></head><body><div class=\"card\">"
		 "<h1>Leitor / Editor Pdf LM</h1><p class=\"sub\">Envie arquivos PDF para o iPad em %@</p>"
		 "<form action=\"/upload\" method=\"post\" enctype=\"multipart/form-data\">"
		 "<input type=\"file\" name=\"files\" accept=\"application/pdf\" multiple required><br>"
		 "<button type=\"submit\">Enviar para o iPad</button></form>"
		 "<h3>Arquivos no iPad</h3><ul>%@</ul>"
		 "<p class=\"tip\">No Windows tamb&eacute;m &eacute; poss&iacute;vel montar esta pasta como unidade de rede "
		 "(WebDAV): <code>net use Z: http://%@/</code> &mdash; ou abra <code>http://%@/</code> no "
		 "Explorador de Arquivos.</p>"
		 "</div></body></html>",
		PDFHTMLEscape([NSString stringWithFormat:@"http://%@:%u", ip, port]),
		rows, ip, ip];
}

static NSString *PDFWebDAVMultiStatus(NSString *path) {
	NSString *directory = PDFDocumentsDirectory();
	NSMutableString *xml = [NSMutableString string];
	[xml appendString:@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<D:multistatus xmlns:D=\"DAV:\">\n"];

	NSMutableArray *entries = [NSMutableArray arrayWithObject:@""];
	if ([path isEqualToString:@"/"]) {
		for (NSDictionary *file in PDFListFiles()) {
			[entries addObject:file[@"name"]];
		}
	} else if ([path hasPrefix:@"/"]) {
		[entries removeAllObjects];
		[entries addObject:[path substringFromIndex:1]];
	}

	for (NSString *name in entries) {
		NSString *display = name.length > 0 ? name : @"/";
		NSString *href = name.length > 0 ? [NSString stringWithFormat:@"/%@", PDFPercentEncode(name)] : @"/";
		unsigned long long size = 0;
		NSDate *date = [NSDate date];
		BOOL isCollection = name.length == 0;
		if (!isCollection) {
			NSString *full = [directory stringByAppendingPathComponent:name];
			NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:full error:NULL];
			if (attributes == nil) {
				continue;
			}
			size = [attributes[NSFileSize] unsignedLongLongValue];
			date = attributes[NSFileModificationDate] ?: date;
		}

		[xml appendString:@"<D:response>"];
		[xml appendFormat:@"<D:href>%@</D:href>", href];
		[xml appendString:@"<D:propstat><D:prop>"];
		[xml appendFormat:@"<D:displayname>%@</D:displayname>", PDFHTMLEscape(display)];
		if (isCollection) {
			[xml appendString:@"<D:resourcetype><D:collection/></D:resourcetype>"];
		} else {
			[xml appendString:@"<D:resourcetype/>"];
			[xml appendFormat:@"<D:getcontentlength>%llu</D:getcontentlength>", size];
			[xml appendString:@"<D:getcontenttype>application/pdf</D:getcontenttype>"];
		}
		[xml appendFormat:@"<D:getlastmodified>%@</D:getlastmodified>", PDFHTTPDate(date)];
		[xml appendString:@"<D:supportedlock><D:lockentry><D:lockscope><D:exclusive/></D:lockscope>"
						   "<D:locktype><D:write/></D:locktype></D:lockentry></D:supportedlock>"];
		[xml appendString:@"</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>\n"];
	}

	[xml appendString:@"</D:multistatus>"];
	return xml;
}

#pragma mark - Servidor

@interface WebServer ()
@property (nonatomic, assign) int listenFD;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, assign, getter=isRunning) BOOL running;
@property (nonatomic, strong) NSString *lastError;
@end

@implementation WebServer

+ (instancetype)sharedServer {
	static WebServer *server = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		server = [[WebServer alloc] init];
	});
	return server;
}

+ (NSString *)deviceIPAddress {
	struct ifaddrs *addresses = NULL;
	if (getifaddrs(&addresses) != 0) {
		return nil;
	}
	NSString *fallback = nil;
	NSString *wifi = nil;
	for (struct ifaddrs *cursor = addresses; cursor != NULL; cursor = cursor->ifa_next) {
		if (cursor->ifa_addr == NULL || cursor->ifa_addr->sa_family != AF_INET) {
			continue;
		}
		if ((cursor->ifa_flags & IFF_LOOPBACK) != 0 || (cursor->ifa_flags & IFF_UP) == 0) {
			continue;
		}
		char text[INET_ADDRSTRLEN] = {0};
		struct sockaddr_in *address = (struct sockaddr_in *)cursor->ifa_addr;
		if (inet_ntop(AF_INET, &address->sin_addr, text, sizeof(text)) == NULL) {
			continue;
		}
		NSString *value = [NSString stringWithUTF8String:text];
		BOOL isWifiInterface = (cursor->ifa_name[0] == 'e' && cursor->ifa_name[1] == 'n');
		if (isWifiInterface) {
			wifi = value;
		} else if (fallback == nil) {
			fallback = value;
		}
	}
	freeifaddrs(addresses);
	return wifi ?: fallback;
}

- (BOOL)startOnPort:(uint16_t)port {
	if (self.running) {
		return YES;
	}

	int fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd < 0) {
		self.lastError = @"Nao foi possivel criar o socket.";
		return NO;
	}
	int reuse = 1;
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

	struct sockaddr_in address;
	memset(&address, 0, sizeof(address));
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_ANY);
	address.sin_port = htons(port);

	if (bind(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
		close(fd);
		self.lastError = [NSString stringWithFormat:@"Porta %u ocupada (erro %d).", port, errno];
		return NO;
	}
	if (listen(fd, 16) != 0) {
		close(fd);
		self.lastError = [NSString stringWithFormat:@"Falha ao escutar na porta %u.", port];
		return NO;
	}

	self.listenFD = fd;
	self.port = port;
	self.running = YES;
	self.lastError = nil;
	PDFLog(@"WebServer: escutando em %@:%u (%@)", [WebServer deviceIPAddress], port, PDFDocumentsDirectory());

	NSThread *thread = [[NSThread alloc] initWithTarget:self selector:@selector(acceptLoop:) object:nil];
	thread.name = @"PDFLM-WebServer";
	[thread start];
	return YES;
}

- (void)stop {
	if (!self.running) {
		return;
	}
	self.running = NO;
	shutdown(self.listenFD, SHUT_RDWR);
	close(self.listenFD);
	self.listenFD = -1;
	PDFLog(@"WebServer: parado");
}

- (void)acceptLoop:(id)ignored {
	while (self.running) {
		int client = accept(self.listenFD, NULL, NULL);
		if (client < 0) {
			if (!self.running) {
				break;
			}
			continue;
		}
		@autoreleasepool {
			struct timeval timeout;
			timeout.tv_sec = 20;
			timeout.tv_usec = 0;
			setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
			setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
			int nosigpipe = 1;
			setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, sizeof(nosigpipe));
			[self handleClient:client];
			close(client);
		}
	}
}

- (void)notifyChange {
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:WebServerFilesDidChangeNotification object:self];
	});
}

- (void)handleClient:(int)fd {
	NSMutableData *buffer = [NSMutableData data];
	NSData *headEnd = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
	uint8_t chunk[8192];

	while ([buffer rangeOfData:headEnd options:0 range:NSMakeRange(0, buffer.length)].location == NSNotFound) {
		ssize_t got = recv(fd, chunk, sizeof(chunk), 0);
		if (got <= 0) {
			return;
		}
		[buffer appendBytes:chunk length:(NSUInteger)got];
		if (buffer.length > 512 * 1024) {
			return;
		}
	}

	NSRange headRange = [buffer rangeOfData:headEnd options:0 range:NSMakeRange(0, buffer.length)];
	NSString *head = [[NSString alloc] initWithData:[buffer subdataWithRange:NSMakeRange(0, headRange.location)]
										   encoding:NSUTF8StringEncoding];
	if (head == nil) {
		head = [[NSString alloc] initWithData:[buffer subdataWithRange:NSMakeRange(0, headRange.location)]
									 encoding:NSISOLatin1StringEncoding];
	}
	NSMutableData *body = [NSMutableData dataWithData:[buffer subdataWithRange:
		NSMakeRange(NSMaxRange(headRange), buffer.length - NSMaxRange(headRange))]];

	NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
	if (lines.count == 0) {
		return;
	}
	NSArray *requestParts = [lines[0] componentsSeparatedByString:@" "];
	if (requestParts.count < 2) {
		return;
	}
	NSString *method = [requestParts[0] uppercaseString];
	NSString *rawPath = requestParts[1];

	NSMutableDictionary *headers = [NSMutableDictionary dictionary];
	for (NSUInteger i = 1; i < lines.count; i++) {
		NSString *line = lines[i];
		NSRange colon = [line rangeOfString:@":"];
		if (colon.location == NSNotFound) {
			continue;
		}
		NSString *key = [[line substringToIndex:colon.location] lowercaseString];
		NSString *value = [[line substringFromIndex:NSMaxRange(colon)] stringByTrimmingCharactersInSet:
						   [NSCharacterSet whitespaceCharacterSet]];
		headers[key] = value;
	}

	unsigned long long contentLength = [headers[@"content-length"] longLongValue];
	if (contentLength > 0 && body.length < contentLength) {
		while (body.length < contentLength) {
			ssize_t got = recv(fd, chunk, sizeof(chunk), 0);
			if (got <= 0) {
				return;
			}
			[body appendBytes:chunk length:(NSUInteger)got];
			if (body.length > 256ULL * 1024 * 1024) {
				return; // limite de 256 MB por arquivo
			}
		}
	}

	NSString *path = [rawPath componentsSeparatedByString:@"?"].firstObject;
	path = [path stringByRemovingPercentEncoding] ?: path;
	if (![path hasPrefix:@"/"]) {
		path = [@"/" stringByAppendingString:path];
	}
	PDFLog(@"WebServer: %@ %@ (%llu bytes)", method, path, contentLength);

	NSString *directory = PDFDocumentsDirectory();

	if ([method isEqualToString:@"OPTIONS"]) {
		PDFSendHead(fd, 200, @"OK", nil, 0, @{
			@"DAV": @"1, 2", @"MS-Author-Via": @"DAV",
			@"Allow": @"OPTIONS, GET, HEAD, POST, PUT, DELETE, PROPFIND, PROPPATCH, MKCOL, LOCK, UNLOCK" });
		return;
	}

	if ([method isEqualToString:@"PROPFIND"]) {
		NSString *xml = PDFWebDAVMultiStatus(path);
		NSData *data = [xml dataUsingEncoding:NSUTF8StringEncoding];
		PDFSendHead(fd, 207, @"Multi-Status", @"application/xml; charset=\"utf-8\"", data.length,
					@{ @"DAV": @"1, 2" });
		PDFSendAll(fd, data.bytes, data.length);
		return;
	}

	if ([method isEqualToString:@"PROPPATCH"] || [method isEqualToString:@"MKCOL"] ||
		[method isEqualToString:@"LOCK"] || [method isEqualToString:@"UNLOCK"]) {
		if ([method isEqualToString:@"LOCK"]) {
			PDFSendHead(fd, 200, @"OK", @"application/xml; charset=\"utf-8\"", 0, @{
				@"Lock-Token": @"<opaquelocktoken:00000000-0000-0000-0000-000000000000>",
				@"DAV": @"1, 2" });
		} else {
			PDFSendData(fd, 200, @"OK", @"text/plain; charset=utf-8", [NSData data]);
		}
		return;
	}

	if ([method isEqualToString:@"GET"] || [method isEqualToString:@"HEAD"]) {
		if ([path isEqualToString:@"/"] || [path isEqualToString:@"/index.html"]) {
			NSString *html = PDFHTMLPage();
			NSData *data = [html dataUsingEncoding:NSUTF8StringEncoding];
			PDFSendHead(fd, 200, @"OK", @"text/html; charset=utf-8", data.length, nil);
			if ([method isEqualToString:@"GET"]) {
				PDFSendAll(fd, data.bytes, data.length);
			}
			return;
		}
		if ([path isEqualToString:@"/status"]) {
			NSMutableArray *names = [NSMutableArray array];
			for (NSDictionary *file in PDFListFiles()) {
				[names addObject:file[@"name"]];
			}
			NSData *json = [NSJSONSerialization dataWithJSONObject:@{ @"files": names } options:0 error:NULL];
			PDFSendData(fd, 200, @"OK", @"application/json; charset=utf-8", json);
			return;
		}
		NSString *name = [path hasPrefix:@"/files/"] ? [path substringFromIndex:7] : [path substringFromIndex:1];
		NSString *full = [directory stringByAppendingPathComponent:PDFSanitizedFileName(name)];
		PDFSendFile(fd, full, [method isEqualToString:@"HEAD"]);
		return;
	}

	if ([method isEqualToString:@"POST"]) {
		if ([path isEqualToString:@"/upload"]) {
			NSMutableArray *saved = [NSMutableArray array];
			NSInteger count = PDFSaveMultipart(body, headers[@"content-type"], saved);
			if (count > 0) {
				[self notifyChange];
				PDFLog(@"WebServer: %ld arquivo(s) recebido(s): %@", (long)count, [saved componentsJoinedByString:@", "]);
				NSString *html = [NSString stringWithFormat:
					@"<!doctype html><html lang=\"pt-BR\"><meta charset=\"utf-8\">"
					 "<body style=\"font-family:-apple-system,Helvetica,Arial;padding:40px;color:#222\">"
					 "<h2>Recebido!</h2><p>%ld arquivo(s) salvo(s): %@</p>"
					 "<p><a href=\"/\">Enviar mais arquivos</a></p></body></html>",
					(long)count, PDFHTMLEscape([saved componentsJoinedByString:@", "])];
				PDFSendHTML(fd, 200, @"OK", html);
			} else {
				PDFSendSimple(fd, 400, @"Nada recebido", @"Selecione ao menos um arquivo PDF.");
			}
			return;
		}
		PDFSendSimple(fd, 405, @"Metodo nao permitido", @"Use o formulario da pagina inicial.");
		return;
	}

	if ([method isEqualToString:@"PUT"]) {
		NSString *name = PDFSanitizedFileName([path substringFromIndex:1]);
		NSString *full = PDFUniquePath(directory, name);
		if (body.length > 0 && [body writeToFile:full atomically:YES]) {
			[self notifyChange];
			PDFLog(@"WebServer: PUT salvo %@ (%lu bytes)", [full lastPathComponent], (unsigned long)body.length);
			PDFSendData(fd, 201, @"Created", @"text/plain; charset=utf-8", [NSData data]);
		} else {
			PDFSendSimple(fd, 500, @"Falha ao salvar", @"Nao foi possivel gravar o arquivo.");
		}
		return;
	}

	if ([method isEqualToString:@"DELETE"]) {
		NSString *name = PDFSanitizedFileName([path substringFromIndex:1]);
		NSString *full = [directory stringByAppendingPathComponent:name];
		if ([[NSFileManager defaultManager] removeItemAtPath:full error:NULL]) {
			[self notifyChange];
			PDFSendData(fd, 204, @"No Content", nil, [NSData data]);
		} else {
			PDFSendSimple(fd, 404, @"Nao encontrado", @"Arquivo inexistente.");
		}
		return;
	}

	PDFSendSimple(fd, 405, @"Metodo nao permitido", @"Metodo HTTP nao suportado.");
}

@end


