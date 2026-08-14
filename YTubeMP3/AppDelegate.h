// AppDelegate.h
//
// Entire UI is built programmatically (no .xib) so the project has no
// Interface Builder file whose format could be mishandled outside of the
// exact old Xcode version that created it.

#import <Cocoa/Cocoa.h>
#import "YTDLPController.h"

@class SearchResult;

@interface AppDelegate : NSObject <YTDLPControllerDelegate>
{
    NSWindow *window;

    NSTextField *searchField;
    NSButton *searchButton;

    NSScrollView *tableScrollView;
    NSTableView *resultsTableView;
    NSMutableArray *searchResults;

    NSButton *downloadButton;
    NSButton *chooseFolderButton;
    NSTextField *folderLabel;
    NSProgressIndicator *progressIndicator;
    NSTextField *statusLabel;

    NSString *downloadDirectory;
    YTDLPController *ytdlp;
}

- (void)searchButtonClicked:(id)sender;
- (void)downloadButtonClicked:(id)sender;
- (void)chooseFolderButtonClicked:(id)sender;

@end
