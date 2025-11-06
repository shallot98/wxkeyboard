# Version 1.2.2 修复说明

## 问题描述

用户反馈：上下滑手势依旧不生效，某些视图类中的reports包含微信输入法的全部内容。

## 根本原因

在之前的实现中，虽然我们正确地检测到了垂直滑动手势，但是在调用`%orig`后，原始的触摸处理器（特别是IME相关的内容处理器）会消费掉这个事件，导致：

1. 手势识别被中断
2. 键盘的原始行为（如按键点击、IME内容处理）优先执行
3. 我们的模式切换逻辑虽然被调用，但可能被后续的原始处理覆盖或干扰

## 解决方案

### 核心改变

将`WTSProcessTouchMovedForView`从`void`改为返回`BOOL`：

```objc
static BOOL WTSProcessTouchMovedForView(UIView *view, NSSet<UITouch *> *touches) {
    // ... 手势处理逻辑 ...
    
    // 返回YES表示应该阻止原始处理器
    return state.directionLocked;
}
```

### 返回值逻辑

- **返回 YES**：当方向锁定为垂直方向，或已检测到垂直滑动时
  - 此时不调用`%orig`，阻止原始处理器执行
  - 防止IME或其他处理器消费触摸事件
  
- **返回 NO**：当检测到水平移动，或手势尚未确定方向时
  - 正常调用`%orig`
  - 保留键盘的正常点击和水平滑动功能

### Hook更新

所有`touchesMoved`的hook都更新为：

```objc
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    BOOL shouldBlock = WTSProcessTouchMovedForView(self, touches);
    if (!shouldBlock) {
        %orig;
    } else {
        WTSLog(@"[%@] Blocking original touchesMoved due to vertical swipe", 
               NSStringFromClass(self.class));
    }
}
```

## 影响的视图类

以下类的`touchesMoved`钩子都已更新：

1. `WBMainInputView`
2. `WBKeyboardView`
3. `WXKBKeyboardView`
4. `WXKBMainKeyboardView`
5. `WXKBKeyContainerView`

## 测试要点

1. ✓ 垂直滑动手势应该能够触发模式切换
2. ✓ 正常按键点击不受影响
3. ✓ 长按功能正常工作
4. ✓ 水平滑动（如果有）不受影响
5. ✓ IME输入内容不会干扰手势识别

## 技术细节

### 为什么这样有效

- 当用户开始垂直滑动时，方向被锁定为垂直
- 此时我们不再调用原始的`touchesMoved`处理器
- 这防止了IME或其他组件"吞掉"触摸事件
- 手势可以顺利完成，模式切换成功执行

### 不会破坏的功能

- 点击按键：因为点击不涉及大幅度移动，`directionLocked`保持为NO
- 长按：长按在`touchesBegan`时就开始处理，不依赖`touchesMoved`
- 水平手势：水平移动会导致函数提前返回NO，原始处理器正常执行

## 调试日志

如果需要调试，查看日志中的这些关键信息：

```
[ViewClass] Direction locked to vertical (dx=X, dy=Y, ...)  // 方向锁定
[ViewClass] Blocking original touchesMoved due to vertical swipe  // 阻止原始处理
[ViewClass] ✓ Up/Down swipe detected: dy=X, distance=Y  // 手势成功检测
```

日志路径：`/var/mobile/Library/Logs/wxkeyboard.log`
