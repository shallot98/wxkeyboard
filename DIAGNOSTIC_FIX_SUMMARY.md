# 诊断与修复总结 - 滑动失效根因分析

## 问题现象回顾

**上次修复后的状态：**
- ✓ 长按功能恢复正常
- ✗ 所有上下滑动功能失效

## 根因诊断

### 问题定位

通过代码分析发现根本原因：

**之前的实现（Version 1.2.0）同时 hook 了：**
1. 容器视图：`WBMainInputView`, `WBKeyboardView`, `WXKBKeyboardView`, 等
2. **个别按键视图**：`WBKeyView`, `WXKBKeyView`

### 失效机制分析

当用户在键盘上执行滑动操作时：

```
1. 用户触摸一个按键
   └─> touchesBegan 在 WBKeyView（个别按键）上被调用
   └─> 记录起始位置

2. 用户开始向上/下滑动
   └─> 触摸点移出按键边界
   └─> UIKit 停止向该按键视图发送 touchesMoved 事件
       （因为触摸点已经在视图外部）
   └─> 滑动检测逻辑从未被触发
   └─> ✗ 滑动失效

3. 长按仍然工作
   └─> 因为长按不需要移动
   └─> %orig 调用保留了原始手势识别器
   └─> ✓ 长按正常
```

### 关键问题

**个别按键视图太小**，无法捕获完整的滑动手势：
- 按键尺寸：通常 ~40x40pt
- 滑动阈值：28pt（minTranslationY）
- 手指稍微移动就离开了按键边界
- touchesMoved 不再被调用到该按键视图

## 解决方案

### 修复策略

**移除个别按键视图的触摸事件 hook**，仅保留容器视图：

#### 保留的 hook（容器视图）：
- ✓ `WBMainInputView` - 主输入视图
- ✓ `WBKeyboardView` - 键盘视图
- ✓ `WXKBKeyboardView` - 额外键盘视图
- ✓ `WXKBMainKeyboardView` - 主键盘容器
- ✓ `WXKBKeyContainerView` - 按键容器视图

#### 移除的 hook（个别按键）：
- ✗ `WBKeyView` - 完全移除所有触摸方法 hook
- ✗ `WXKBKeyView` - 完全移除所有触摸方法 hook

### 实现细节

#### 1. 移除个别按键 hook

```objc
// 之前：hook 了 WBKeyView 和 WXKBKeyView 的所有触摸方法
// 现在：完全移除，替换为注释说明

// Individual key view hooks removed - touch handling only on container views
// This ensures swipe detection works properly (container views capture full gesture)
// while preserving long-press functionality on individual keys
```

#### 2. 更新视图过滤逻辑

```objc
static BOOL WTSShouldInstallOnView(UIView *view) {
    // 新增：明确排除个别按键视图
    if ([className containsString:@"KeyView"] || 
        [className hasSuffix:@"Key"] ||
        [className isEqualToString:@"WBKeyView"] ||
        [className isEqualToString:@"WXKBKeyView"]) {
        return NO;  // 不在个别按键上安装追踪器
    }
    
    // 仅在大型容器视图上安装
    BOOL isKeyboardContainer = [className containsString:@"Keyboard"] || 
                               [className containsString:@"Input"] || ...;
    BOOL isLargeEnough = boundsSize.width > 100.0 && boundsSize.height > 50.0;
    
    return (isKeyboardContainer && isLargeEnough) || 
           (boundsSize.width > 200.0 && boundsSize.height > 100.0);
}
```

#### 3. 增强诊断日志

添加详细日志记录，包括：
- 视图类名（便于识别哪个视图接收了触摸）
- 视图边界尺寸（验证容器视图足够大）
- 触摸移动的每一步（dx, dy, 方向锁定状态）
- 滑动检测过程（阈值比较、触发判定）

```objc
WTSLog(@"[%@] Touch began at (%.1f, %.1f) - bounds: %.1fx%.1f", 
       NSStringFromClass(self.class), x, y, width, height);

WTSLog(@"[%@] Touch moved: dx=%.1f, dy=%.1f (not locked yet)", 
       NSStringFromClass(view.class), dx, dy);

WTSLogInfo(@"[%@] ✓ Up swipe detected: dy=%.1f, distance=%.1f", 
          NSStringFromClass(view.class), dy, absDy);
```

## 预期效果

### 滑动功能

**容器视图足够大，可以捕获完整手势：**

```
1. 用户触摸键盘任意位置
   └─> touchesBegan 在容器视图（如 WBKeyboardView）上被调用
   └─> 容器尺寸：~390x250pt（足够大）

2. 用户滑动
   └─> 触摸点仍在容器视图内
   └─> touchesMoved 持续被调用
   └─> 滑动距离累积
   └─> 达到阈值（28pt）
   └─> ✓ 触发输入法切换

3. 连续滑动
   └─> 所有移动事件都被容器视图捕获
   └─> ✓ 稳定识别
```

### 长按功能

**个别按键不再被 hook，原始行为完全保留：**

```
1. 用户长按按键
   └─> 触摸事件传递给按键视图
   └─> 按键视图的原始手势识别器（UILongPressGestureRecognizer）工作
   └─> ✓ 长按功能正常（复制、粘贴等）

2. 容器视图也接收事件
   └─> 但滑动未发生（距离不足）
   └─> 不干扰按键的长按
   └─> ✓ 互不冲突
```

## 验收标准

### ✓ 长按功能保留
- 所有按键长按功能正常
- 底行按钮长按正常
- 特殊按键（删除、空格等）长按正常

### ✓ 滑动功能恢复
- 任意键面区域上下滑动触发切换
- 慢速滑动稳定触发
- 小幅度（~30pt）即可触发
- 连续滑动稳定识别

### ✓ 正常点按不受影响
- 单击按键输入字符
- 点按不误触发滑动

### ✓ 完整诊断日志
- 日志清晰标注视图类名
- 记录触摸移动全过程
- 便于后续问题排查

## 技术要点总结

1. **视图层级理解**：触摸事件在视图层级中的传递机制
2. **边界限制**：触摸移出视图边界后，touchesMoved 不再被调用
3. **容器 vs 个别视图**：手势检测应在足够大的容器视图上进行
4. **事件传递**：%orig 调用确保原始行为（如长按）继续工作
5. **职责分离**：容器负责滑动检测，按键负责点击/长按

## 文件变更

- **Tweak.xm**：
  - 移除 `%hook WBKeyView` 和 `%hook WXKBKeyView` 的所有触摸方法
  - 更新 `WTSShouldInstallOnView` 过滤逻辑
  - 增强日志输出（添加视图类名和边界信息）
  - 改进 `WTSProcessTouchMovedForView` 诊断日志

## 预防措施

**未来开发指导：**
- 手势识别应安装在**容器视图**上，而非个别子视图
- 需要捕获完整手势的视图应**足够大**（至少 100x50pt）
- 个别按键视图应保持**原始触摸行为**，避免干扰系统手势
- 充分的**日志记录**有助于快速定位问题

---

本次修复采用**最小侵入原则**：
- 移除不必要的 hook（个别按键）
- 保留必要的 hook（容器视图）
- 完全依赖 iOS 的标准触摸事件机制
- 不使用任何 hack 或 workaround

预期此方案可以**同时满足滑动和长按两个需求**，无需任何妥协。
