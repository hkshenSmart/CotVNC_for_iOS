/* RFBServerInitReader.m created by helmut on Tue 16-Jun-1998 */

/* Copyright (C) 1998-2000  Helmut Maierhofer <helmut.maierhofer@chello.at>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 */

#import "RFBServerInitReader.h"
#import "ByteBlockReader.h"
#import "RFBStringReader.h"
#import "CARD32Reader.h"

@implementation ServerInitMessage

- (void)setFixed:(NSData*)data
{
	NSLog(@"server init fixed=%d bytes", [data length]);
    memcpy(&fixed, [data bytes], sizeof(fixed));
    fixed.width = ntohs(fixed.width);
    fixed.height = ntohs(fixed.height);
    fixed.red_max = ntohs(fixed.red_max);
    fixed.green_max = ntohs(fixed.green_max);
    fixed.blue_max = ntohs(fixed.blue_max);
	NSLog(@"fixed.width=%d", (int)fixed.width);
	NSLog(@"fixed.height=%d", (int)fixed.height);
}

- (unsigned char*)pixelFormatData
{
    return &fixed.bpp;
}

- (void)dealloc
{
    [name release];
    [super dealloc];
}

- (void)setName:(NSString*)aName
{
    [name autorelease];
    name = [aName retain];
}

- (NSString*)name
{
    return name;
}

- (CGSize)size
{
    CGSize s;
	
	// For some reason, we have to go through this rigamarole to convert
	// from CARD16 to float format on the iPhone! Must be an issue with
	// the ARM FP library or something.
	int iw;
	int ih;
	float fw;
	float fh;
	
	iw = (int)fixed.width;
	ih = (int)fixed.height;
	
	fw = (float)iw;
	fh = (float)ih;
	
    s.width = fw;
    s.height = fh;
    return s;
}

@end

@implementation RFBServerInitReader

- (id)initTarget:(id)aTarget action:(SEL)anAction
{
    if (self = [super initTarget:aTarget action:anAction]) {
        blockReader = [[ByteBlockReader alloc] initTarget:self action:@selector(setBlock:) size:20];
        nameReader = [[RFBStringReader alloc] initTarget:self action:@selector(setName:)];
        appshareReader = [[CARD32Reader alloc] initTarget:self action:@selector(getAppSharingState:)];
        appNumberReader = [[CARD32Reader alloc] initTarget:self action:@selector(getAppNumber:)];
        appInfoReader = [[ByteBlockReader alloc] initTarget:self action:@selector(getAppInfoBlock:) size:sizeof(myrfbAppInfo)];
        
        
        msg = [[ServerInitMessage alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [nameReader release];
    [blockReader release];
    [appshareReader release];
    [appNumberReader release];
    [appInfoReader release];
    if (appTitleReader) {
        [appTitleReader release];
        appTitleReader = nil;
    }
    [msg release];
    [super dealloc];
}

- (void)resetReader
{
    [target setReader:blockReader];
}

- (void)setBlock:(NSData*)theBlock
{
    [msg setFixed:theBlock];
    [target setReader:nameReader];
}

- (void)getAppInfoBlock:(NSData*)theBlock
{
    myrfbAppInfo newapp;
    memcpy(&newapp, [theBlock bytes], sizeof(myrfbAppInfo));
    newapp.appthreadid = Swap32IfLE(newapp.appthreadid);
    newapp.titlelength = Swap32IfLE(newapp.titlelength);
    if (appTitleReader) {
        [appTitleReader release];
        appTitleReader = nil;
    }
    appTitleReader = [[ByteBlockReader alloc] initTarget:self action:@selector(getAppTitleBlock:) size:newapp.titlelength];
    [target setReader:appTitleReader];
}

- (void)getAppTitleBlock:(NSData*)theBlock
{
    char appTitle[256];
    memset(appTitle, 0x00, 256);
    memcpy(appTitle, theBlock, MIN(255, [theBlock length]));
    appNum --;
    if (appNum > 0) {
        [target setReader:appInfoReader];
    }
    else {
        [target performSelector:action withObject:msg];
    }
}

- (void)setName:(NSString*)aName
{
    [msg setName:aName];
    [target setReader:appshareReader];
    //[target performSelector:action withObject:msg];
}

- (void)getAppSharingState:(NSNumber*)appSharing
{
    uint32_t appsharingstatus = [appSharing unsignedIntValue];
    //uint32_t appsharingstatus;
    //appsharingstatus = Swap32IfLE(appSharingResult);
    switch (appsharingstatus) {
        case myrfbAppSharingYes:
            [target setReader:appNumberReader];
            break;
        case myrfbAppSharingNo:
            [target performSelector:action withObject:msg];
            break;
        default:
            break;
    }
}

- (void)getAppNumber:(NSNumber*)appNumber
{
    appNum = [appNumber unsignedIntValue];
    if (appNum > 0) {
        [target setReader:appInfoReader];
    }
    else {
       [target performSelector:action withObject:msg];
    }
}




@end
