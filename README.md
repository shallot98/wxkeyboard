# WeType Vertical Swipe with Region-Specific Mapping

This tweak implements region-specific vertical swipe actions for the WeType keyboard, allowing users to trigger different actions based on where they swipe on the keyboard.

## Features

### Region-Specific Actions

1. **Middle 9-key area**: Swipe up/down toggles between Chinese and English input modes
2. **Bottom "switch to numbers" key**: Swipe up/down switches to the numeric keyboard
3. **Spacebar**: Swipe up/down switches to the symbol keyboard

### Configuration

The tweak supports the following preferences (stored in `com.yourcompany.wxkeyboard`):

- `Enabled` (bool): Master toggle for the entire tweak (default: true)
- `DebugLog` (bool): Enable debug logging (default: true)
- `RegionSwipe` (bool): Enable region-specific swipe feature (default: true)
- `SwipeThreshold` (float): Minimum vertical distance for swipe detection in points (default: 25.0)
- `NineKeyEnabled` (bool): Enable swipe in the 9-key area (default: true)
- `NumberKeyEnabled` (bool): Enable swipe on the number switch key (default: true)
- `SpacebarEnabled` (bool): Enable swipe on the spacebar (default: true)

### Example Preferences

See `preferences_example.plist` for a complete example configuration.

## Implementation Details

### Gesture Recognition

- Uses a single `UIPanGestureRecognizer` attached to the top-level keyboard container view
- Configurable threshold for vertical movement detection
- Coexists with taps and long-press gestures
- Debounced to trigger at most once per gesture

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
- Check that `Enabled` and `RegionSwipe` are both true
- Verify the specific region is enabled (e.g., `SpacebarEnabled`)
- Increase `SwipeThreshold` if gestures are too sensitive
- Check debug logs for region detection issues

### Wrong action triggered
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