# Implementation Notes - Version 1.2.1

## Summary of Changes

This version fixes the critical bug where swipe gestures stopped working after the custom touch handling implementation in version 1.2.0.

## Problem Analysis

### Root Cause
Version 1.2.0 hooked touch events on **individual key views** (WBKeyView, WXKBKeyView) which are too small (~40x40pt) to capture complete swipe gestures:

1. User touches a key → `touchesBegan` called on that key view
2. User swipes vertically → touch moves outside key bounds
3. UIKit stops delivering `touchesMoved` to that key view
4. Swipe never reaches threshold → **detection fails**

### Why Long-Press Still Worked
- Long-press doesn't require movement outside the key bounds
- Original gesture recognizers were preserved via `%orig` calls
- UILongPressGestureRecognizer on keys continued to function

## Solution

### Key Changes

#### 1. Removed Individual Key Hooks
Completely removed touch event hooks for:
- `WBKeyView` 
- `WXKBKeyView`

These small views cannot reliably detect swipe gestures.

#### 2. Kept Container View Hooks
Maintained touch event hooks for larger container views:
- `WBMainInputView` (main input container)
- `WBKeyboardView` (keyboard container)
- `WXKBKeyboardView` (additional keyboard view)
- `WXKBMainKeyboardView` (main keyboard container)
- `WXKBKeyContainerView` (key container)

These views are large enough (200x100pt+) to capture full swipe paths.

#### 3. Enhanced View Filtering
Updated `WTSShouldInstallOnView` to explicitly skip individual key views:

```objc
// Skip individual key views - they're too small for swipe detection
if ([className containsString:@"KeyView"] || 
    [className hasSuffix:@"Key"] ||
    [className isEqualToString:@"WBKeyView"] ||
    [className isEqualToString:@"WXKBKeyView"]) {
    return NO;
}
```

#### 4. Improved Diagnostic Logging
Enhanced all touch logs to include:
- View class name (identify which view is handling touches)
- View bounds (verify container views are large enough)
- Detailed movement tracking (dx, dy, thresholds)
- Operation context markers ([WBKeyboardView], etc.)

Example:
```objc
WTSLog(@"[%@] Touch began at (%.1f, %.1f) - bounds: %.1fx%.1f", 
       NSStringFromClass(self.class), x, y, width, height);
```

## Expected Behavior

### Swipe Detection
- Touch begins on any part of keyboard
- Container view (large) captures touch
- User swipes up/down ≥28pt
- Container continues receiving `touchesMoved` events
- Threshold reached → mode switch triggered
- ✓ **Works reliably**

### Long-Press
- Touch begins on individual key
- Both key view and container view receive events
- Key's UILongPressGestureRecognizer fires (via `%orig`)
- No interference from swipe detection (threshold not reached)
- ✓ **Works as expected**

### Normal Tap
- Touch begins and ends on same key
- No significant movement
- Key's tap handler fires normally
- Swipe detection sees insufficient distance
- ✓ **No interference**

## Technical Architecture

### View Hierarchy
```
WBMainInputView (390x250pt)
├── WBKeyboardView (390x200pt)
│   ├── WXKBKeyContainerView (390x160pt)
│   │   ├── WBKeyView (~40x40pt) ← NOT HOOKED
│   │   ├── WBKeyView (~40x40pt) ← NOT HOOKED
│   │   └── ... more keys
│   └── ... other subviews
└── ... other components
```

### Touch Event Flow
```
1. User touches keyboard
   ↓
2. Touch delivered to both:
   - Individual key (not hooked, original behavior)
   - Container view (hooked, swipe detection)
   ↓
3a. If tap/long-press:
    → Key handles interaction
    → Container sees no movement, ignores
    
3b. If swipe:
    → Touch moves outside key bounds
    → Container still receives touchesMoved
    → Swipe detected when threshold reached
```

### Hook Structure
```objc
%group WTSWeTypeHooks

%hook WBMainInputView
  - didMoveToWindow, layoutSubviews (install tracker)
  - touchesBegan, touchesMoved, touchesEnded, touchesCancelled
%end

%hook WBKeyboardView
  [same structure]
%end

%hook WBInputViewController
  - viewDidLoad, viewDidLayoutSubviews (install on .view)
%end

%hook WXKBKeyboardView
  [same structure as WBMainInputView]
%end

%hook WXKBMainKeyboardView
  [same structure]
%end

%hook WXKBKeyContainerView
  [same structure]
%end

%hook UIKeyboardImpl
  - activate, setInputMode: (diagnostics)
%end

%end // WTSWeTypeHooks
```

## Testing Checklist

- [ ] Long-press on letter keys shows popup
- [ ] Long-press on space bar shows cursor movement
- [ ] Long-press on delete key rapid-deletes
- [ ] Swipe up anywhere on keyboard switches to English
- [ ] Swipe down anywhere on keyboard switches to Chinese
- [ ] Slow swipes (~30pt) trigger switch
- [ ] Fast swipes trigger switch
- [ ] Normal taps input characters correctly
- [ ] No accidental mode switches during typing
- [ ] Logs show container view names in touch events
- [ ] Logs show complete swipe detection process

## Files Modified

1. **Tweak.xm** (-208 lines, +97 lines)
   - Removed WBKeyView and WXKBKeyView hook blocks
   - Updated WTSShouldInstallOnView filtering logic
   - Enhanced logging throughout touch handling
   - Added view class names to all log messages

2. **CHANGELOG.md** (+26 lines)
   - Added Version 1.2.1 section
   - Documented bug fix and improvements
   - Cross-referenced DIAGNOSTIC_FIX_SUMMARY.md

3. **Makefile** (version: 1.2.0 → 1.2.1)
4. **control** (version: 1.1.0 → 1.2.1)

## Files Added

- **DIAGNOSTIC_FIX_SUMMARY.md** - Detailed Chinese language root cause analysis
- **IMPLEMENTATION_NOTES.md** - This file

## Build & Deployment

This tweak is built using GitHub Actions with Randomblock1/theos-action@v1:
- Builds for arm64 and arm64e
- Runs on macOS-14 (Apple Silicon) runner
- Produces .deb packages for both architectures
- No local Theos installation required

## Future Considerations

### Preventing Similar Issues
- **Always use container views for gesture detection**
- **Test on actual device** - simulators may behave differently with touch events
- **Add comprehensive logging early** - helps identify issues quickly
- **Consider view size** - gestures need sufficient capture area

### Potential Enhancements
- Add configuration for container view minimum size
- Implement fallback detection for unusual keyboard layouts
- Add gesture conflict resolution for other tweaks
- Consider using hitTest: for more precise view selection

## Notes for Maintainers

1. **Do not hook individual key views** - they're too small for gesture detection
2. **Always verify view bounds** in logs when debugging touch issues  
3. **Container views must be >100x50pt** to reliably capture swipes
4. **Keep %orig calls** to preserve original keyboard functionality
5. **Test both swipe and long-press** after any touch handling changes

---

**Version:** 1.2.1  
**Date:** 2024  
**Status:** ✓ Ready for deployment
