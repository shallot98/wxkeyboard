# Changelog

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
