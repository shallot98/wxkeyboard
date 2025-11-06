# WeType Vertical Swipe Mode Switching

This tweak implements full-keyboard vertical swipe gestures for the WeType keyboard, allowing users to cycle through input modes by swiping up or down anywhere on the keyboard.

## Features

### Full-Keyboard Vertical Swipe

1. **Swipe up anywhere**: Switch to previous input mode
2. **Swipe down anywhere**: Switch to next input mode
3. **WeType-specific integration**: Uses WeType's internal mode manager for proper mode ordering
4. **Circular navigation**: Wraps around from first to last mode and vice versa

### Configuration

The tweak supports the following preferences (stored in `com.yourcompany.wxkeyboard`):

- `Enabled` (bool): Master toggle for the entire tweak (default: true)
- `DebugLog` (bool): Enable debug logging (default: true)

### Example Preferences

See `preferences_example.plist` for a complete example configuration.

## Implementation Details

### Gesture Recognition

- Uses two `UISwipeGestureRecognizer` instances (up and down) attached to the top-level keyboard container view
- `cancelsTouchesInView = NO` to minimize interference with key taps
- Restricts to vertical direction only to avoid conflicts with horizontal gestures
- One trigger per swipe gesture

### WeType Integration

The implementation uses WeType-specific APIs for mode management:

1. **Mode Discovery**: Attempts to access WeType's `inputModeManager` for ordered mode list
2. **Fallback Methods**: Uses multiple selector names to find current and available modes
3. **Proper Switching**: Uses WeType's internal mode setting methods when available
4. **Standard Fallback**: Falls back to iOS standard `inputModes` if WeType APIs fail

### Safety Features

- Only activates when WeType keyboard is active and visible
- Ignores touches on system UI elements like panels and toolbars
- Prevents duplicate gesture recognizer installation
- Comprehensive error handling and logging

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
- Check that `Enabled` is true
- Ensure WeType keyboard is active and visible
- Check debug logs for gesture recognizer installation
- Verify that swipe gestures aren't being intercepted by other apps

### Mode switching not working
- Check debug logs for available modes detection
- Verify WeType APIs are accessible (may vary by iOS version)
- Ensure there are at least 2 input modes available
- Check for mode switching errors in debug logs

### Interference with typing
- The implementation uses `cancelsTouchesInView = NO` to minimize interference
- If issues persist, check debug logs for gesture conflicts
- Ensure swipe gestures are deliberate (not accidental while typing)

### Performance issues
- Disable `DebugLog` in production builds
- Check for excessive logging in debug mode

## Development

The implementation is structured for WeType-specific integration:

- `WTVerticalSwipeManager` handles gesture recognition and mode switching
- WeType API discovery with multiple fallback selectors
- Proper previous/next mode calculation with circular navigation
- Comprehensive logging for debugging mode switching issues
- Clean separation between gesture handling and mode management

## License

This project is provided as-is for educational and personal use.