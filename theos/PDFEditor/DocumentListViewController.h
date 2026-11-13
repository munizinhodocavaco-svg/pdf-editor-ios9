#import <UIKit/UIKit.h>

@interface DocumentListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *pdfFiles;

@end
