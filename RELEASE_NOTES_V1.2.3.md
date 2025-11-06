# WeTypeVerticalSwipeToggle v1.2.3 Release Notes

## Critical Bug Fix: IME Gesture Consumption

### The Issue
In version 1.2.2, we attempted to fix gesture interference by blocking the `touchesMoved` handler when a vertical swipe was detected. However, users reported that **the gesture still didn't work** and that "reports contain all WeChat IME content."

### Root Cause Analysis
The problem was that we only blocked `touchesMoved`, but **always called the original handler in `touchesEnded`**. This meant:

1. ✅ We detected the vertical swipe correctly
2. ✅ We blocked `touchesMoved` to prevent key activation
3. ✅ We triggered the mode switch
4. ❌ **But** `touchesEnded` called `%orig`, allowing the IME handler to complete its processing
5. ❌ The IME consumed the gesture, preventing the mode switch from taking effect

The touch event sequence is: `touchesBegan → touchesMoved (multiple) → touchesEnded`

Even though we intercepted the middle part, the IME handler still received the complete sequence (began + ended) and was able to process it.

### The Fix
Now we **completely hijack the touch sequence** when a vertical swipe is detected:

- **touchesBegan**: Always call original (we don't know what gesture this will be yet)
- **touchesMoved**: Block original if vertical direction is locked
- **touchesEnded**: Block original if vertical swipe was detected ← **NEW**
- **touchesCancelled**: Block original if vertical swipe was detected ← **NEW**

This prevents the IME and other handlers from receiving the complete touch sequence, ensuring they can't interfere with our gesture.

### Technical Implementation
All 5 hooked view classes now check `state.verticalSwipeDetected` before calling `%orig` in `touchesEnded` and `touchesCancelled`:

```objective-c
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    WTVerticalSwipeManager *tracker = objc_getAssociatedObject(self, kWTTouchTrackerKey);
    BOOL shouldBlock = NO;
    if (tracker) {
        WTTouchState state = tracker.touchState;
        shouldBlock = state.verticalSwipeDetected;  // ← Check if swipe was detected
        // ... reset state ...
    }
    if (!shouldBlock) {
        %orig;  // Only call original if no swipe detected
    } else {
        WTSLog(@"Blocking original touchesEnded due to completed vertical swipe");
    }
}
```

### Affected Classes
- WBMainInputView
- WBKeyboardView
- WXKBKeyboardView
- WXKBMainKeyboardView
- WXKBKeyContainerView

### User Impact
✅ **Vertical swipe gestures now work reliably** - IME can't interfere anymore  
✅ **Normal keyboard taps still work perfectly** - we only block when swipe is detected  
✅ **Horizontal gestures unaffected** - direction detection ensures we don't block those  
✅ **Better gesture isolation** - complete control over touch sequence during swipes

### Testing
To verify this fix:
1. Install v1.2.3
2. Open WeType keyboard in any app
3. Perform vertical swipe gesture (up or down)
4. Mode should switch without IME interference
5. Check logs to see "Blocking original touchesEnded" messages
6. Verify normal taps still work (keys respond correctly)

### Version History
- **v1.2.3** (Current): Block touchesEnded and touchesCancelled when swipe detected
- v1.2.2: Block touchesMoved when swipe detected (insufficient)
- v1.2.1: Initial attempt at gesture detection
- v1.2.0: Basic mode switching implementation
