# WeType Vertical Swipe with Region-Specific Mapping

This tweak enables global vertical swipe gestures on the WeType keyboard to toggle between Chinese and English input modes, while optionally supporting region-specific swipe actions for numeric and symbol panels.

## Features

### Global Language Swipe

- Swipe up or down anywhere on the keyboard surface to switch between Chinese and English input modes
- Works alongside normal taps and long presses with per-gesture debouncing
- Automatically disables when VoiceOver is active to respect accessibility workflows

### Region-Specific Actions (optional)

1. **Middle 9-key area**: Swipe up/down toggles between Chinese and English input modes
2. **Bottom "switch to numbers" key**: Swipe up/down switches to the numeric keyboard
3. **Spacebar**: Swipe up/down switches to the symbol keyboard

### Configuration

The tweak supports the following preferences (stored in `com.yourcompany.wxkeyboard`):

- `Enabled` (bool): Master toggle for the entire tweak (default: true)
- `DebugLog` (bool): Enable debug logging (default: true)
- `GlobalSwipe` (bool): Allow swipe up/down anywhere on the keyboard surface to toggle Chinese/English modes (default: true)
- `SwipeThreshold` (float): Minimum vertical distance for swipe detection in points (default: 25.0)
- `RegionSwipe` (bool): Enable region-specific routing (numeric/symbol) when global swipe is disabled (default: true)
- `NineKeyEnabled` (bool): Enable region swipe in the 9-key area when `RegionSwipe` is true (default: true)
- `NumberKeyEnabled` (bool): Enable region swipe on the number switch key when `RegionSwipe` is true (default: true)
- `SpacebarEnabled` (bool): Enable region swipe on the spacebar when `RegionSwipe` is true (default: true)

### Example Preferences

See `preferences_example.plist` for a complete example configuration.

## Implementation Details

### Gesture Recognition

- Uses a single `UIPanGestureRecognizer` attached to the top-level keyboard container view
- Detects vertical movement using a configurable threshold while ensuring the vertical component dominates horizontal motion
- Coexists with taps and long-press gestures, and logs gesture begin/end decisions (with dx/dy and active mode) when debug logging is enabled
- Debounced to trigger at most once per gesture and automatically resets after cancellation or failure
- Skips recognition when VoiceOver is active to preserve accessibility workflows

### Region Detection

The region detection uses a multi-layered approach:

1. **Accessibility Properties**: Checks `accessibilityLabel` and `accessibilityIdentifier`
2. **Class Name Analysis**: Matches view class names against known patterns
3. **Geometric Heuristics**: Uses keyboard layout proportions as fallback

### Safety Features

- Only activates when WeType keyboard is active and visible
- Excludes emoji/clipboard/toolbar panels from triggering
- Preserves existing long-press functionality
- Comprehensive error handling and fallbacks

## Installation

1. Build the tweak using Theos
2. Install on a jailbroken device
3. Configure preferences using a preferences editor or directly in the plist

## Compatibility

- WeType Keyboard (com.tencent.wetype.keyboard)
- iOS 13+ (tested on iOS 16+)
- Rootless jailbreaks supported

## Debugging

Enable `DebugLog` to view detailed logs in `/var/mobile/Library/Preferences/wxkeyboard.log`. Logs include:

- Gesture attachment and detection
- Region identification
- Action triggering
- Error conditions

## Troubleshooting

### Swipe not working
- Check that `Enabled` and `GlobalSwipe` are true (or enable `RegionSwipe` with the relevant region toggles if you prefer region-specific actions)
- Verify the specific region is enabled (e.g., `SpacebarEnabled`) when relying on region routing
- Adjust `SwipeThreshold` if gestures are too sensitive or too strict
- Review debug logs for gesture begin/decision/end entries to understand why a swipe was ignored

### Wrong action triggered
- Disable `GlobalSwipe` if you need region-specific numeric/symbol actions to take precedence
- Verify region detection in debug logs
- Adjust region boundaries if needed (geometric heuristics)
- Check if accessibility labels are available for better accuracy

### Performance issues
- Disable `DebugLog` in production
- Increase `SwipeThreshold` to reduce false positives
- Disable unused regions

## Development

The implementation is structured for extensibility:

- `WTKeyboardRegion` enum for easy addition of new regions
- Modular action methods for each keyboard function
- Comprehensive API discovery for WeType-specific methods
- Fallback mechanisms for different WeType versions

## License

This project is provided as-is for educational and personal use.