//
//  XcursorEncodingReader.m
//  SmartCallEx
//
//  Created by shenkun on 16/5/26.
//  Copyright © 2016年 Cellcom. All rights reserved.
//

#import "XcursorEncodingReader.h"
#import "ByteBlockReader.h"

@implementation XcursorEncodingReader

- (id)initTarget:(id)aTarget action:(SEL)anAction {
    if (self = [super initTarget:aTarget action:anAction]) {
        pixelReader = [[ByteBlockReader alloc] initTarget:self action:@selector(setCursor:)];
    }
    return self;
}

- (void)resetReader {
    CGRect srect = frame;
    int bytesPerRow = (srect.size.width + 7) / 8;
    int bytesMaskData = bytesPerRow * srect.size.height;
    NSLog(@"frameBuffer bytesPerPixel:%d", [frameBuffer bytesPerPixel]);
    int bytesSourceData = srect.size.width * srect.size.height * ([frameBuffer bytesPerPixel]);
//    int bytesSourceData = srect.size.width * srect.size.height * (m_pRoom->m_FBPixel / 8);
//    
//    int bytesToSkip = 6 + 2 * bytesMaskData;
    int bytesToSkip = bytesSourceData + bytesMaskData;
    
//#ifdef COLLECT_STATS
//    bytesTransferred = bytesToSkip;
//#endif
    [pixelReader setBufferSize:bytesToSkip];
    
    [target setReader:pixelReader];
}

- (void)setCursor:(NSData*)pixel {
    
    //画出来    
    //[frameBuffer putRect:frame fromData:(unsigned char*)[pixel bytes]];
    [target performSelector:action withObject:self];
}

@end

