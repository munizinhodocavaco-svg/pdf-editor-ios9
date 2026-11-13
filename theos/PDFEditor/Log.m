#import "Log.h"
#import <signal.h>
#import <stdarg.h>
#import <unistd.h>
#import <fcntl.h>
#import <string.h>
#import <sys/types.h>

static NSString *PDFDocumentsPath(void) {
	static NSString *path = nil;
	if (path == nil) {
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		if (paths.count > 0) {
			path = [paths objectAtIndex:0];
		}
	}
	return path;
}

static void PDFRawWrite(const char *file, const char *text) {
	int fd = open(file, O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (fd >= 0) {
		write(fd, text, strlen(text));
		close(fd);
	}
}

static void PDFWriteLine(NSString *line) {
	NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
	if (data == nil) {
		return;
	}
	// /tmp e' gravavel mesmo sem sandbox: serve para provar que o processo chegou a rodar.
	PDFRawWrite("/tmp/pdfeditor.log", [line UTF8String]);

	NSString *documents = PDFDocumentsPath();
	if (documents != nil) {
		NSString *path = [documents stringByAppendingPathComponent:@"launch.log"];
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
}

void PDFLog(NSString *format, ...) {
	va_list args;
	va_start(args, format);
	NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);

	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"HH:mm:ss.SSS"];
	NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];
	PDFWriteLine(line);
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

/* Roda antes do main: se esta linha aparecer em /tmp/pdfeditor.log, o binario
   foi executado e o problema esta no codigo. Se nao aparecer, o processo foi
   barrado pelo launchd/amfid antes de executar qualquer instrucao nossa. */
__attribute__((constructor)) static void PDFBootConstructor(void) {
	char buffer[256];
	snprintf(buffer, sizeof(buffer),
			 "BOOT construtor pid=%d ppid=%d\n", getpid(), getppid());
	PDFRawWrite("/tmp/pdfeditor.log", buffer);
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
