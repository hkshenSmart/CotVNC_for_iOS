/* HextileEncodingReader.h created by helmut on Wed 17-Jun-1998 */

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

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "EncodingReader.h"

#define TILE_SIZE	16

@interface HextileEncodingReader : EncodingReader
{
    id			subEncodingReader;
    id			rawReader;
    id			backGroundReader;
    id			foreGroundReader;
    id			numOfSubRectReader;
    id			subColorRectReader;
    id			subRectReader;
    FrameBufferColor	background;
    FrameBufferColor	foreground;
    CARD8		numOfSubRects;
    CARD8		subEncodingMask;
    CGRect		currentTile;
}

- (void)nextTile;
- (void)drawSubColorRects:(NSData*)data;
- (void)drawSubRects:(NSData*)data;
- (void)drawRawTile:(NSData*)data;

@end
