//
//  EventFilter.m
//  Chicken of the VNC
//
//  Created by Jason Harris on 7/1/05.
//  Copyright 2005 Geekspiff. All rights reserved.
//

#import "EventFilter.h"
//#import "KeyEquivalentManager.h"
#import "Profile.h"
#import "QueuedEvent.h"
#import "RFBConnection.h"

#define CHANGE_DIFF 3

//! Ignore up to 10 drag events in a row, unless the delta X/Y from the
//! last event we sent is greater than 3 pixels.
#define IGNORE_COUNT 10

#define kMouseHysteresisPixels (5.0)

//! @brief Entry in a map to convert from character to key and modifiers.
struct _key_modifier_map
{
	unichar character;				//!< The actual character being typed.
	unichar unmodifiedCharacter;	//!< What the character on a physical keyboard key would be.
	unsigned int modifiers;			//!< The modified required to produce the original character.
};

typedef struct _key_modifier_map key_modifier_map_t;

//! Map to convert from modified characters to the unmodified character
//! and the modifiers required to produce it. This map is necessary
//! because the UIKit keyboard does not give us an event with the raw
//! unmodified characters and modifiers that are necessary for the RFB
//! protocol. More characters than can currently be typed with the UIKit
//! keyboard are in this map, but it won't hurt any more than a small
//! performance penalty.
//!
//! @note Because Unicode characters are used here instead of ASCII, this
//! map is too big to convert to a direct index table. Another option for
//! speeding it up would be to sort by character value and use a binary
//! search algorithm instead of linear.
//!
//! @todo Convert the non-ASCII characters in this table into hex codes.
const key_modifier_map_t kKeyModifierMap[] = {
		{ L'~', L'`', NSShiftKeyMask },
		{ L'!', L'1', NSShiftKeyMask },
		{ L'@', L'2', NSShiftKeyMask },
		{ L'#', L'3', NSShiftKeyMask },
		{ L'$', L'4', NSShiftKeyMask },
		{ L'%', L'5', NSShiftKeyMask },
		{ L'^', L'6', NSShiftKeyMask },
		{ L'&', L'7', NSShiftKeyMask },
		{ L'*', L'8', NSShiftKeyMask },
		{ L'(', L'9', NSShiftKeyMask },
		{ L')', L'0', NSShiftKeyMask },
		{ L'_', L'-', NSShiftKeyMask },
		{ L'+', L'=', NSShiftKeyMask },
		{ L'{', L'[', NSShiftKeyMask },
		{ L'}', L']', NSShiftKeyMask },
		{ L'|', L'\\', NSShiftKeyMask },
		{ L':', L';', NSShiftKeyMask },
		{ L'"', L'\'', NSShiftKeyMask },
		{ L'<', L',', NSShiftKeyMask },
		{ L'>', L'.', NSShiftKeyMask },
		{ L'?', L'/', NSShiftKeyMask },
		
		{ L'¡', L'1', NSAlternateKeyMask },
		{ L'™', L'2', NSAlternateKeyMask },
		{ L'£', L'3', NSAlternateKeyMask },
		{ L'¢', L'4', NSAlternateKeyMask },
		{ L'∞', L'5', NSAlternateKeyMask },
		{ L'§', L'6', NSAlternateKeyMask },
		{ L'¶', L'7', NSAlternateKeyMask },
		{ L'•', L'8', NSAlternateKeyMask },
		{ L'ª', L'9', NSAlternateKeyMask },
		{ L'º', L'0', NSAlternateKeyMask },
		{ L'–', L'-', NSAlternateKeyMask },
		{ L'≠', L'=', NSAlternateKeyMask },
		
		{ L'œ', L'q', NSAlternateKeyMask },
		{ L'∑', L'w', NSAlternateKeyMask },
		{ L'®', L'r', NSAlternateKeyMask },
		{ L'†', L't', NSAlternateKeyMask },
		{ L'¥', L'y', NSAlternateKeyMask },
		{ L'ø', L'o', NSAlternateKeyMask },
		{ L'π', L'p', NSAlternateKeyMask },
		{ L'“', L'[', NSAlternateKeyMask },
		{ L'‘', L']', NSAlternateKeyMask },
		{ L'«', L'\\', NSAlternateKeyMask },
		
		{ L'å', L'a', NSAlternateKeyMask },
		{ L'ß', L's', NSAlternateKeyMask },
		{ L'∂', L'd', NSAlternateKeyMask },
		{ L'ƒ', L'f', NSAlternateKeyMask },
		{ L'©', L'g', NSAlternateKeyMask },
		{ L'˙', L'h', NSAlternateKeyMask },
		{ L'∆', L'j', NSAlternateKeyMask },
		{ L'˚', L'k', NSAlternateKeyMask },
		{ L'¬', L'l', NSAlternateKeyMask },
		{ L'…', L';', NSAlternateKeyMask },
		{ L'æ', L'\'', NSAlternateKeyMask },
		
		{ L'Ω', L'z', NSAlternateKeyMask },
		{ L'≈', L'x', NSAlternateKeyMask },
		{ L'ç', L'c', NSAlternateKeyMask },
		{ L'√', L'v', NSAlternateKeyMask },
		{ L'∫', L'b', NSAlternateKeyMask },
		{ L'µ', L'm', NSAlternateKeyMask },
		{ L'≤', L',', NSAlternateKeyMask },
		{ L'≥', L'.', NSAlternateKeyMask },
		{ L'÷', L'/', NSAlternateKeyMask },
		
		{ L'€', L'2', NSShiftKeyMask | NSAlternateKeyMask },
		
		// Terminate the list with a zero entry
		{ 0 }
	};

static inline unsigned int
ButtonNumberToArrayIndex( unsigned int buttonNumber )
{
	NSCParameterAssert( buttonNumber == 2 || buttonNumber == 3 );
	return buttonNumber - 2;
}


static inline unsigned int
ButtonNumberToRFBButtomMask( unsigned int buttonNumber )
{  return 1 << (buttonNumber-1);  }


@implementation EventFilter

#pragma mark Creation/Destruction

- (void)_resetMultiTapTimer: (NSTimer *)timer
{
	[_multiTapTimer invalidate];
	[_multiTapTimer release];
	_multiTapTimer = nil;
	if ( timer )
	{
//		NSLog(@"resetting multi-tap timer");
		[self sendAllPendingQueueEntriesNow];
	}
}


- (void)_resetTapModifierAndClick: (NSTimer *)timer
{
	[_tapAndClickTimer invalidate];
	[_tapAndClickTimer release];
	_tapAndClickTimer = nil;
//	[_view setCursorTo: @"rfbCursor"];
	if ( timer )
		[self sendAllPendingQueueEntriesNow];
}


- (void)_updateCapsLockStateIfNecessary
{
//	if ( _watchEventForCapsLock )
//	{
//		_watchEventForCapsLock = NO;
//		GSEventRefcurrentEvent = [NSApp currentEvent];
//		unsigned int modifierFlags = [currentEvent modifierFlags];
//		if ( (NSAlphaShiftKeyMask & modifierFlags) != (NSAlphaShiftKeyMask & _pressedModifiers) )
//			[self flagsChanged: currentEvent];
//	}
}


- (id)init
{
	if ( self = [super init] )
	{
		_pendingEvents = [[NSMutableArray alloc] init];
		_pressedKeys = [[NSMutableSet alloc] init];
		_emulationButton = 1;
//	    _mouseTimer = nil;
        _unsentMouseMoveExists = NO;
		_lastMousePoint.x = -1;
		_lastMousePoint.y = -1;
	}
	return self;
}


- (void)dealloc
{
	[self _resetMultiTapTimer: nil];
	[self _resetTapModifierAndClick: nil];
	[self sendAllPendingQueueEntriesNow];
	[self synthesizeRemainingEvents];
	[self sendAllPendingQueueEntriesNow];
	[_pendingEvents release];
	[_pressedKeys release];
	[super dealloc];
}

#pragma mark Talking to the server

- (RFBConnection *)connection
{
	return _connection;
}

- (void)setConnection: (RFBConnection *)connection
{
	_connection = connection;
	_viewOnly = [connection viewOnly];
	
	Profile *profile = [connection profile];
	if ( profile )
	{
		[self setButton2EmulationScenario: [profile button2EmulationScenario]];
		[self setButton3EmulationScenario: [profile button3EmulationScenario]];
	}
}

- (UIView *)view
{
	return _view;
}

- (void)setView: (UIView *)view
{
	_view = view;
}

- (CGAffineTransform) backToVNCTransform;
{
	return _matrixBackToVNCTransform;
}

- (void)setBackToVNCTransform: (CGAffineTransform)matrix
{
	_matrixBackToVNCTransform = matrix;
}

- (unsigned int)pressedButtons
{
	return _pressedButtons;
}

//- (void)setOrientation:(UIDeviceOrientation)wOrientation
//{
//	_orientation = wOrientation;
//}
//
//- (CGPoint)getVNCScreenPoint: (CGRect)r
//{
//	CGRect cr = [_view convertRect:r fromView:nil];
//	CGPoint pt = CGPointApplyAffineTransform(cr.origin, _matrixBackToVNCTransform);
//	switch (_orientation)
//	{
//		case UIDeviceOrientationPortrait:
//			pt.y = 0-pt.y;
//			break;
//		case UIDeviceOrientationPortraitUpsideDown:
//			pt.x = pt.x+[_connection displaySize].width;
//			pt.y = [_connection displaySize].height - pt.y;	
//			break;
//		case UIDeviceOrientationLandscapeRight:
//			pt.y = 0-pt.y;
//			pt.x = pt.x+[_connection displaySize].width;
//			break;
//		case UIDeviceOrientationLandscapeLeft:
//			pt.y = [_connection displaySize].height - pt.y;
//			break;
//	}
//	return pt;
//}

- (unsigned int)pressedModifiers
{
	return _pressedModifiers;
}

#pragma mark Local Mouse Events

//- (void)mouseDown: (GSEventRef)theEvent
//{
//	[self queueMouseDownEventFromEvent: theEvent buttonNumber: 1];
//}
//
//
//- (void)mouseUp: (GSEventRef)theEvent
//{
//	[self queueMouseUpEventFromEvent: theEvent buttonNumber: 1];
//}
//
//
//- (void)rightMouseDown: (GSEventRef)theEvent
//{
//	[self queueMouseDownEventFromEvent: theEvent buttonNumber: 3];
//}
//
//
//- (void)rightMouseUp: (GSEventRef)theEvent
//{
//	[self queueMouseUpEventFromEvent: theEvent buttonNumber: 3];
//}
//
//
//- (void)otherMouseDown: (GSEventRef)theEvent
//{
////	if ( 2 == [theEvent buttonNumber] )
////		[self queueMouseDownEventFromEvent: theEvent buttonNumber: 2];
//}
//
//
//- (void)otherMouseUp: (GSEventRef)theEvent
//{
////	if ( 2 == [theEvent buttonNumber] )
////		[self queueMouseUpEventFromEvent: theEvent buttonNumber: 2];
//}
//
//
//- (void)scrollWheel: (GSEventRef)theEvent
//{
////	if ( _viewOnly )
////		return;
////
////	[self sendAllPendingQueueEntriesNow];
////	int addMask;
////    CGPoint	p = [_view convertPoint: [[_view window] convertScreenToBase: [GSEventRefmouseLocation]] 
////						  fromView: nil];
////    if ( [theEvent deltaY] > 0.0 )
////		addMask = rfbButton4Mask;
////	else
////		addMask = rfbButton5Mask;
////    [self clearUnpublishedMouseMove];
////    [_connection mouseAt: p buttons: _pressedButtons | addMask];	// 'Mouse button down'
////    [_connection mouseAt: p buttons: _pressedButtons];			// 'Mouse button up'
//}

//- (void)mouseMoved:(GSEventRef)theEvent
//{
//	if ( _viewOnly )
//		return;
//	
//	if( nil != _mouseTimer )
//    {
//        [_mouseTimer invalidate];
//		[_mouseTimer release];
//        _mouseTimer = nil;
//    }
//
//	CGRect r = GSEventGetLocationInWindow(theEvent);
//    CGPoint	currentPoint = [self getVNCScreenPoint: r];
//	
//	static int ct = IGNORE_COUNT;
//    bool bSendEventImmediately = NO;
//	
//	float dx = ABS(_lastSentMousePoint.x - currentPoint.x);
//	float dy = ABS(_lastSentMousePoint.y - currentPoint.y);
//	bool overDiff = (dx >= CHANGE_DIFF || dy >= CHANGE_DIFF);
//	
//	if( IGNORE_COUNT == ct || overDiff )
//	{
//		bSendEventImmediately = YES;
//		
//		ct = 0;
//	}
//	else
//	{
//		++ct;
//	}
//    
//    _unsentMouseMoveExists = YES;
//    _lastMousePoint = currentPoint;
//    
//    if( YES == bSendEventImmediately )
//    {
////        NSLog( @"Forced Mouse Move." );
//        [self sendUnpublishedMouseMove];
//    }
//    else
//    {
////        NSLog( @"Ignored Mouse Move." );
//        _mouseTimer = [NSTimer scheduledTimerWithTimeInterval: 0.05
//                                                       target: self
//                                                     selector: @selector(handleMouseTimer:)
//                                                     userInfo: nil
//                                                      repeats: NO];
//		[_mouseTimer retain];
//    }
//}
//
//- (void)handleMouseTimer: (NSTimer *) timer
//{
//	[_mouseTimer release];
//    _mouseTimer = nil;
//    
//    [self sendUnpublishedMouseMove];
//    
////    NSLog( @"Sent Mouse Move." );
//}
//
//- (void)clearUnpublishedMouseMove
//{
//	_unsentMouseMoveExists = NO;
//}
//
//- (void)sendUnpublishedMouseMove
//{
//    if( YES == _unsentMouseMoveExists )
//    {
//        [self clearUnpublishedMouseMove];
//        [_connection mouseAt: _lastMousePoint buttons: _pressedButtons];
//		_lastSentMousePoint = _lastMousePoint;
//    }
//}
//
//- (void)mouseDragged:(GSEventRef)theEvent
//{
//	[self mouseMoved:theEvent];
//}
//
//- (void)rightMouseDragged:(GSEventRef)theEvent
//{
//	[self mouseMoved:theEvent];
//}
//
//- (void)otherMouseDragged:(GSEventRef)theEvent
//{
//	[self mouseMoved:theEvent];
//}

#pragma mark Local Keyboard Events

- (void)flagsChanged:(unsigned int)newState
{
//	unsigned int newState = [theEvent modifierFlags];
    newState = ~(~newState | 0xFFFF);
	unsigned int changedState = newState ^ _queuedModifiers;
	NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
	_queuedModifiers = newState;
	
	if ( NSShiftKeyMask & changedState )
	{
		if ( NSShiftKeyMask & newState )
		{
			[self queueModifierPressed: NSShiftKeyMask timestamp: timestamp];
		}
		else
		{
			[self queueModifierReleased: NSShiftKeyMask timestamp: timestamp];
		}
	}
	if ( NSControlKeyMask & changedState )
	{
		if ( NSControlKeyMask & newState )
		{
			[self queueModifierPressed: NSControlKeyMask timestamp: timestamp];
		}
		else
		{
			[self queueModifierReleased: NSControlKeyMask timestamp: timestamp];
		}
	}
	if ( NSAlternateKeyMask & changedState )
	{
		if ( NSAlternateKeyMask & newState )
		{
			[self queueModifierPressed: NSAlternateKeyMask timestamp: timestamp];
		}
		else
		{
			[self queueModifierReleased: NSAlternateKeyMask timestamp: timestamp];
		}
	}
	if ( NSCommandKeyMask & changedState )
	{
		if ( NSCommandKeyMask & newState )
		{
			[self queueModifierPressed: NSCommandKeyMask timestamp: timestamp];
		}
		else
		{
			[self queueModifierReleased: NSCommandKeyMask timestamp: timestamp];
		}
	}
	if ( NSAlphaShiftKeyMask & changedState )
	{
		if ( NSAlphaShiftKeyMask & newState )
		{
			[self queueModifierPressed: NSAlphaShiftKeyMask timestamp: timestamp];
		}
		else
		{
			[self queueModifierReleased: NSAlphaShiftKeyMask timestamp: timestamp];
		}
	}
	if ( NSNumericPadKeyMask & changedState )
	{
		if ( NSNumericPadKeyMask & newState )
		{
			[self queueModifierPressed: NSNumericPadKeyMask timestamp: timestamp];
		}
		else
		{
			[self queueModifierReleased: NSNumericPadKeyMask timestamp: timestamp];
		}
	}
	if ( NSHelpKeyMask & changedState )
	{
		if ( NSHelpKeyMask & newState )
		{
			[self queueModifierPressed: NSHelpKeyMask timestamp: timestamp];
		}
		else
		{
			[self queueModifierReleased: NSHelpKeyMask timestamp: timestamp];
		}
	}
}

//- (void)keyTyped:(NSString *)characters
//{
//	unsigned int i;
//	unsigned int length = [characters length];
//	NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
//	
//	for (i = 0; i < length; ++i)
//	{
//		unichar character = [characters characterAtIndex: i];
//		unichar characterIgnoringModifiers = character;
//		unsigned int modifiers = 0;
//		
////		NSLog(@"char=0x%04x", character);
//		
//		// Perform any character conversions necessary to map from the UIKit
//		// keyboard characters to what the RFB protocol and servers expect.
//		if (character == '\n')
//		{
//			// Need to convert the return character.
//			character = '\r';
//			characterIgnoringModifiers = '\r';
//		}
//		else if (iswupper(character))
//		{
//			// Handle upper case alphabetical characters.
//			modifiers |= NSShiftKeyMask;
//			characterIgnoringModifiers = towlower(character);
//		}
//		else
//		{
//			// See if we need to apply modifier keys.
//			unsigned int j;
//			for (j = 0; kKeyModifierMap[j].character != 0; ++j)
//			{
//				if (kKeyModifierMap[j].character == character)
//				{
//					modifiers |= kKeyModifierMap[j].modifiers;
//					characterIgnoringModifiers = kKeyModifierMap[j].unmodifiedCharacter;
//					break;
//				}
//			}
//		}
//		
//		// Press any modifiers.
//		if (modifiers & NSShiftKeyMask)
//		{
//			[self queueModifierPressed:NSShiftKeyMask timestamp:timestamp];
//		}
//		
//		if (modifiers & NSAlternateKeyMask)
//		{
//			[self queueModifierPressed:NSAlternateKeyMask timestamp:timestamp + 0.001];
//		}
//		
//		// Send key down and up for the main character.
//		[_pendingEvents addObject:[QueuedEvent keyDownEventWithCharacter:character characterIgnoringModifiers:characterIgnoringModifiers timestamp:timestamp + 0.002]];
//		
//		[_pendingEvents addObject:[QueuedEvent keyUpEventWithCharacter:character characterIgnoringModifiers:characterIgnoringModifiers timestamp:timestamp + 0.003]];
//		
//		// Release any modifiers.
//		//! @todo Don't release modifiers that are manually turned on.
//		if (modifiers & NSAlternateKeyMask)
//		{
//			[self queueModifierReleased:NSAlternateKeyMask timestamp:timestamp + 0.004];
//		}
//		
//		if (modifiers & NSShiftKeyMask)
//		{
//			[self queueModifierReleased:NSShiftKeyMask timestamp:timestamp + 0.005];
//		}
//		
//		[self sendAnyValidEventsToServerNow];
//	}
//}

#pragma mark Synthesized Events

- (void)clearAllEmulationStates
{
	[self sendAllPendingQueueEntriesNow];
	_emulationButton = 1;
	_clickWhileHoldingModifierStillDown[0] = NO;
	_clickWhileHoldingModifierStillDown[1] = NO;
	[self _resetMultiTapTimer: nil];
	[self _resetTapModifierAndClick: nil];
}


- (void)_queueEmulatedMouseDownForButton: (unsigned int) button basedOnEvent: (QueuedEvent *)event
{
	_emulationButton = button;
	QueuedEvent *mousedown = [QueuedEvent mouseDownEventForButton: _emulationButton
														 location: [event locationInWindow]
														timestamp: [event timestamp]];
	[_pendingEvents addObject: mousedown];
}

//- (void)queueMouseDownEventFromEvent: (GSEventRef)theEvent buttonNumber: (unsigned int)button
//{
////	NSLog(@"queueMouseDownEventFromEvent:%@ n:%d", theEvent, button);
//	if ( 1 != _emulationButton )
//	{
//		[self queueMouseUpEventFromEvent: theEvent buttonNumber: _emulationButton];
//	}
//	
//	CGRect r = GSEventGetLocationInWindow(theEvent);
////	NSLog(@"r.o={%f,%f}", r.origin.x, r.origin.y);
//
//	// The convertPoint:fromView: call crashes. Probably a compiler issue.
//	// So instead we use convertRect:fromView:.
//    CGPoint	p = [self getVNCScreenPoint: r];
////	NSLog(@"down:p={%f,%f}", p.x, p.y);
//
//	// Put some hysteresis on the mouse location.
//	float deltaX = ABS(p.x - _lastSentMousePoint.x);
//	float deltaY = ABS(p.y - _lastSentMousePoint.y);
//	
//	if (deltaX < kMouseHysteresisPixels && deltaY < kMouseHysteresisPixels)
//	{
//		p = _lastSentMousePoint;
////		NSLog(@"down:using p={%f,%f}", p.x, p.y);
//	}
//	else
//	{
//		_lastSentMousePoint = p;
//	}
//		
//	QueuedEvent *event = [QueuedEvent mouseDownEventForButton: button location: p timestamp: GSEventGetTimestamp(theEvent)];
//	
////	NSLog(@"q'd event=%@", event);
//	[_pendingEvents addObject: event];
//	[self sendAnyValidEventsToServerNow];
//}
//
//- (void)queueMouseUpEventFromEvent: (GSEventRef)theEvent buttonNumber: (unsigned int)button
//{
////	NSLog(@"queueMouseUpEventFromEvent:%@ n:%d", theEvent, button);
//	if ( 1 != _emulationButton )
//	{
//		button = _emulationButton;
//		_emulationButton = 1;
//	}
//	
//	CGRect r = GSEventGetLocationInWindow(theEvent);
//    CGPoint	p  = [self getVNCScreenPoint: r];
////	NSLog(@"up:p={%f,%f}", p.x, p.y);
//	
//	// If the location for this mouse up event is not over a certain
//	// distance away, send the last location instead. This should help
//	// double clicking work, since even a quick tap of the finger can
//	// have a distance between the down and up location larger than what
//	// most remote computers accept as a maximum double click delta.
//	float deltaX = ABS(p.x - _lastSentMousePoint.x);
//	float deltaY = ABS(p.y - _lastSentMousePoint.y);
//	
//	if (deltaX < kMouseHysteresisPixels && deltaY < kMouseHysteresisPixels)
//	{
//		p = _lastSentMousePoint;
////		NSLog(@"up:using p={%f,%f}", p.x, p.y);
//	}
//	else
//	{
//		_lastSentMousePoint = p;
//	}
//	
//	QueuedEvent *event = [QueuedEvent mouseUpEventForButton:button location:p timestamp:GSEventGetTimestamp(theEvent)];
//	
////	NSLog(@"q'd event=%@", event);
//	[_pendingEvents addObject: event];
//	[self sendAnyValidEventsToServerNow];
//}

- (void)queueModifierPressed: (unsigned int)modifier timestamp: (NSTimeInterval)timestamp
{
	QueuedEvent *event = [QueuedEvent modifierDownEventWithCharacter: modifier
													  timestamp: timestamp];
	[_pendingEvents addObject: event];
	[self sendAnyValidEventsToServerNow];
}


- (void)queueModifierReleased: (unsigned int)modifier timestamp: (NSTimeInterval)timestamp
{
	if ( kClickWhileHoldingModifierEmulation == _buttonEmulationScenario[0] 
		 && _clickWhileHoldingModifierStillDown[0] 
		 && modifier == _clickWhileHoldingModifier[0] )
	{
		_clickWhileHoldingModifierStillDown[0] = NO;
	}
	if ( kClickWhileHoldingModifierEmulation == _buttonEmulationScenario[1] 
		 && _clickWhileHoldingModifierStillDown[1] 
		 && modifier == _clickWhileHoldingModifier[1] )
	{
		_clickWhileHoldingModifierStillDown[1] = NO;
	}
	
	QueuedEvent *event = [QueuedEvent modifierUpEventWithCharacter: modifier
													timestamp: timestamp];
	[_pendingEvents addObject: event];
	[self sendAnyValidEventsToServerNow];
}


- (void)pasteString: (NSString *)string
{
	[self _updateCapsLockStateIfNecessary];
	int index, strLength = [string length];
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	
	[self clearAllEmulationStates];
	BOOL capsLockWasPressed = (_pressedModifiers & NSAlphaShiftKeyMask) ? YES : NO;
	
	for ( index = 0; index < strLength; ++index )
	{
		unichar character = [string characterAtIndex: index];
		
		// hack - lets' be polite to the server
		if ( '\n' == character )
			character = '\r';
		
		QueuedEvent *event = [QueuedEvent keyDownEventWithCharacter: character
										 characterIgnoringModifiers: character
														  timestamp: now];
		[_pendingEvents addObject: event];
		event = [QueuedEvent keyUpEventWithCharacter: character
						  characterIgnoringModifiers: character
										   timestamp: now];
		[_pendingEvents addObject: event];
	}
	
	[self sendAllPendingQueueEntriesNow];
	if ( capsLockWasPressed )
		_pressedModifiers |= NSAlphaShiftKeyMask;
}

#pragma mark Event Processing

- (unsigned int)_sendAnyValidEventsToServerForButton: (unsigned int)button 
									scenario: (EventFilterEmulationScenario)scenario
{
	unsigned int eventsToDelay = 0;
	switch (scenario)
	{
		case kNoMouseButtonEmulation:
			break;
		case kClickWhileHoldingModifierEmulation:
			eventsToDelay = [self handleClickWhileHoldingForButton: button];
			break;
		case kMultiTapModifierEmulation:
			eventsToDelay = [self handleMultiTapForButton: button];
			break;
		case kTapModifierAndClickEmulation:
			eventsToDelay = [self handleTapModifierAndClickForButton: button];
			break;
		default:
			[NSException raise: NSInternalInconsistencyException format: @"unsupported emulation scenario %d for button %d", (int)scenario, button];
	}
	return eventsToDelay;
}

- (void)sendAnyValidEventsToServerNow
{
	unsigned int eventsToDelay2;
	unsigned int eventsToDelay3;
	
	eventsToDelay2 = [self _sendAnyValidEventsToServerForButton: 2 scenario: _buttonEmulationScenario[0]];
	eventsToDelay3 = [self _sendAnyValidEventsToServerForButton: 3 scenario: _buttonEmulationScenario[1]];
	
	unsigned int eventsToDelay = eventsToDelay3 > eventsToDelay2 ? eventsToDelay3 : eventsToDelay2;
	if ( eventsToDelay )
	{
		unsigned int pendingEvents = [_pendingEvents count];
		if ( eventsToDelay < pendingEvents )
		{
			NSRange range = NSMakeRange( 0, pendingEvents - eventsToDelay );
			[self sendPendingQueueEntriesInRange: range];
		}
	}
	else
	{
		[self sendAllPendingQueueEntriesNow];
	}
}

- (void)_sendMouseEvent: (QueuedEvent *)event
{
	unsigned int oldPressedButtons = _pressedButtons;
	
	switch ([event type])
	{
		case kQueuedMouse1DownEvent:
			_pressedButtons |= rfbButton1Mask;
			break;
		case kQueuedMouse1UpEvent:
			if ( _pressedButtons & rfbButton1Mask )
				_pressedButtons &= ~rfbButton1Mask;
			break;
		case kQueuedMouse2DownEvent:
			_pressedButtons |= rfbButton2Mask;
			break;
		case kQueuedMouse2UpEvent:
			if ( _pressedButtons & rfbButton2Mask )
				_pressedButtons &= ~rfbButton2Mask;
			break;
		case kQueuedMouse3DownEvent:
			_pressedButtons |= rfbButton3Mask;
			break;
		case kQueuedMouse3UpEvent:
			if ( _pressedButtons & rfbButton3Mask )
				_pressedButtons &= ~rfbButton3Mask;
			break;
		default:
			[NSException raise: NSInternalInconsistencyException format: @"unsupported event type"];
	}
	
	if ( _pressedButtons != oldPressedButtons )
    {
        [self clearUnpublishedMouseMove];
		[_connection mouseAt: [event locationInWindow] buttons: _pressedButtons];
    }
}

- (void)_sendKeyEvent: (QueuedEvent *)event
{
	unichar character = [event character];
	unichar characterIgnoringModifiers = [event characterIgnoringModifiers];
	NSNumber * encodedChar = [NSNumber numberWithInt: (int)characterIgnoringModifiers];
	unichar sendKey;
	
	// turns out that servers seem to ignore any keycodes over 128.  so no point in 
	// sending 'em.  Also, turns out that RealVNC doesn't track the status of the capslock
	// key.  So, I'll repurpose 'character' here to be the shifted character, if needed.
	// 
	// I'll maintain state of the unmodified character because, for example, if you set 
	// caps lock and then keyrepeat something and unset caps lock while you're doing it, 
	// the key up character will be for the lowercase letter.
	if ( NSAlphaShiftKeyMask & _pressedModifiers )
	{
		character = toupper(characterIgnoringModifiers);
	}
	else if ((_pressedModifiers & NSShiftKeyMask) == 0)
	{
		// If the shift key is not pressed, send unmodified character. Otherwise,
		// send the modifiers (shifted) character, because shift is supposed to only
		// be a hint to the server.
		character = characterIgnoringModifiers;
	}
	
	sendKey = character;
	
	if ( kQueuedKeyDownEvent == [event type] )
	{
        [self sendUnpublishedMouseMove];
		[_pressedKeys addObject: encodedChar];
		[_connection sendKey: sendKey pressed: YES];
	}
	else if ( [_pressedKeys containsObject: encodedChar] )
	{
        [self sendUnpublishedMouseMove];
		[_pressedKeys removeObject: encodedChar];
		[_connection sendKey: sendKey pressed: NO];
	}
}

- (void)_sendModifierEvent: (QueuedEvent *)event
{
	unsigned int modifier = [event modifier];
	
	if ( kQueuedModifierDownEvent == [event type] )
	{
        [self sendUnpublishedMouseMove];
		_pressedModifiers |= modifier;
		[_connection sendModifier: modifier pressed: YES];
	}
	else if ( _pressedModifiers & modifier )
	{
        [self sendUnpublishedMouseMove];
		_pressedModifiers &= ~modifier;
		[_connection sendModifier: modifier pressed: NO];
	}
}

- (void)_sendEvent: (QueuedEvent *)event
{
	if ( _viewOnly )
	{
		return;
	}
	
	QueuedEventType eventType = [event type];
	
	if ( eventType <= kQueuedMouse3UpEvent )
	{
		[self _sendMouseEvent: event];
	}
	else if ( eventType <= kQueuedKeyUpEvent )
	{
		[self _sendKeyEvent: event];
	}
	else
	{
		[self _sendModifierEvent: event];
	}
}

- (void)sendAllPendingQueueEntriesNow
{
	NSEnumerator *eventEnumerator = [_pendingEvents objectEnumerator];
	QueuedEvent *event;
	
	while ( event = [eventEnumerator nextObject] )
	{
		[self _sendEvent: event]; // this sets stuff like _pressedKeyes, _pressedButtons, etc.
	}
	
	[self discardAllPendingQueueEntries];
}

- (void)sendPendingQueueEntriesInRange: (NSRange)range
{
	unsigned int i, last = NSMaxRange(range);
	
	for ( i = range.location; i < last; ++i )
	{
		QueuedEvent *event = [_pendingEvents objectAtIndex: i];
		[self _sendEvent: event];
	}
	[_pendingEvents removeObjectsInRange: range];
}

- (void)discardAllPendingQueueEntries
{
	[_pendingEvents removeAllObjects];
}

- (void)_synthesizeRemainingMouseUpEvents
{
	CGPoint p = {0,0};
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	
	if ( rfbButton1Mask && _pressedButtons )
	{
		QueuedEvent *event = [QueuedEvent mouseUpEventForButton: 1
													   location: p
													  timestamp: now];
		[_pendingEvents addObject: event];
	}
	if ( rfbButton2Mask && _pressedButtons )
	{
		QueuedEvent *event = [QueuedEvent mouseUpEventForButton: 2
													   location: p
													  timestamp: now];
		[_pendingEvents addObject: event];
	}
	if ( rfbButton3Mask && _pressedButtons )
	{
		QueuedEvent *event = [QueuedEvent mouseUpEventForButton: 3
													   location: p
													  timestamp: now];
		[_pendingEvents addObject: event];
	}
	if ( rfbButton4Mask && _pressedButtons )
	{
		QueuedEvent *event = [QueuedEvent mouseUpEventForButton: 4
													   location: p
													  timestamp: now];
		[_pendingEvents addObject: event];
	}
	if ( rfbButton5Mask && _pressedButtons )
	{
		QueuedEvent *event = [QueuedEvent mouseUpEventForButton: 5
													   location: p
													  timestamp: now];
		[_pendingEvents addObject: event];
	}
}

- (void)_synthesizeRemainingKeyUpEvents
{
	NSEnumerator *keyEnumerator = [_pressedKeys objectEnumerator];
	NSNumber *encodedKey;
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	
	while ( encodedKey = [keyEnumerator nextObject] )
	{
		unichar character = (unichar) [encodedKey intValue];
		QueuedEvent *event = [QueuedEvent keyUpEventWithCharacter: character
									   characterIgnoringModifiers: character
														timestamp: now];
		[_pendingEvents addObject: event];
	}
}

- (void)_synthesizeRemainingModifierUpEvents
{
	NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
	
	if ( NSShiftKeyMask && _pressedModifiers )
	{
		QueuedEvent *event = [QueuedEvent modifierUpEventWithCharacter: NSShiftKeyMask
															 timestamp: now];
		[_pendingEvents addObject: event];
	}
	if ( NSControlKeyMask && _pressedModifiers )
	{
		QueuedEvent *event = [QueuedEvent modifierUpEventWithCharacter: NSControlKeyMask
															 timestamp: now];
		[_pendingEvents addObject: event];
	}
	if ( NSAlternateKeyMask && _pressedModifiers )
	{
		QueuedEvent *event = [QueuedEvent modifierUpEventWithCharacter: NSAlternateKeyMask
															 timestamp: now];
		[_pendingEvents addObject: event];
	}
	if ( NSCommandKeyMask && _pressedModifiers )
	{
		QueuedEvent *event = [QueuedEvent modifierUpEventWithCharacter: NSCommandKeyMask
															 timestamp: now];
		[_pendingEvents addObject: event];
	}
}

- (void)synthesizeRemainingEvents
{
	[self _synthesizeRemainingMouseUpEvents];
	[self _synthesizeRemainingKeyUpEvents];
	[self _synthesizeRemainingModifierUpEvents];
}

- (unsigned int)handleClickWhileHoldingForButton: (unsigned int)button
{
	int eventCount = [_pendingEvents count];
	if ( eventCount > 2 )
		return 0;
	
	unsigned int buttonIndex = ButtonNumberToArrayIndex( button );
	
	if ( eventCount == 2 )
	{
		QueuedEvent *event1 = [_pendingEvents objectAtIndex: 0];
		
		if ( kQueuedModifierDownEvent == [event1 type] 
			 && _clickWhileHoldingModifier[buttonIndex] == [event1 modifier] )
		{
			QueuedEvent *event2 = [_pendingEvents objectAtIndex: 1];
			
			if ( kQueuedMouse1DownEvent == [event2 type] )
			{
				[[event2 retain] autorelease];
				[self discardAllPendingQueueEntries];
				[self _queueEmulatedMouseDownForButton: button basedOnEvent: event2];
				_clickWhileHoldingModifierStillDown[buttonIndex] = YES;
				return 0;
			}
		}
	}
	
	if ( eventCount == 1 )
	{
		QueuedEvent *event = [_pendingEvents objectAtIndex: 0];

		if ( kQueuedModifierDownEvent == [event type] 
			 && _clickWhileHoldingModifier[buttonIndex] == [event modifier] )
		{
			return 1;
		}
		else if ( YES == _clickWhileHoldingModifierStillDown[buttonIndex] 
				  && kQueuedMouse1DownEvent == [event type] )
		{
			[[event retain] autorelease];
			[self discardAllPendingQueueEntries];
			[self _queueEmulatedMouseDownForButton: button basedOnEvent: event];
			return 0;
		}
	}
	
	return 0;
}

- (unsigned int)handleMultiTapForButton: (unsigned int)button
{
	unsigned int buttonIndex = ButtonNumberToArrayIndex( button );
	NSEnumerator *eventEnumerator = [_pendingEvents objectEnumerator];
	QueuedEvent *event;
	unsigned int validEvents = 0;
	
	[self _resetMultiTapTimer: nil];

	while ( event = [eventEnumerator nextObject] )
	{
		QueuedEventType eventType = [event type];
		unsigned int modifier = [event modifier];
		
		if ( _multipTapModifier[buttonIndex] != modifier )
			return 0;
		
		if ( 0 == validEvents % 2 )
		{
			if ( kQueuedModifierDownEvent != eventType )
				return 0;
			validEvents++;
		}
		else
		{
			if ( kQueuedModifierUpEvent != eventType )
				return 0;
			validEvents++;
			
			// XXX review this again
//			if ( validEvents / 2 == _multipTapCount[buttonIndex] )
//			{
//				[self discardAllPendingQueueEntries];
//				CGPoint	p = [_view convertPoint: [[_view window] convertScreenToBase: [GSEventRefmouseLocation]] 
//									  fromView: nil];
//				unsigned int rfbButton = ButtonNumberToRFBButtomMask( button );
//                [self clearUnpublishedMouseMove];
//				[_connection mouseAt: p buttons: _pressedButtons | rfbButton];	// 'Mouse button down'
//				[_connection mouseAt: p buttons: _pressedButtons];				// 'Mouse button up'
//				return 0;
//			}
		}
	}
	
	if ( validEvents && (validEvents % 2 == 0) )
	{
		_multiTapTimer = [[NSTimer scheduledTimerWithTimeInterval: _multipTapDelay[buttonIndex] target: self selector: @selector(_resetMultiTapTimer:) userInfo: nil repeats: NO] retain];
//		NSLog(@"starting multi-tap timer");
	}
	
	return validEvents;
}

- (unsigned int)handleTapModifierAndClickForButton: (unsigned int)button
{
	unsigned int buttonIndex = ButtonNumberToArrayIndex( button );
	int eventIndex, eventCount = [_pendingEvents count];
	NSTimeInterval time1 = 0, time2;
	
	for ( eventIndex = 0; eventIndex < eventCount; ++eventIndex )
	{
		QueuedEvent *event = [_pendingEvents objectAtIndex: eventIndex];
		QueuedEventType eventType = [event type];
		unsigned int modifier = [event modifier];
		
		if ( 0 == eventIndex )
		{
			if ( ! (kQueuedModifierDownEvent == eventType && modifier == _tapAndClickModifier[buttonIndex]) )
				return 0;
			time1 = [event timestamp];
		}
		
		else if ( 1 == eventIndex )
		{
			if ( ! (kQueuedModifierUpEvent == eventType && modifier == _tapAndClickModifier[buttonIndex]) )
				return 0;
			time2 = [event timestamp];
			if ( time2 - time1 > _tapAndClickButtonSpeed[buttonIndex] )
				return 0;

			if ( ! _tapAndClickTimer )
			{
				_tapAndClickTimer = [[NSTimer scheduledTimerWithTimeInterval: _tapAndClickTimeout[buttonIndex] target: self selector: @selector(_resetTapModifierAndClick:) userInfo: nil repeats: NO] retain];
//				[_view setCursorTo: (button == 2) ? @"rfbCursor2" : @"rfbCursor3"];
			}
		}
		
		else if ( 2 == eventIndex )
		{
			if ( kQueuedKeyDownEvent == eventType && '\e' == [event character] )
			{
				[self discardAllPendingQueueEntries];
				[self _resetTapModifierAndClick: nil];
				return 0;
			}
			
			if ( kQueuedMouse1DownEvent != eventType )
			{
				[self _resetTapModifierAndClick: nil];
				return 0;
			}
			
			[[event retain] autorelease];
			[self discardAllPendingQueueEntries];
			[self _queueEmulatedMouseDownForButton: button basedOnEvent: event];
			[self _resetTapModifierAndClick: nil];
			return 0;
		}
	}

	return eventCount;
}

#pragma mark Configuration

- (void)_updateConfigurationForButton: (unsigned int)button
{
	unsigned int buttonIndex = ButtonNumberToArrayIndex( button );
	Profile *profile = [_connection profile];
	
	switch (_buttonEmulationScenario[buttonIndex])
	{
		case kNoMouseButtonEmulation:
			break;
		case kClickWhileHoldingModifierEmulation:
			[self setClickWhileHoldingModifier: [profile clickWhileHoldingModifierForButton: button] button: button];
			break;
		case kMultiTapModifierEmulation:
			[self setMultiTapModifier: [profile multiTapModifierForButton: button] button: button];
			[self setMultiTapDelay: [profile multiTapDelayForButton: button] button: button];
			[self setMultiTapCount: [profile multiTapCountForButton: button] button: button];
			break;
		case kTapModifierAndClickEmulation:
			[self setTapAndClickModifier: [profile tapAndClickModifierForButton: button] button: button];
			[self setTapAndClickButtonSpeed: [profile tapAndClickButtonSpeedForButton: button] button: button];
			[self setTapAndClickTimeout: [profile tapAndClickTimeoutForButton: button] button: button];
			break;
		default:
			[NSException raise: NSInternalInconsistencyException format: @"unsupported emulation scenario for button %d", button];
	}
}


- (void)setButton2EmulationScenario: (EventFilterEmulationScenario)scenario
{
	_buttonEmulationScenario[0] = scenario;
	if ( _viewOnly )
		_buttonEmulationScenario[0] = kNoMouseButtonEmulation;
	[self _updateConfigurationForButton: 2];
}


- (void)setButton3EmulationScenario: (EventFilterEmulationScenario)scenario
{
	_buttonEmulationScenario[1] = scenario;
	if ( _viewOnly )
		_buttonEmulationScenario[1] = kNoMouseButtonEmulation;
	[self _updateConfigurationForButton: 3];
}


- (void)setClickWhileHoldingModifier: (unsigned int)modifier button: (unsigned int)button
{
	unsigned int buttonIndex = ButtonNumberToArrayIndex( button );
	_clickWhileHoldingModifier[buttonIndex] = modifier;
}


- (void)setMultiTapModifier: (unsigned int)modifier button: (unsigned int)button
{
	unsigned int buttonIndex = ButtonNumberToArrayIndex( button );
	_multipTapModifier[buttonIndex] = modifier;
}


- (void)setMultiTapDelay: (NSTimeInterval)delay button: (unsigned int)button
{
	unsigned int buttonIndex = ButtonNumberToArrayIndex( button );
	_multipTapDelay[buttonIndex] = delay;
}


- (void)setMultiTapCount: (unsigned int)count button: (unsigned int)button
{
	unsigned int buttonIndex = ButtonNumberToArrayIndex( button );
	_multipTapCount[buttonIndex] = count;
}


- (void)setTapAndClickModifier: (unsigned int)modifier button: (unsigned int)button
{
	unsigned int buttonIndex = ButtonNumberToArrayIndex( button );
	_tapAndClickModifier[buttonIndex] = modifier;
}


- (void)setTapAndClickButtonSpeed: (NSTimeInterval)speed button: (unsigned int)button
{
	unsigned int buttonIndex = ButtonNumberToArrayIndex( button );
	_tapAndClickButtonSpeed[buttonIndex] = speed;
}


- (void)setTapAndClickTimeout: (NSTimeInterval)timeout button: (unsigned int)button
{
	unsigned int buttonIndex = ButtonNumberToArrayIndex( button );
	_tapAndClickTimeout[buttonIndex] = timeout;
}

@end
