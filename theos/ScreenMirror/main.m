#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "ScreenMirror.h"

int main(int argc, char *argv[]) {
	@autoreleasepool {
		// Daemonize: fork and run in background
		pid_t pid = fork();
		if (pid > 0) {
			// Parent exits
			return 0;
		}
		if (pid < 0) {
			NSLog(@"ScreenMirror: fork failed");
			return 1;
		}
		
		// Child continues
		setsid();
		chdir("/");
		umask(0);
		
		// Close std fds
		close(STDIN_FILENO);
		close(STDOUT_FILENO);
		close(STDERR_FILENO);
		
		// Start the MJPEG server
		ScreenMirror *server = [[ScreenMirror alloc] initWithPort:8081];
		[server start];
		
		NSLog(@"ScreenMirror: started on port 8081");
		
		// Keep alive
		[[NSRunLoop currentRunLoop] run];
	}
	return 0;
}