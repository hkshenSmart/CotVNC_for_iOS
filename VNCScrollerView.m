//
//  VNCScrollerView.m
//  vnsea
//
//  Created by Chris Reed on 10/16/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//  Modified by: Glenn Kreisel

#import "VNCScrollerView.h"
#import "VNCView.h"
//#import "VNCMouseTracks.h"
//#import "VNCPreferences.h"

#define kMinScale (0.10f)
#define kMaxScale (3.0f)

// Some extra UIKit functions.
extern float UIDistanceBetweenPoints(CGPoint a, CGPoint b);
extern CGPoint UIMidPointBetweenPoints(CGPoint a, CGPoint b);

@implementation VNCScrollerView

- (void)setEventFilter:(EventFilter *)filter
{
	_eventFilter = filter;
}

- (BOOL)canHandleGestures
{
  return NO;
}

- (void)setVNCView:(VNCView *)view
{
	_vncView = view;
//	_windowPopupScalePercent = nil;
//	_windowPopupMouseDown = nil;
	_scrollTimer = nil;
	_doubleTapTimer = nil;
	_bZoomedIn = false;
}

-(void)toggleViewOnly
{
	_viewOnly = !_viewOnly;
	[_vncView enableControlsForViewOnly: _viewOnly];
}

- (void)setViewOnly:(bool)isViewOnly
{
	_viewOnly = isViewOnly;
}

- (bool)useRightMouse
{
	return _useRightMouse;
}

- (void)setUseRightMouse:(bool)useRight
{
	_useRightMouse = useRight;
}

- (BOOL)canBecomeFirstResponder
{
	return YES;
}

//- (void)sendMouseDown:(GSEventRef)theEvent
//{
//	if (_useRightMouse)
//	{
//		[_eventFilter rightMouseDown:theEvent];
//		_inRightMouse = YES;
//		
//		[[self superview] toggleRightMouse:self];
//	}
//	else
//	{
//		[_eventFilter mouseDown:theEvent];
//	}
//}
//
//- (void)sendMouseUp:(GSEventRef)theEvent
//{
//	// Need to send the corresponding mouse up, regardless the current
//	// use right mouse state.
//	if (_inRightMouse)
//	{
//		[_eventFilter rightMouseUp:theEvent];
//		_inRightMouse = NO;
//	}
//	else
//	{
//		[_eventFilter mouseUp:theEvent];
//	}
//}
//
//- (void)cleanUpMouseTracks
//{
//	if (_windowPopupScalePercent != nil)
//	{
//		_isZooming = false;
//		[_windowPopupScalePercent setHidden:true];
//		[_windowPopupScalePercent release];
//		_windowPopupScalePercent = nil;
//	}
//	
//	if (_windowPopupMouseDown != nil)
//	{
//		[_windowPopupMouseDown hide];
//		_windowPopupMouseDown = nil;
//	}
//	
//	if (_windowPopupMouseUp != nil)
//	{
//		[_windowPopupMouseUp hide];
//		_windowPopupMouseUp = nil;
//	}
//}


// Auto scroll function called by timer and mouse is on edges of device and dragging
// This also submits the original drag event so that the vnc server updates the mouse to the new location 
// under your finger
//- (void)handleScrollTimer:(NSTimer *)timer
//{
//	int dxAutoScroll = 3, dyAutoScroll = 3;
//	CGPoint ptLeftTop = [self bounds].origin;
//	
//	if (_currentAutoScrollerType & kAutoScrollerRight)
//	{
//		ptLeftTop.x += dxAutoScroll;
//	}
//	else if (_currentAutoScrollerType & kAutoScrollerLeft)
//	{
//		ptLeftTop.x -= dxAutoScroll;
//	}
//					
//	if (_currentAutoScrollerType & kAutoScrollerUp)
//	{
//		ptLeftTop.y -= dyAutoScroll;
//	}
//	else if (_currentAutoScrollerType & kAutoScrollerDown)
//	{
//		ptLeftTop.y += dyAutoScroll;
//	}
//				
//	[self scrollPointVisibleAtTopLeft: ptLeftTop];	
//	[_eventFilter mouseDragged:_autoLastDragEvent];
//}
//
//
//- (void)handleDoubleTapTimer:(NSTimer *)timer
//{
//	NSLog(@"Double click expired");
//	[_doubleTapTimer release];
//	_doubleTapTimer = nil;
//}
//
//- (void)handleTapTimer:(NSTimer *)timer
//{
//	_inRemoteAction = true;
//	
//	// Send the original event.
//	GSEventRef theEvent = (GSEventRef)[timer userInfo];
////	NSLog(@"tapTimer:%@", theEvent);
//	
//	[self sendMouseDown:theEvent];
//	
//	// Do mouse tracks
//	if ([[VNCPreferences sharedPreferences] showMouseTracks] && !_viewOnly)
//	{
//		if (_windowPopupMouseDown != nil)
//		{
//			[_windowPopupMouseDown hide];
//			_windowPopupMouseDown = nil;
//		}
//		CGPoint ptVNC = [_eventFilter getVNCScreenPoint: GSEventGetLocationInWindow(theEvent)];
//	
//		_windowPopupMouseDown = [[VNCMouseTracks alloc] initWithFrame: CGRectMake(ptVNC.x, ptVNC.y, 10, 10) style:kPopupStyleMouseDown scroller:self];	
//		[_windowPopupMouseDown setTimer:[[VNCPreferences sharedPreferences] mouseTracksFadeTime] info:nil]; 
//	}
//	
//	// The event is no longer needed.
//	CFRelease(theEvent);
//	
//	[_tapTimer release];
//	_tapTimer = nil;
//}
//
//- (void)mouseDown:(GSEventRef)theEvent
//{
//	// Do nothing if there is no connection.
//	if (!_eventFilter)
//	{
//		return;
//	}
//	
//	// if mousedown then we must not be in a drag event so reset Autoscroll during drag
//	if (_scrollTimer != nil)
//	{
//		[_scrollTimer invalidate];
//		[_scrollTimer release];
//		_scrollTimer = nil;
//		CFRelease(_autoLastDragEvent);
//	}
//	_currentAutoScrollerType = kAutoScrollerNone;
//	
//	bool isChording = GSEventIsChordingHandEvent(theEvent);	
////	int count = GSEventGetClickCount(theEvent);
////	NSLog(@"mouseDown:%c:%d", isChording ? 'y' : 'n', count);
//
//	// Prepare for zooming and/or panning when it's a chorded mouse down.
//	if (isChording)
//	{	
//		CGPoint pt1 = GSEventGetInnerMostPathPosition(theEvent);
//		CGPoint pt2 = GSEventGetOuterMostPathPosition(theEvent);
//		
//		_fDistanceStart = UIDistanceBetweenPoints(pt1, pt2);
//		_fDistancePrev = _fDistanceStart;
//		if (_windowPopupScalePercent == nil)
//		{
//			CGPoint ptCenter = UIMidPointBetweenPoints(pt1, pt2);
//			bool showPopup = [[VNCPreferences sharedPreferences] showScrollingIcon];
//			
//			_windowPopupScalePercent = [[VNCPopupWindow alloc] initWithFrame: CGRectMake(0, 0, POPUP_WINDOW_WIDTH, POPUP_WINDOW_HEIGHT) centered:true show:showPopup orientation:[_vncView orientationDegree] style:kPopupStyleDrag];
//			[_windowPopupScalePercent setCenterLocation: ptCenter]; 
//			[_windowPopupScalePercent setTextPercent: [_vncView getScalePercent]];
//			
//			_isZooming = false;
//		}
//	}
//	
//	if (isChording || _viewOnly)
//	{
//		// If the timer exists, it means we haven't yet sent the single finger mouse
//		// down. Kill the timer so that the event is never sent.
//		if (_tapTimer)
//		{
////			NSLog(@"killed tap timer");
//			[_tapTimer invalidate];
//			[_tapTimer release];
//			_tapTimer = nil;
//		}
//		if (_viewOnly && !isChording)
//			{
//			if (!_doubleTapTimer)
//				_doubleTapTimer = [[NSTimer scheduledTimerWithTimeInterval:.2 target:self selector:@selector(handleDoubleTapTimer:) userInfo:nil repeats:NO] retain];
//			else
//				{
//				float newScale;
//				
//				NSLog(@"Double clicked it");
//				[_doubleTapTimer invalidate];
//				[_doubleTapTimer release];
//				_doubleTapTimer = nil;
//				CGPoint ptCenter = GSEventGetInnerMostPathPosition(theEvent);
//				
//				if (_bZoomedIn)
//					{
//					newScale = _preDoubleClickZoom;
//					_bZoomedIn = false;
//					}
//				else
//					{
//					_preDoubleClickZoom = [_vncView getScalePercent];
//					newScale = 1.0;
//					_bZoomedIn = true;
//					}
//				[self changeViewPinnedToPoint:ptCenter scale:newScale orientation:[_vncView getOrientationState] force:true];
//				}
//			}
//		
//		// Need to send a mouse up when switching from remote mouse to scrolling.
//		// This assumes that _inRemoteAction will only ever be true after a mouse
//		// down and before a mouse up.
//		if (_inRemoteAction)
//		{
//			[self sendMouseUp:theEvent];
//			_inRemoteAction = NO;
//		}
//		
//		// Let the superclass handle scrolling.
//		[super mouseDown:theEvent];
//	}
//	else
//	{
//		// Keep this event around for a bit.
//		CFRetain(theEvent);
//		
//		// We don't want to send the mouse down event quite yet, because we
//		// need to wait to see if this is really a chording event for scrolling.
//		// So create a timer that when it fires will send the original event.
//		// If a chording mouse down happens before the timer fires, it will be
//		// killed.
//		_tapTimer = [[NSTimer scheduledTimerWithTimeInterval:[[VNCPreferences sharedPreferences] mouseDownDelay] target:self selector:@selector(handleTapTimer:) userInfo:(id)theEvent repeats:NO] retain];
//	}
//}

- (CGPoint)getIPodScreenPoint:(CGRect)r bounds:(CGRect)bounds
{
	return [_vncView getIPodScreenPoint: r bounds: bounds];
}

//- (void)mouseUp:(GSEventRef)theEvent
//{
//	// Do nothing if there is no connection.
//	if (_windowPopupScalePercent != nil)
//	{
//		_isZooming = false;
//		[_windowPopupScalePercent setHidden:true];
//		[_windowPopupScalePercent release];
//		_windowPopupScalePercent = nil;
//	}
//	
//	if (!_eventFilter)
//	{
//		return;
//	}	
//	
//	// Autoscroll during drag must be over
//	if (_scrollTimer != nil)
//	{
//		[_scrollTimer invalidate];
//		_scrollTimer = nil;
//		CFRelease(_autoLastDragEvent);
//	}
//	
//	if (_tapTimer)
//	{
//		[_tapTimer fire];
//	}
//
//	if (_inRemoteAction)
//	{
//		if ([[VNCPreferences sharedPreferences] showMouseTracks] && !_viewOnly)
//		{
//			if (_windowPopupMouseUp != nil)
//			{
//				[_windowPopupMouseUp hide];
//				_windowPopupMouseUp = nil;
//			}
//			CGPoint ptVNC = [_eventFilter getVNCScreenPoint: GSEventGetLocationInWindow(theEvent)];
//			
//			// Show mouse track for up event.
//			CGRect popupFrame = CGRectMake(ptVNC.x, ptVNC.y, 10, 10);
//			_windowPopupMouseUp = [[VNCMouseTracks alloc] initWithFrame:popupFrame style:kPopupStyleMouseUp scroller:self];			
//			[_windowPopupMouseUp setTimer:[[VNCPreferences sharedPreferences] mouseTracksFadeTime] info:nil]; 
//		}
//
//		[self sendMouseUp:theEvent];
//		_inRemoteAction = NO;
//	}
//	else
//	{
//		[super mouseUp:theEvent];
//	}
//}

//- (void)changeViewPinnedToPoint:(CGPoint)ptPinned scale:(float)fScale orientation:(UIDeviceOrientation)wOrientationState force:(BOOL)bForce
//{
//	CGRect r = CGRectMake(ptPinned.x, ptPinned.y, 1,1);
//	CGPoint ptVNCBefore = [_eventFilter getVNCScreenPoint: r];
//	r.origin = ptVNCBefore;
//	CGRect bounds = [self bounds];
//	CGPoint ptIPodBefore = [_vncView getIPodScreenPoint: r bounds: bounds];
//	CGPoint ptLeftTop = bounds.origin;
//	bool bOrientationChange;
//	
////	NSLog(@"iPodScreen Point %f,%f", ptIPodBefore.x, ptIPodBefore.y);
//
//	[_vncView setScalePercent: fScale];
//	bOrientationChange = [_vncView getOrientationState] != wOrientationState;
//	[_vncView setOrientation:wOrientationState bForce:bForce];
//	r.origin = ptVNCBefore;
//	CGPoint ptIPodAfter = [_vncView getIPodScreenPoint: r bounds: bounds];
////	NSLog(@"IPod After %f,%f", ptIPodAfter.x, ptIPodAfter.y);
////	NSLog(@"");
//	ptLeftTop.x +=(ptIPodAfter.x - ptIPodBefore.x);
//	ptLeftTop.y += (ptIPodAfter.y - ptIPodBefore.y);
//	
////  Try to prevent orientation change from making the screen scroll too far
//	if (bOrientationChange)
//	{
//		ptLeftTop.x = MAX(0, ptLeftTop.x);
//		ptLeftTop.y = MAX(0, ptLeftTop.y);
////		if (ptLeftTop.x + [_scroller frame].size.width > [_scroller bounds].size.width)
////			{
////			NSLog(@"Scroller set too far");
////			}
//	}
////	NSLog(@"topleft %f,%f", ptLeftTop.x, ptLeftTop.y);
//	[self scrollPointVisibleAtTopLeft: ptLeftTop];
//	
//// Make sure the MouseTracks get updated to the new Scale / Orientation
//	if (_windowPopupMouseDown != nil)
//	{
//		[_windowPopupMouseDown zoomOrientationChange];
//	}
//	if (_windowPopupMouseUp != nil)
//	{
//		[_windowPopupMouseUp zoomOrientationChange];
//	}
//}
//
//
////! Determines if we need to autoscroll while dragging. If so, then it
////! sets up the autoscroll timer.
//- (void)checkForAutoscrollEvents:(GSEventRef) theEvent
//{
//	CGPoint ptDrag = GSEventGetLocationInWindow(theEvent).origin;
//	CGRect rcFrame = [self frame];
//	AutoScrollerTypes newAutoScroller = kAutoScrollerNone;
//	
//	if (ptDrag.x > (rcFrame.origin.x+rcFrame.size.width) - LEFTRIGHT_AUTOSCROLL_BORDER && ptDrag.x < (rcFrame.origin.x+rcFrame.size.width))
//	{
//		newAutoScroller = kAutoScrollerRight;
//	}
//	else if (ptDrag.x < LEFTRIGHT_AUTOSCROLL_BORDER && ptDrag.x >= 0)
//	{
//		newAutoScroller = kAutoScrollerLeft;
//	}
//		
//	if (ptDrag.y < TOPBOTTOM_AUTOSCROLL_BORDER && ptDrag.y >= 0)
//	{
//		newAutoScroller |= kAutoScrollerUp;
//	}
//	else if (ptDrag.y > rcFrame.size.height - TOPBOTTOM_AUTOSCROLL_BORDER && ptDrag.y < rcFrame.size.height)
//	{
//		newAutoScroller |= kAutoScrollerDown;
//	}
//	
//	if (newAutoScroller != _currentAutoScrollerType)
//	{
//		_currentAutoScrollerType = newAutoScroller;
//		
//		NSLog(@"In border Area %d", newAutoScroller);
//		
//		// Get rid of any old autoscroll timer.
//		if (_scrollTimer != nil)
//		{
//			[_scrollTimer invalidate];
//			[_scrollTimer release];
//			_scrollTimer = nil;
//			CFRelease(_autoLastDragEvent);
//		}
//		
//		// Setup autoscroll timer if we're scrolling.
//		if (newAutoScroller != kAutoScrollerNone)
//		{
//			NSLog(@"Starting Timer");
//			CFRetain(theEvent);
//			_autoLastDragEvent = theEvent;
//			_scrollTimer = [[NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(handleScrollTimer:) userInfo:nil repeats:YES] retain];
//		}
//	}
//}
//
//- (void)mouseDragged:(GSEventRef)theEvent
//{
//	// Do nothing if there is no connection.
//	if (!_eventFilter)
//	{
//		return;
//	}
//	
//	bool isChording = GSEventIsChordingHandEvent(theEvent);	
//
//	if (isChording)
//	{	
//		CGPoint pt1 = GSEventGetInnerMostPathPosition(theEvent);
//		CGPoint pt2 = GSEventGetOuterMostPathPosition(theEvent);
//		
//		float fDistance = UIDistanceBetweenPoints(pt1, pt2);
//		float fHowFar = fDistance - _fDistancePrev;
//		CGPoint ptCenter = UIMidPointBetweenPoints(pt1, pt2);
//
//		// Check if the distance between fingers has crossed a threshold. The threshold value
//		// depends on if we're in view-only mode, or are already zooming.
//		if (abs(fHowFar) > (_viewOnly || _isZooming ? 3 : 20))
//		{
//			float fOldScale = [_vncView getScalePercent];
//			float fNewScale = fOldScale + (0.0025 * fHowFar);
//			
//			// Snap to 100%.
//			if (fabsf(1.0 - fNewScale) < 0.007)
//			{
//				fNewScale = 1.0;
//			}
//			
//			_isZooming = true;
//			[_windowPopupScalePercent setStyleWindow: kPopupStyleScalePercent];
//			[_windowPopupScalePercent setHidden:![[VNCPreferences sharedPreferences] showZoomPercent]];
//			
//			// If the scale is within bounds, update zoom.
//			if ((fNewScale > [_vncView scaleFitCurrentScreen: kScaleFitWhole] || (fNewScale > fOldScale)) && fNewScale < kMaxScale)
//			{
//				// Update the popup window showing the current scale percentage.
//				[_windowPopupScalePercent setTextPercent: fNewScale];
//				[_windowPopupScalePercent setCenterLocation: ptCenter]; 
//			
//				_bZoomedIn = false;
//				// Zoom the view.
//				[self changeViewPinnedToPoint:ptCenter scale:fNewScale orientation:[_vncView getOrientationState] force:true];
//			}
//			
//			_fDistancePrev = fDistance;
//			return;
//		}
//		else
//		{
//			// Either we're only scrolling, or the distance between fingers hasn't changed enough
//			// to warrant updating the zoom amount. In both cases, all we have to do here is
//			// update the popup window location. For chorded scrolling, we'll let the superview
//			// handle the actual scrolling down below.
//			[_windowPopupScalePercent setCenterLocation: ptCenter];
//		}
//
//		// Chorded events are never passed to the remote server or handled by the
//		// UIScroller superclass (the code below) if we're in view-only mode or are
//		// zooming.
//		if (_viewOnly || _isZooming)
//		{
//			return;
//		}
//	}
//
//	if (_doubleTapTimer)
//		{
//		NSLog(@"Double clicked cancelled");
//		[_doubleTapTimer invalidate];
//		[_doubleTapTimer release];
//		_doubleTapTimer = nil;
//		}
//
//	// If the user starts dragging her finger before the tap timer expires, then we need
//	// to send the mouse down before any mouse moved events are sent to the server.
//	if (_tapTimer)
//	{
//		[_tapTimer fire];
//	}
//
//	if (_inRemoteAction)
//	{
//		[self checkForAutoscrollEvents: theEvent];
//		[_eventFilter mouseDragged:theEvent];
//	}
//	else
//	{
//		[super mouseDragged:theEvent];
//	}
//}

@end
