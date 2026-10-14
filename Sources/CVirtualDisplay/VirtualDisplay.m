#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "VirtualDisplay.h"

// Undocumented CoreGraphics interfaces. Signatures cross-checked against
// Chromium's ui/display/mac/test/virtual_display_util_mac.mm. Runtime-gated.
@interface UCDisplayDescriptor : NSObject
@property unsigned int vendorID, productID, serialNum, serialNumber;
@property unsigned int maxPixelsWide, maxPixelsHigh;
@property CGSize sizeInMillimeters;
@property CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;
@property(strong) NSString *name;
@property(strong) id queue;
@end
@interface UCDisplayMode : NSObject
- (id)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
@interface UCDisplaySettings : NSObject
@property unsigned int hiDPI;
@property(strong) NSArray *modes;
@end
@interface UCDisplay : NSObject
- (id)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property(readonly) unsigned int displayID;
@end

void *uca_display_create(uint32_t width, uint32_t height, int hiDPI) {
    if (width < 640 || width > 2560 || height < 480 || height > 2560) return NULL;
    @autoreleasepool {
    @try {
        Class dc = NSClassFromString(@"CGVirtualDisplayDescriptor");
        Class mc = NSClassFromString(@"CGVirtualDisplayMode");
        Class sc = NSClassFromString(@"CGVirtualDisplaySettings");
        Class vc = NSClassFromString(@"CGVirtualDisplay");
        if (!dc || !mc || !sc || !vc) return NULL;
        UCDisplayDescriptor *d = [[dc alloc] init];
        d.name = @"Android Extended Display";
        d.vendorID = 0x5543; d.productID = 1;
        // Stable per-layout identity avoids macOS restoring another orientation's mode.
        // This is derived only from public dimensions, never a device identifier.
        d.serialNum = (width << 16) | height; d.serialNumber = d.serialNum;
        d.maxPixelsWide = width; d.maxPixelsHigh = height;
        d.sizeInMillimeters = CGSizeMake(width * 25.4 / 160, height * 25.4 / 160);
        d.redPrimary = CGPointMake(0.64, 0.33); d.greenPrimary = CGPointMake(0.30, 0.60);
        d.bluePrimary = CGPointMake(0.15, 0.06); d.whitePoint = CGPointMake(0.3127, 0.3290);
        d.queue = dispatch_get_main_queue();
        UCDisplay *display = [[vc alloc] initWithDescriptor:d];
        UCDisplaySettings *settings = [[sc alloc] init]; settings.hiDPI = hiDPI ? 1 : 0;
        id mode = [[mc alloc] initWithWidth:(hiDPI ? width / 2 : width) height:(hiDPI ? height / 2 : height) refreshRate:30];
        if (!mode || !display) return NULL;
        settings.modes = @[mode];
        if (![display applySettings:settings] || !display.displayID) return NULL;
        return (__bridge_retained void *)display;
    } @catch (NSException *exception) { return NULL; }
    }
}
uint32_t uca_display_id(void *display) { return display ? [(__bridge UCDisplay *)display displayID] : 0; }
void uca_display_destroy(void *display) { if (display) { id released = (__bridge_transfer id)display; (void)released; } }
