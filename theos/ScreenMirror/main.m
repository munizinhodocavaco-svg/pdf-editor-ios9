#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/stat.h>
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
		mode_t old_mask = umask(0);
		(void)old_mask;
		
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