// YTDLPController.h
//
// Wraps the bundled yt-dlp (and, if needed, a bundled Python interpreter) as
// an NSTask. Written against the Mac OS X 10.6 SDK: no blocks-based
// NSFileHandle APIs, no NSJSONSerialization. Output from yt-dlp is parsed as
// plain delimited text produced via --print, never JSON.
//
// Field separator used with --print (ASCII Unit Separator, 0x1F) — extremely
// unlikely to appear in a video title, unlike '|' or '\t'.
#define YTDLP_FIELD_SEP @"\x1f"

#import <Cocoa/Cocoa.h>

@class SearchResult;

@protocol YTDLPControllerDelegate <NSObject>
@optional
- (void)ytdlpController:(id)controller didFindResults:(NSArray *)results;
- (void)ytdlpController:(id)controller searchDidFailWithMessage:(NSString *)message;

- (void)ytdlpController:(id)controller downloadProgress:(NSString *)rawLine;
- (void)ytdlpController:(id)controller downloadDidFinishForResult:(SearchResult *)result outputPath:(NSString *)path;
- (void)ytdlpController:(id)controller downloadDidFailWithMessage:(NSString *)message;
@end

@interface YTDLPController : NSObject
{
    id <YTDLPControllerDelegate> delegate;

    NSTask *currentTask;
    NSMutableData *outputBuffer;
    SearchResult *pendingDownloadResult;
    NSString *pendingDownloadOutputPath;
    BOOL isSearchTask;
}

@property (nonatomic, assign) id <YTDLPControllerDelegate> delegate;

// Resolved at runtime from the app bundle's Resources/Tools directory.
+ (NSString *)bundledYTDLPPath;
+ (NSString *)bundledFFmpegPath;
+ (NSString *)bundledPythonPath; // nil if yt-dlp is a standalone binary
+ (NSString *)bundledCACertPath; // nil if no CA bundle was vendored

- (void)searchForQuery:(NSString *)query maxResults:(NSInteger)maxResults;
- (void)downloadResult:(SearchResult *)result toDirectory:(NSString *)directoryPath;
- (void)cancelCurrentTask;

@end
