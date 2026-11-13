#import "Log.h"
#import <signal.h>
#import <stdarg.h>

static NSString *PDFLogPath(void) {
	static NSString *path = nil;
	if (path == nil) {
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		if (paths.count > 0) {
			path = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"launch.log"];
		} else {
			path = @"/tmp/launch.log";
		}
	}
	return path;
}

void PDFLog(NSString *format, ...) {
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);

	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"HH:mm:ss.SSS"];
	NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];
	NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

	NSString *path = PDFLogPath();
	NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
	if (handle == nil) {
		[data writeToFile:path atomically:YES];
	} else {
		@try {
			[handle seekToEndOfFile];
			[handle writeData:data];
			[handle closeFile];
		} @catch (NSException *exception) {
			[data writeToFile:path atomically:YES];
		}
	}
}

static void PDFUncaughtExceptionHandler(NSException *exception) {
	PDFLog(@"EXCECAO %@: %@", exception.name, exception.reason);
	PDFLog(@"EXCECAO stack: %@", [exception callStackSymbols]);
}

static void PDFSignalHandler(int sig) {
	PDFLog(@"SINAL %d recebido", sig);
	signal(sig, SIG_DFL);
	raise(sig);
}

void PDFInstallCrashHandlers(void) {
	NSSetUncaughtExceptionHandler(&PDFUncaughtExceptionHandler);
	signal(SIGABRT, PDFSignalHandler);
	signal(SIGSEGV, PDFSignalHandler);
	signal(SIGILL, PDFSignalHandler);
	signal(SIGBUS, PDFSignalHandler);
	signal(SIGFPE, PDFSignalHandler);
	signal(SIGTRAP, PDFSignalHandler);
}
