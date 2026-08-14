// YTDLPController.m

#import "YTDLPController.h"
#import "SearchResult.h"

static NSString * const kFinalPathMarker = @"FINALPATH:";

@interface YTDLPController (Private)
- (void)taskOutputAvailable:(NSNotification *)note;
- (void)taskDidTerminate:(NSNotification *)note;
- (NSTask *)makeTaskWithArguments:(NSArray *)arguments;
@end

@implementation YTDLPController

@synthesize delegate;

+ (NSString *)bundledYTDLPPath
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"yt-dlp" ofType:nil inDirectory:@"Tools"];
    if (path == nil) {
        // Fall back to a plain top-level Resources copy.
        path = [[NSBundle mainBundle] pathForResource:@"yt-dlp" ofType:nil];
    }
    return path;
}

+ (NSString *)bundledFFmpegPath
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"ffmpeg" ofType:nil inDirectory:@"Tools"];
    if (path == nil) {
        path = [[NSBundle mainBundle] pathForResource:@"ffmpeg" ofType:nil];
    }
    return path;
}

+ (NSString *)bundledPythonPath
{
    // Only present if vendor.sh bundled a portable python3 interpreter
    // because the vendored yt-dlp is a plain script rather than a
    // standalone PyInstaller binary. See README.md for details.
    NSString *path = [[NSBundle mainBundle] pathForResource:@"python3" ofType:nil inDirectory:@"Tools/Python.framework/Versions/3.6/bin"];
    return path;
}

+ (NSString *)bundledCACertPath
{
    // python.org's Python.framework builds ship no trusted root certificates
    // of their own (unlike the system's Keychain-backed OpenSSL) - without
    // this, every HTTPS request fails with CERTIFICATE_VERIFY_FAILED, even
    // to legitimate hosts. We point Python's ssl module at a bundled CA
    // bundle via the SSL_CERT_FILE environment variable instead of relying
    // on "Install Certificates.command", which isn't run in a vendored,
    // non-installed interpreter.
    return [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem" inDirectory:@"Tools"];
}

- (void)dealloc
{
    [self cancelCurrentTask];
    [outputBuffer release];
    [pendingDownloadResult release];
    [pendingDownloadOutputPath release];
    [super dealloc];
}

- (NSTask *)makeTaskWithArguments:(NSArray *)arguments
{
    NSString *ytdlpPath = [YTDLPController bundledYTDLPPath];
    NSString *pythonPath = [YTDLPController bundledPythonPath];

    NSTask *task = [[NSTask alloc] init];

    if (pythonPath != nil) {
        [task setLaunchPath:pythonPath];
        NSMutableArray *fullArgs = [NSMutableArray arrayWithObject:ytdlpPath];
        [fullArgs addObjectsFromArray:arguments];
        [task setArguments:fullArgs];
    } else {
        [task setLaunchPath:ytdlpPath];
        [task setArguments:arguments];
    }

    NSString *caCertPath = [YTDLPController bundledCACertPath];
    if (caCertPath != nil) {
        NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
        [env setObject:caCertPath forKey:@"SSL_CERT_FILE"];
        [task setEnvironment:env];
    }

    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    [task setStandardError:pipe]; // merge stdout+stderr, yt-dlp writes progress to both depending on version

    return [task autorelease];
}

- (void)cancelCurrentTask
{
    if (currentTask != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        if ([currentTask isRunning]) {
            [currentTask terminate];
        }
        [currentTask release];
        currentTask = nil;
    }
}

#pragma mark - Search

- (void)searchForQuery:(NSString *)query maxResults:(NSInteger)maxResults
{
    [self cancelCurrentTask];

    NSString *searchSpec = [NSString stringWithFormat:@"ytsearch%ld:%@", (long)maxResults, query];
    NSString *printFormat = [NSString stringWithFormat:@"%%(id)s%@%%(title)s%@%%(duration)s%@%%(uploader)s",
                              YTDLP_FIELD_SEP, YTDLP_FIELD_SEP, YTDLP_FIELD_SEP];

    NSArray *args = [NSArray arrayWithObjects:
                      searchSpec,
                      @"--skip-download",
                      @"--no-warnings",
                      @"--ignore-errors",
                      @"--print", printFormat,
                      nil];

    isSearchTask = YES;
    [outputBuffer release];
    outputBuffer = [[NSMutableData alloc] init];

    currentTask = [[self makeTaskWithArguments:args] retain];

    NSFileHandle *readHandle = [[currentTask standardOutput] fileHandleForReading];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(taskOutputAvailable:)
                                                  name:NSFileHandleReadCompletionNotification
                                                object:readHandle];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(taskDidTerminate:)
                                                  name:NSTaskDidTerminateNotification
                                                object:currentTask];
    [readHandle readInBackgroundAndNotify];

    NS_DURING
        [currentTask launch];
    NS_HANDLER
        if ([delegate respondsToSelector:@selector(ytdlpController:searchDidFailWithMessage:)]) {
            [delegate ytdlpController:self searchDidFailWithMessage:[localException reason]];
        }
    NS_ENDHANDLER
}

#pragma mark - Download

- (void)downloadResult:(SearchResult *)result toDirectory:(NSString *)directoryPath
{
    [self cancelCurrentTask];

    NSString *outputTemplate = [directoryPath stringByAppendingPathComponent:@"%(title)s.%(ext)s"];
    NSString *videoURL = [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", [result videoId]];
    NSString *ffmpegPath = [YTDLPController bundledFFmpegPath];
    NSString *printFormat = [kFinalPathMarker stringByAppendingString:@"%(filepath)s"];

    NSArray *args = [NSArray arrayWithObjects:
                      @"-x",
                      @"--audio-format", @"mp3",
                      @"--audio-quality", @"0",
                      @"--ffmpeg-location", ffmpegPath,
                      @"--no-warnings",
                      @"-o", outputTemplate,
                      @"--newline",
                      @"--print", [@"after_move:" stringByAppendingString:printFormat],
                      videoURL,
                      nil];

    isSearchTask = NO;
    [pendingDownloadResult release];
    pendingDownloadResult = [result retain];
    [pendingDownloadOutputPath release];
    pendingDownloadOutputPath = nil;
    [outputBuffer release];
    outputBuffer = [[NSMutableData alloc] init];

    currentTask = [[self makeTaskWithArguments:args] retain];

    NSFileHandle *readHandle = [[currentTask standardOutput] fileHandleForReading];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(taskOutputAvailable:)
                                                  name:NSFileHandleReadCompletionNotification
                                                object:readHandle];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(taskDidTerminate:)
                                                  name:NSTaskDidTerminateNotification
                                                object:currentTask];
    [readHandle readInBackgroundAndNotify];

    NS_DURING
        [currentTask launch];
    NS_HANDLER
        if ([delegate respondsToSelector:@selector(ytdlpController:downloadDidFailWithMessage:)]) {
            [delegate ytdlpController:self downloadDidFailWithMessage:[localException reason]];
        }
    NS_ENDHANDLER
}

#pragma mark - NSTask callbacks

- (void)taskOutputAvailable:(NSNotification *)note
{
    NSData *data = [[note userInfo] objectForKey:NSFileHandleNotificationDataItem];
    NSFileHandle *handle = [note object];

    if ([data length] > 0) {
        [outputBuffer appendData:data];

        if (!isSearchTask) {
            NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSArray *lines = [chunk componentsSeparatedByString:@"\n"];
            NSEnumerator *e = [lines objectEnumerator];
            NSString *line;
            while ((line = [e nextObject]) != nil) {
                if ([line length] == 0) continue;
                if ([line hasPrefix:kFinalPathMarker]) {
                    [pendingDownloadOutputPath release];
                    pendingDownloadOutputPath = [[line substringFromIndex:[kFinalPathMarker length]] retain];
                } else if ([delegate respondsToSelector:@selector(ytdlpController:downloadProgress:)]) {
                    [delegate ytdlpController:self downloadProgress:line];
                }
            }
            [chunk release];
        }

        [handle readInBackgroundAndNotify];
    }
}

- (void)taskDidTerminate:(NSNotification *)note
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];

    NSString *fullOutput = [[NSString alloc] initWithData:outputBuffer encoding:NSUTF8StringEncoding];
    int status = [currentTask terminationStatus];

    if (isSearchTask) {
        NSMutableArray *results = [NSMutableArray array];
        NSArray *lines = [fullOutput componentsSeparatedByString:@"\n"];
        NSEnumerator *e = [lines objectEnumerator];
        NSString *line;
        while ((line = [e nextObject]) != nil) {
            if ([line length] == 0) continue;
            NSArray *fields = [line componentsSeparatedByString:YTDLP_FIELD_SEP];
            if ([fields count] < 4) continue;

            SearchResult *result = [[SearchResult alloc] init];
            [result setVideoId:[fields objectAtIndex:0]];
            [result setTitle:[fields objectAtIndex:1]];

            NSString *rawDuration = [fields objectAtIndex:2];
            [result setDurationString:[self formattedDuration:rawDuration]];
            [result setUploader:[fields objectAtIndex:3]];

            [results addObject:result];
            [result release];
        }

        if (status == 0 || [results count] > 0) {
            if ([delegate respondsToSelector:@selector(ytdlpController:didFindResults:)]) {
                [delegate ytdlpController:self didFindResults:results];
            }
        } else {
            if ([delegate respondsToSelector:@selector(ytdlpController:searchDidFailWithMessage:)]) {
                [delegate ytdlpController:self searchDidFailWithMessage:fullOutput];
            }
        }
    } else {
        if (status == 0 && pendingDownloadOutputPath != nil) {
            if ([delegate respondsToSelector:@selector(ytdlpController:downloadDidFinishForResult:outputPath:)]) {
                [delegate ytdlpController:self downloadDidFinishForResult:pendingDownloadResult outputPath:pendingDownloadOutputPath];
            }
        } else {
            if ([delegate respondsToSelector:@selector(ytdlpController:downloadDidFailWithMessage:)]) {
                [delegate ytdlpController:self downloadDidFailWithMessage:fullOutput];
            }
        }
    }

    [fullOutput release];
    [currentTask release];
    currentTask = nil;
}

- (NSString *)formattedDuration:(NSString *)rawSeconds
{
    if (rawSeconds == nil || [rawSeconds length] == 0 || [rawSeconds isEqualToString:@"NA"]) {
        return @"--:--";
    }
    double totalSeconds = [rawSeconds doubleValue];
    long seconds = (long)totalSeconds;
    long hours = seconds / 3600;
    long minutes = (seconds % 3600) / 60;
    long secs = seconds % 60;

    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", hours, minutes, secs];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", minutes, secs];
}

@end
