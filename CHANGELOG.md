# Changelog

## Version 1.2.3

### Critical Fix
- **Fixed touchesEnded allowing IME to consume gesture**: Now blocks touchesEnded and touchesCancelled when vertical swipe is detected
- **Complete touch sequence hijacking**: When a vertical swipe is detected, we now prevent the original handler from processing ANY part of the touch sequence (began → moved → ended)

### Technical Changes
- touchesEnded: Now checks if verticalSwipeDetected and blocks %orig if true
- touchesCancelled: Now checks if verticalSwipeDetected and blocks %orig if true
- This prevents IME content handlers from completing their processing after we've detected a swipe

### Why This Matters
- Previous version (1.2.2) only blocked touchesMoved, but touchesEnded was still calling %orig
- IME handlers complete their processing in touchesEnded, which was consuming the gesture
- Now we completely take over the touch sequence when a vertical swipe is detected
- Normal taps still work (original handler is called when no swipe detected)

## Version 1.2.2

### Critical Fix
- **Fixed gesture blocked by original touch handler**: Modified touchesMoved hooks to conditionally block original handler when vertical swipe is detected
- **Prevents IME interference**: When direction is locked to vertical, original touch processing is suppressed to prevent IME or other handlers from consuming the gesture

### Technical Changes
- WTSProcessTouchMovedForView now returns BOOL indicating if original handler should be blocked
- Returns YES when vertical direction is locked or swipe is detected
- Returns NO for horizontal movement or when no swipe is in progress
- All touchesMoved hooks updated to check return value before calling %orig

### Why This Matters
- Some keyboard components (like IME content handlers) may consume touch events before gesture completion
- By blocking original handler during vertical swipe, we ensure the gesture is not interrupted
- Normal key taps and horizontal gestures still work normally (original handler is called)

## Version 1.2.1

### Critical Bug Fix
- **Fixed swipe gesture detection failure**: Removed touch event hooks from individual key views (WBKeyView, WXKBKeyView) which were preventing swipe detection
- **Root cause**: Individual key views are too small (~40x40pt) to capture full swipe gestures. When user swipes, touch moves outside key bounds and touchesMoved stops being called
- **Solution**: Only hook container views (WBMainInputView, WBKeyboardView, etc.) which are large enough to capture complete swipe gestures

### Improvements
- **Enhanced diagnostic logging**: Added view class names and bounds to all touch event logs for easier debugging
- **Improved view filtering**: Updated WTSShouldInstallOnView to explicitly exclude individual key views
- **Better log messages**: All touch logs now include view class name and operation context

### What Works Now
- ✓ Long-press functionality preserved (on all keys including bottom row)
- ✓ Vertical swipe detection restored (up/down swipe to switch input modes)
- ✓ Normal tap input unaffected
- ✓ Works across entire keyboard area

### Technical Details
- Container views (200x100pt+) capture full gesture paths
- Individual key views retain original touch handling for long-press gestures
- Touch events properly propagate via %orig calls
- No interference between swipe detection and key interactions

See DIAGNOSTIC_FIX_SUMMARY.md for detailed root cause analysis and implementation notes.

## Version 1.2.0

### Major Changes
- **Enhanced gesture recognition**: Replaced UISwipeGestureRecognizer with UIPanGestureRecognizer for better control and slow swipe support
- **Distance-based triggering**: Now uses configurable minimum vertical distance (default: 28pt) instead of velocity-based detection
- **Direction locking**: Implemented intelligent direction locking to prevent horizontal interference during vertical swipes
- **Debounce protection**: Added 250ms minimum interval between triggers to prevent rapid-fire switching
- **Comprehensive view coverage**: Extended hook coverage to multiple WeType view classes for full keyboard area support
- **Filza-compatible logging**: Moved log file to `/var/mobile/Library/Logs/wxkeyboard.log` for easy access via Filza

### New Configuration Options
- `MinTranslationY` (float): Minimum vertical distance for swipe detection (default: 28.0)
- `SuppressKeyTapOnSwipe` (bool): Cancel touch events when swipe is detected (default: true)
- `LogLevel` (string): Logging level - DEBUG, INFO, or ERROR (default: DEBUG)

### Improvements
- **Slow swipe support**: Now works reliably with slow, deliberate swipes
- **Recursive installation**: Automatically installs gesture recognizers on view hierarchy for comprehensive coverage
- **Intelligent view filtering**: Skips very small views to improve performance
- **Enhanced logging**: Added multi-level logging with detailed state transitions and debugging information
- **Better conflict resolution**: Improved gesture conflict handling with other system gestures

### Technical Details
- Pan gesture recognizer with state machine for precise control
- Configurable thresholds and timing for different user preferences
- Comprehensive WeType class coverage: WBMainInputView, WBKeyboardView, WXKBKeyboardView, etc.
- Enhanced error handling and fallback mechanisms
- Performance optimizations with smart view selection

### Bug Fixes
- Fixed issue where fast swipes were not recognized reliably
- Resolved conflicts with horizontal gestures and scrolling
- Improved reliability of mode switching across different iOS versions
- Fixed performance issues with excessive gesture recognizer installation

## Version 1.1.0

### Major Changes
- **High-priority gesture recognition**: Swipe gestures now have `cancelsTouchesInView = YES` to override WeType's built-in button actions
- **Toolbar exclusion**: Top toolbar area (top 20% or 44pt, whichever is larger) is now excluded from swipe recognition
- **Chinese-English only switching**: Swipe gestures now only toggle between Chinese and English input modes, ignoring symbol keyboards and other input modes
- **Enhanced logging**: Debug logging is now enabled in production builds for better issue diagnosis

### Improvements
- Added detailed touch location logging for debugging
- Added toolbar detection by both position and view class name hierarchy
- Added comprehensive mode detection with support for multiple Chinese/English identifiers
- Logs all available input modes when switching for easier troubleshooting

### Technical Details
- Up swipe: Switches from Chinese to English (if currently Chinese) or to Chinese (if not Chinese)
- Down swipe: Switches from English to Chinese (if currently English) or to English (if not English)
- Gesture recognizers now cancel touches to prevent underlying button actions from firing
- Toolbar views are excluded from swipe recognition to preserve original toolbar functionality

### Bug Fixes
- Fixed issue where swiping on symbol/number buttons would open their respective keyboards instead of switching Chinese/English
- Improved gesture priority to ensure swipe always overrides button tap actions outside toolbar area

## Version 1.0.0
- Initial release
- Basic vertical swipe to switch input modes
