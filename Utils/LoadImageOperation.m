//
//  LoadImageOperation.m
//  ClockU
//
//  Created by Gary Morris on 5/16/10.
//  Copyright 2010 Gary A. Morris. All rights reserved.
//

#import "LoadImageOperation.h"
#import "UIImage-ResizeSameAspectRatio.h"

#ifdef DEBUG
#import "GMImage.h"
#endif

@implementation LoadImageOperation

- (id)initWithContext:(NSMutableDictionary *)aContext
			 selector:(SEL)aSelector
			   target:(id)aTarget
{
	if (self = [super init]) {
		selector = aSelector;
		target   = [aTarget retain];
		context  = [aContext retain];
	}
	return self;
}

- (void)dealloc {
	[target  release];
	[context release];
	[super dealloc];
}

//----------------------------------------------------------------------------
// saveImage - convert image to PNG, save to file, return file URL
//----------------------------------------------------------------------------
-(NSString*)saveImage:(UIImage*)image
{
	NSString* fullPathToFile = nil;
	
	// Create an autorelease pool so we don't keep png data around long
	NSAutoreleasePool * imagePool = [[NSAutoreleasePool alloc] init];
	{
		NSData*   pngData  = UIImagePNGRepresentation(image);
		NSString* filename = [NSString stringWithFormat:@"%0.0f.png", 
							  [NSDate timeIntervalSinceReferenceDate] * 1000];  // time w/millisec
		NSArray*  paths    = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES); 
		NSString* documentsDirectory = [paths objectAtIndex:0]; 
		
		// retain fullPathToFile so we still have it after pool drains
		fullPathToFile = [[documentsDirectory stringByAppendingPathComponent:filename] retain]; 
		
		// then we write it out 
		[pngData writeToFile:fullPathToFile atomically:NO]; 
	}
	[imagePool release];		// drain the pool
	
	// Create a URL from the file's path
	NSURL* tmpURL = [NSURL fileURLWithPath:fullPathToFile isDirectory:NO];
	[fullPathToFile release];	// done with this now
	
	NSString* urlStr = [tmpURL absoluteString];
	NSLog(@"%s saved %@ to %@", __PRETTY_FUNCTION__, NSStringFromCGSize(image.size), urlStr);

#ifdef DEBUG
	NSLog(@"scheme==%@, path=%@", [tmpURL scheme], [tmpURL path]);
#endif
	
	return urlStr;
}

//----------------------------------------------------------------------------
// main
//----------------------------------------------------------------------------
- (void)main {
	@try {
		NSString* urlStr = [context objectForKey:kURLKey];		// get URL string
		UIImage*  image  = [context objectForKey:kImageKey];	// get image ref
		NSString* errorMsg = nil;
		
		//--------------------------------------------------------
		// LOAD - If we have a URL but no image, request the image
		//--------------------------------------------------------
		if (urlStr && image==nil) {
			NSURL* url = [NSURL URLWithString:urlStr];
			NSURLResponse* response;
			NSError* error;
			
			// if it is a file URL, the path may have changed (happens
			// whenever the app is reinstalled or updated), fix path first
			if ([url isFileURL]) {
				// Check to see if file exists first, if not, try fixing the path
				BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:[url path]];
				if (!exists) {
					// path is not valid, recreate path from current Documents folder
					// in case the path has change due to install or update
					NSArray* oldPathNames = [urlStr componentsSeparatedByString:@"/"];
					NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES); 
					NSString* docsDir = [paths objectAtIndex:0]; 
					NSLog(@"%s file not found %@, trying %@", __PRETTY_FUNCTION__, urlStr, docsDir);
					urlStr = [docsDir stringByAppendingPathComponent:[oldPathNames lastObject]];
					url = [NSURL fileURLWithPath:urlStr isDirectory:NO];
				}
			}
			
			NSLog(@"%s requesting %@", __PRETTY_FUNCTION__, urlStr);
			
			NSData *data = [NSURLConnection
							sendSynchronousRequest:[NSURLRequest requestWithURL:url]
							returningResponse:&response
							error:&error];
			if (self.isCancelled) return;

			if (data) {
				image = [UIImage imageWithData:data];
			} else {
				NSLog(@"%s ERROR: %@, URL=%@", __PRETTY_FUNCTION__, error.localizedDescription, urlStr);
				NSArray* oldPathNames = [urlStr componentsSeparatedByString:@"/"];
				errorMsg = [NSString stringWithFormat:@"Not Found: %@", [oldPathNames lastObject]];
				[context setObject:errorMsg forKey:kErrorKey];
			}
		}
		
		if (image) {
			CGSize origSize   = image.size;
			CGSize screenSize = [UIScreen mainScreen].bounds.size;
			CGFloat maxImageDim  = MAX( origSize.width,   origSize.height   );
			CGFloat maxScreenDim = MAX( screenSize.width, screenSize.height );
			
			//------------------------------------------------------------
			// RESIZE - If the image is larger than will fit on the screen
			// resize the image to the maximum size usable on this device, 
			// while maintaining the aspect ratio, reduces memory usage.
			//------------------------------------------------------------
			if (maxImageDim > maxScreenDim) {
				// image is larger than necessary, it can't fit our screen, 
				// so reduce size to fit which will save memory
				CGFloat factor = maxScreenDim / maxImageDim;
				
				// replace image with resized copy
				image = [UIImage imageWithImage:image Factor:factor Quality:kCGInterpolationHigh];
				///image = [self resizeImage:image Factor:factor Quality:kCGInterpolationHigh];
			}
			
			if (urlStr==nil) {
				//------------------------------------------------------------
				// SAVE - we have an image but no URL, save image to a file,
				// and create a URL for it.
				//------------------------------------------------------------
				urlStr = [self saveImage:image];
				if (urlStr) {
					[context setObject:urlStr forKey:kURLKey];
				}
			}
		
			[context setObject:image forKey:kImageKey];
		}
	}
	@catch (NSException *exception) {
		NSLog(@"%s: EXCEPTION %@: %@", __PRETTY_FUNCTION__, exception.name, exception.reason);
		[context setObject:exception.name forKey:kErrorKey];
	}
	
	// Notify target that the operation is completed.
	[target performSelectorOnMainThread:selector
							 withObject:context waitUntilDone:NO];
}

@end
