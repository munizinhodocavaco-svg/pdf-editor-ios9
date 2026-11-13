#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "Log.h"

int main(int argc, char *argv[]) {
	@autoreleasepool {
		PDFInstallCrashHandlers();
		PDFLog(@"main: inicio (bundle=%@, versao=%@)",
			   [[NSBundle mainBundle] bundleIdentifier],
			   [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
		int result = UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
		PDFLog(@"main: fim (rc=%d)", result);
		return result;
	}
}
