# WeType Vertical Swipe Mode Switching

This tweak implements full-keyboard vertical swipe gestures for the WeType keyboard, allowing users to cycle through input modes by swiping up or down anywhere on the keyboard with enhanced gesture recognition and comprehensive logging.

## Features

### Enhanced Full-Keyboard Vertical Swipe

1. **Swipe up anywhere**: Switch to previous input mode
2. **Swipe down anywhere**: Switch to next input mode
3. **Slow swipe support**: Works with both fast and slow swipes using distance-based detection
4. **Direction locking**: Prevents horizontal interference during vertical swipes
5. **Debounce protection**: Prevents rapid-fire triggering (250ms minimum interval)
6. **WeType-specific integration**: Uses WeType's internal mode manager for proper mode ordering
7. **Comprehensive coverage**: Installs on multiple WeType view classes for full keyboard area support
8. **Complete touch sequence hijacking** (v1.2.3): Blocks touchesMoved, touchesEnded, and touchesCancelled when vertical swipe is detected to prevent IME from consuming the gesture

### Configuration

The tweak supports the following preferences (stored in `com.yourcompany.wxkeyboard`):

- `Enabled` (bool): Master toggle for the entire tweak (default: true)
- `DebugLog` (bool): Enable debug logging (default: true)
- `MinTranslationY` (float): Minimum vertical distance for swipe detection (default: 28.0 points)
- `SuppressKeyTapOnSwipe` (bool): Cancel touch events when swipe is detected (default: true)
- `LogLevel` (string): Logging level - DEBUG, INFO, or ERROR (default: DEBUG)

### Example Preferences

See `preferences_example.plist` for a complete example configuration.

## Implementation Details

### Enhanced Gesture Recognition

- Uses `UIPanGestureRecognizer` for precise control and slow swipe support
- Distance-based triggering (default: 28 points minimum vertical movement)
- Direction locking to prevent horizontal interference during vertical swipes
- Debounce protection with 250ms minimum interval between triggers
- Configurable touch cancellation to prevent key tap interference
- Comprehensive view hierarchy coverage with recursive installation

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

Enable `DebugLog` to view detailed logs in `/var/mobile/Library/Logs/wxkeyboard.log` (Filza-compatible location). Logs include:

- Gesture attachment and detection with detailed state transitions
- View hierarchy installation and coverage analysis
- Distance calculations and direction locking status
- Mode switching attempts and results
- Configuration changes and preference updates
- Error conditions and troubleshooting information

Log levels can be controlled via `LogLevel` preference:
- `DEBUG`: Shows all detailed information
- `INFO`: Shows important events and errors
- `ERROR`: Shows only error conditions

## Troubleshooting

### Swipe not working
- Check that `Enabled` is true
- Ensure WeType keyboard is active and visible
- Check debug logs for gesture recognizer installation and view coverage
- Verify `MinTranslationY` setting (try lowering to 20.0 for testing)
- Check if swipe distance meets the minimum threshold
- Verify that swipe gestures aren't being intercepted by other apps

### Mode switching not working
- Check debug logs for available modes detection
- Verify WeType APIs are accessible (may vary by iOS version)
- Ensure there are at least 2 input modes available
- Check for mode switching errors in debug logs
- Verify mode detection and switching logic in detailed logs

### Slow swipes not detected
- Check `MinTranslationY` setting - ensure it's not too high
- Verify direction locking is working (check debug logs)
- Ensure swipe is primarily vertical (check angle in logs)
- Try increasing swipe distance gradually

### Interference with typing
- Check `SuppressKeyTapOnSwipe` setting (set to false if too aggressive)
- Review debug logs for gesture state transitions
- Ensure swipe gestures are deliberate (not accidental while typing)
- Check for conflicts with other gesture recognizers

### Performance issues
- Set `LogLevel` to INFO or ERROR to reduce logging overhead
- Disable `DebugLog` in production builds
- Check for excessive view installations in debug logs

## Development

The implementation is structured for enhanced WeType-specific integration:

- `WTVerticalSwipeManager` handles enhanced pan gesture recognition with state machine
- Distance-based triggering with configurable thresholds and direction locking
- Comprehensive WeType API discovery with multiple fallback selectors
- Recursive view hierarchy installation for full keyboard coverage
- Multi-level logging system (DEBUG/INFO/ERROR) with Filza-compatible output
- Debounce protection and configurable touch cancellation
- Clean separation between gesture handling and mode management
- Intelligent view filtering to avoid performance issues

## License

This project is provided as-is for educational and personal use.