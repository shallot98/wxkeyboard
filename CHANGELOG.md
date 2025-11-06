# Changelog

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
