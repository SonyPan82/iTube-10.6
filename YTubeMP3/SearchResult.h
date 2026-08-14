// SearchResult.h
// Non-ARC (retain/release) model object — compatible with Xcode 3.2.6 / Mac OS X 10.6 SDK.

#import <Cocoa/Cocoa.h>

@interface SearchResult : NSObject
{
    NSString *videoId;
    NSString *title;
    NSString *uploader;
    NSString *durationString;
}

@property (nonatomic, retain) NSString *videoId;
@property (nonatomic, retain) NSString *title;
@property (nonatomic, retain) NSString *uploader;
@property (nonatomic, retain) NSString *durationString;

@end
