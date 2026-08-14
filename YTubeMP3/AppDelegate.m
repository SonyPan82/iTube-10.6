// AppDelegate.m
//
// Layout uses plain frames + autoresizingMask (springs & struts) rather than
// Auto Layout constraints, because NSLayoutConstraint does not exist on the
// Mac OS X 10.6 SDK (Auto Layout arrived in 10.7).

#import "AppDelegate.h"
#import "SearchResult.h"

#define kWindowWidth  620
#define kWindowHeight 460
#define kMargin       16

@interface AppDelegate (Private)
- (void)buildMenuBar;
- (void)buildWindow;
- (NSString *)defaultDownloadDirectory;
- (void)setStatus:(NSString *)text;
- (void)setControlsEnabled:(BOOL)enabled;
@end

@implementation AppDelegate

- (id)init
{
    self = [super init];
    if (self != nil) {
        searchResults = [[NSMutableArray alloc] init];
        downloadDirectory = [[self defaultDownloadDirectory] retain];
        ytdlp = [[YTDLPController alloc] init];
        [ytdlp setDelegate:self];
    }
    return self;
}

- (void)dealloc
{
    [ytdlp setDelegate:nil];
    [ytdlp release];
    [searchResults release];
    [downloadDirectory release];
    [super dealloc];
}

- (NSString *)defaultDownloadDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES);
    if ([paths count] > 0) {
        return [paths objectAtIndex:0];
    }
    return NSHomeDirectory();
}

#pragma mark - Application lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    [self buildMenuBar];
    [self buildWindow];

    NSString *ytdlpPath = [YTDLPController bundledYTDLPPath];
    if (ytdlpPath == nil) {
        [self setStatus:NSLocalizedString(@"status_ytdlp_missing", nil)];
        [self setControlsEnabled:NO];
    } else {
        [self setStatus:NSLocalizedString(@"status_ready", nil)];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
    return YES;
}

#pragma mark - Menu bar

- (void)buildMenuBar
{
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"iTube"];

    NSString *appName = @"iTube";
    NSString *quitTitle = [NSString stringWithFormat:NSLocalizedString(@"menu_quit_format", nil), appName];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                        action:@selector(terminate:)
                                                 keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
    [quitItem release];

    [appMenuItem setSubmenu:appMenu];
    [mainMenu addItem:appMenuItem];
    [appMenuItem release];
    [appMenu release];

    // Standard Edit menu so Cmd+C / Cmd+V / Cmd+A work in text fields.
    NSString *editTitle = NSLocalizedString(@"menu_edit", nil);
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:editTitle action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:editTitle];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu_cut", nil) action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu_copy", nil) action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu_paste", nil) action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:NSLocalizedString(@"menu_select_all", nil) action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenuItem setSubmenu:editMenu];
    [mainMenu addItem:editMenuItem];
    [editMenuItem release];
    [editMenu release];

    [NSApp setMainMenu:mainMenu];
    [mainMenu release];
}

#pragma mark - Window construction

- (void)buildWindow
{
    NSRect frame = NSMakeRect(0, 0, kWindowWidth, kWindowHeight);
    unsigned int styleMask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;

    window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:styleMask
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [window setTitle:NSLocalizedString(@"window_title", nil)];
    [window setMinSize:NSMakeSize(480, 360)];
    [window center];

    NSView *content = [window contentView];

    // --- Search row ---
    NSRect searchFieldFrame = NSMakeRect(kMargin, kWindowHeight - 44, kWindowWidth - kMargin * 2 - 100, 24);
    searchField = [[NSTextField alloc] initWithFrame:searchFieldFrame];
    [searchField setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [[searchField cell] setPlaceholderString:NSLocalizedString(@"search_placeholder", nil)];
    [searchField setTarget:self];
    [searchField setAction:@selector(searchButtonClicked:)];
    [content addSubview:searchField];
    [searchField release];

    NSRect searchButtonFrame = NSMakeRect(kWindowWidth - kMargin - 90, kWindowHeight - 45, 90, 26);
    searchButton = [[NSButton alloc] initWithFrame:searchButtonFrame];
    [searchButton setAutoresizingMask:(NSViewMinXMargin | NSViewMinYMargin)];
    [searchButton setTitle:NSLocalizedString(@"search_button", nil)];
    [searchButton setBezelStyle:NSRoundedBezelStyle];
    [searchButton setTarget:self];
    [searchButton setAction:@selector(searchButtonClicked:)];
    [content addSubview:searchButton];
    [searchButton release];

    // --- Results table ---
    NSRect scrollFrame = NSMakeRect(kMargin, 116, kWindowWidth - kMargin * 2, kWindowHeight - 116 - 60);
    tableScrollView = [[NSScrollView alloc] initWithFrame:scrollFrame];
    [tableScrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [tableScrollView setHasVerticalScroller:YES];
    [tableScrollView setBorderType:NSBezelBorder];

    resultsTableView = [[NSTableView alloc] initWithFrame:[[tableScrollView contentView] bounds]];
    [resultsTableView setAllowsMultipleSelection:NO];

    NSTableColumn *titleColumn = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    [[titleColumn headerCell] setStringValue:NSLocalizedString(@"column_title", nil)];
    [titleColumn setWidth:320];
    [resultsTableView addTableColumn:titleColumn];
    [titleColumn release];

    NSTableColumn *uploaderColumn = [[NSTableColumn alloc] initWithIdentifier:@"uploader"];
    [[uploaderColumn headerCell] setStringValue:NSLocalizedString(@"column_uploader", nil)];
    [uploaderColumn setWidth:150];
    [resultsTableView addTableColumn:uploaderColumn];
    [uploaderColumn release];

    NSTableColumn *durationColumn = [[NSTableColumn alloc] initWithIdentifier:@"duration"];
    [[durationColumn headerCell] setStringValue:NSLocalizedString(@"column_duration", nil)];
    [durationColumn setWidth:80];
    [resultsTableView addTableColumn:durationColumn];
    [durationColumn release];

    [resultsTableView setDataSource:self];
    [resultsTableView setDelegate:self];
    [resultsTableView setDoubleAction:@selector(downloadButtonClicked:)];
    [resultsTableView setTarget:self];

    [tableScrollView setDocumentView:resultsTableView];
    [resultsTableView release];
    [content addSubview:tableScrollView];
    [tableScrollView release];

    // --- Folder row ---
    NSRect folderLabelFrame = NSMakeRect(kMargin, 84, kWindowWidth - kMargin * 2 - 140, 20);
    folderLabel = [[NSTextField alloc] initWithFrame:folderLabelFrame];
    [folderLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [folderLabel setEditable:NO];
    [folderLabel setBordered:NO];
    [folderLabel setDrawsBackground:NO];
    [folderLabel setStringValue:[NSLocalizedString(@"folder_prefix", nil) stringByAppendingString:downloadDirectory]];
    [content addSubview:folderLabel];
    [folderLabel release];

    NSRect chooseFolderFrame = NSMakeRect(kWindowWidth - kMargin - 120, 80, 120, 26);
    chooseFolderButton = [[NSButton alloc] initWithFrame:chooseFolderFrame];
    [chooseFolderButton setAutoresizingMask:(NSViewMinXMargin | NSViewMaxYMargin)];
    [chooseFolderButton setTitle:NSLocalizedString(@"choose_folder_button", nil)];
    [chooseFolderButton setBezelStyle:NSRoundedBezelStyle];
    [chooseFolderButton setTarget:self];
    [chooseFolderButton setAction:@selector(chooseFolderButtonClicked:)];
    [content addSubview:chooseFolderButton];
    [chooseFolderButton release];

    // --- Bottom row: download + progress + status ---
    NSRect downloadButtonFrame = NSMakeRect(kMargin, kMargin + 24, 160, 30);
    downloadButton = [[NSButton alloc] initWithFrame:downloadButtonFrame];
    [downloadButton setAutoresizingMask:(NSViewMaxYMargin)];
    [downloadButton setTitle:NSLocalizedString(@"download_button", nil)];
    [downloadButton setBezelStyle:NSRoundedBezelStyle];
    [downloadButton setEnabled:NO];
    [downloadButton setTarget:self];
    [downloadButton setAction:@selector(downloadButtonClicked:)];
    [content addSubview:downloadButton];
    [downloadButton release];

    NSRect progressFrame = NSMakeRect(kMargin + 172, kMargin + 28, 160, 20);
    progressIndicator = [[NSProgressIndicator alloc] initWithFrame:progressFrame];
    [progressIndicator setAutoresizingMask:(NSViewMaxYMargin)];
    [progressIndicator setStyle:NSProgressIndicatorBarStyle];
    [progressIndicator setIndeterminate:NO];
    [progressIndicator setMinValue:0.0];
    [progressIndicator setMaxValue:100.0];
    [progressIndicator setDoubleValue:0.0];
    [content addSubview:progressIndicator];
    [progressIndicator release];

    NSRect statusFrame = NSMakeRect(kMargin + 344, kMargin + 24, kWindowWidth - kMargin * 2 - 344, 24);
    statusLabel = [[NSTextField alloc] initWithFrame:statusFrame];
    [statusLabel setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [statusLabel setEditable:NO];
    [statusLabel setBordered:NO];
    [statusLabel setDrawsBackground:NO];
    [statusLabel setStringValue:@""];
    [content addSubview:statusLabel];
    [statusLabel release];

    [window makeFirstResponder:searchField];
    [window makeKeyAndOrderFront:nil];
}

#pragma mark - Actions

- (void)searchButtonClicked:(id)sender
{
    NSString *query = [searchField stringValue];
    if ([query length] == 0) {
        return;
    }

    [self setControlsEnabled:NO];
    [self setStatus:NSLocalizedString(@"status_searching", nil)];
    [progressIndicator setIndeterminate:YES];
    [progressIndicator startAnimation:nil];

    [searchResults removeAllObjects];
    [resultsTableView reloadData];

    [ytdlp searchForQuery:query maxResults:15];
}

- (void)chooseFolderButtonClicked:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setPrompt:NSLocalizedString(@"choose_folder_prompt", nil)];

    if ([panel runModal] == NSOKButton) {
        NSArray *urls = [panel URLs];
        if ([urls count] > 0) {
            NSURL *url = [urls objectAtIndex:0];
            [downloadDirectory release];
            downloadDirectory = [[url path] retain];
            [folderLabel setStringValue:[NSLocalizedString(@"folder_prefix", nil) stringByAppendingString:downloadDirectory]];
        }
    }
}

- (void)downloadButtonClicked:(id)sender
{
    NSInteger row = [resultsTableView selectedRow];
    if (row < 0 || row >= (NSInteger)[searchResults count]) {
        return;
    }
    SearchResult *result = [searchResults objectAtIndex:row];

    [self setControlsEnabled:NO];
    [self setStatus:[NSString stringWithFormat:NSLocalizedString(@"status_downloading_format", nil), [result title]]];
    [progressIndicator setIndeterminate:NO];
    [progressIndicator setDoubleValue:0.0];

    [ytdlp downloadResult:result toDirectory:downloadDirectory];
}

#pragma mark - Helpers

- (void)setStatus:(NSString *)text
{
    [statusLabel setStringValue:text];
}

- (void)setControlsEnabled:(BOOL)enabled
{
    [searchButton setEnabled:enabled];
    [searchField setEnabled:enabled];
    [chooseFolderButton setEnabled:enabled];
    if (enabled) {
        [downloadButton setEnabled:([resultsTableView selectedRow] >= 0)];
    } else {
        [downloadButton setEnabled:NO];
    }
}

- (double)percentFromProgressLine:(NSString *)line
{
    NSScanner *scanner = [NSScanner scannerWithString:line];
    [scanner setCharactersToBeSkipped:nil];
    NSCharacterSet *digitsAndDot = [NSCharacterSet characterSetWithCharactersInString:@"0123456789."];

    while (![scanner isAtEnd]) {
        NSString *numberString = nil;
        [scanner scanUpToCharactersFromSet:digitsAndDot intoString:NULL];
        if ([scanner scanCharactersFromSet:digitsAndDot intoString:&numberString]) {
            if (![scanner isAtEnd] && [scanner scanString:@"%" intoString:NULL]) {
                return [numberString doubleValue];
            }
        } else {
            break;
        }
    }
    return -1.0;
}

#pragma mark - NSTableView data source / delegate

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [searchResults count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(int)row
{
    if (row < 0 || row >= (int)[searchResults count]) {
        return nil;
    }
    SearchResult *result = [searchResults objectAtIndex:row];
    NSString *identifier = [tableColumn identifier];

    if ([identifier isEqualToString:@"title"]) {
        return [result title];
    } else if ([identifier isEqualToString:@"uploader"]) {
        return [result uploader];
    } else if ([identifier isEqualToString:@"duration"]) {
        return [result durationString];
    }
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note
{
    [downloadButton setEnabled:([resultsTableView selectedRow] >= 0)];
}

#pragma mark - YTDLPControllerDelegate

- (void)ytdlpController:(id)controller didFindResults:(NSArray *)results
{
    [progressIndicator stopAnimation:nil];
    [progressIndicator setIndeterminate:NO];
    [progressIndicator setDoubleValue:0.0];

    [searchResults setArray:results];
    [resultsTableView reloadData];
    [self setControlsEnabled:YES];

    if ([results count] == 0) {
        [self setStatus:NSLocalizedString(@"status_no_results", nil)];
    } else {
        [self setStatus:[NSString stringWithFormat:NSLocalizedString(@"status_results_format", nil), (int)[results count]]];
    }
}

- (void)ytdlpController:(id)controller searchDidFailWithMessage:(NSString *)message
{
    [progressIndicator stopAnimation:nil];
    [self setControlsEnabled:YES];
    [self setStatus:NSLocalizedString(@"status_search_failed", nil)];
    NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"alert_search_failed_title", nil)
                                      defaultButton:NSLocalizedString(@"alert_ok_button", nil)
                                    alternateButton:nil
                                        otherButton:nil
                          informativeTextWithFormat:@"%@", message];
    [alert runModal];
}

- (void)ytdlpController:(id)controller downloadProgress:(NSString *)rawLine
{
    double percent = [self percentFromProgressLine:rawLine];
    if (percent >= 0.0) {
        [progressIndicator setDoubleValue:percent];
    }
    [self setStatus:rawLine];
}

- (void)ytdlpController:(id)controller downloadDidFinishForResult:(SearchResult *)result outputPath:(NSString *)path
{
    [progressIndicator setDoubleValue:100.0];
    [self setControlsEnabled:YES];
    [self setStatus:[NSString stringWithFormat:NSLocalizedString(@"status_download_done_format", nil), [path lastPathComponent]]];
}

- (void)ytdlpController:(id)controller downloadDidFailWithMessage:(NSString *)message
{
    [self setControlsEnabled:YES];
    [self setStatus:NSLocalizedString(@"status_download_failed", nil)];
    NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"alert_download_failed_title", nil)
                                      defaultButton:NSLocalizedString(@"alert_ok_button", nil)
                                    alternateButton:nil
                                        otherButton:nil
                          informativeTextWithFormat:@"%@", message];
    [alert runModal];
}

@end
