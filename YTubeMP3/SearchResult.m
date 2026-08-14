// SearchResult.m

#import "SearchResult.h"

@implementation SearchResult

@synthesize videoId;
@synthesize title;
@synthesize uploader;
@synthesize durationString;

- (void)dealloc
{
    [videoId release];
    [title release];
    [uploader release];
    [durationString release];
    [super dealloc];
}

@end
