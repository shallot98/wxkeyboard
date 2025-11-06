# Version 1.2.2 实现说明

## 问题背景

在之前的版本中，虽然我们的代码能够正确检测到垂直滑动手势并调用模式切换逻辑，但用户仍然报告手势不生效。用户提到某些视图类中的reports（可能是触摸事件报告或IME内容）包含了输入法的全部内容，这暗示触摸事件可能被其他处理器消费了。

## 根本原因

### 触摸事件处理链

在iOS中，触摸事件通过响应链传递。当我们hook `touchesMoved:withEvent:`时：

1. 我们的代码首先执行（检测垂直滑动）
2. 调用 `%orig` 后，原始的 `touchesMoved` 实现执行
3. 原始实现可能包含：
   - IME内容处理器
   - 按键状态更新
   - 其他键盘组件的触摸处理

### 问题所在

即使我们检测到了垂直滑动并调用了模式切换，原始的触摸处理器仍然会执行，可能导致：

- IME处理器消费了触摸事件
- 按键被激活（用户不想要的）
- 其他组件干扰了模式切换
- 触摸序列被中断

## 解决方案

### 核心思路

**当检测到垂直滑动时，不再调用原始的触摸处理器。**

这确保了：
- 垂直滑动手势不被打断
- IME或其他处理器不能干扰
- 模式切换能够顺利完成

### 实现细节

#### 1. 修改返回类型

```objc
// 之前
static void WTSProcessTouchMovedForView(UIView *view, NSSet<UITouch *> *touches)

// 现在
static BOOL WTSProcessTouchMovedForView(UIView *view, NSSet<UITouch *> *touches)
```

返回值含义：
- `YES`: 应该阻止原始处理器（垂直滑动进行中）
- `NO`: 可以调用原始处理器（水平移动或无手势）

#### 2. 返回值逻辑

```objc
// 在函数末尾
return state.directionLocked;
```

这意味着：
- 如果方向已经锁定为垂直 → 返回YES，阻止原始处理
- 如果还未确定方向 → 返回NO，允许原始处理
- 如果检测到水平移动 → 返回NO，允许原始处理

#### 3. Hook更新

所有5个视图类的`touchesMoved`都更新为：

```objc
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    BOOL shouldBlock = WTSProcessTouchMovedForView(self, touches);
    if (!shouldBlock) {
        %orig;  // 正常调用原始处理
    } else {
        WTSLog(@"[%@] Blocking original touchesMoved due to vertical swipe", 
               NSStringFromClass(self.class));
        // 不调用%orig - 阻止原始处理
    }
}
```

## 影响分析

### 垂直滑动场景

1. 用户开始向上/下滑动
2. `touchesMoved` 被调用
3. 我们的代码检测到垂直方向 → `directionLocked = YES`
4. 返回 `YES`
5. **不调用 %orig**
6. 原始处理器不执行
7. IME等组件不会干扰
8. 继续滑动直到触发模式切换
9. 模式切换成功

### 正常点击场景

1. 用户点击按键
2. `touchesMoved` 可能被轻微调用（手指微动）
3. 移动距离很小，方向未锁定
4. 返回 `NO`
5. **正常调用 %orig**
6. 原始处理器执行
7. 按键正常响应

### 水平滑动场景

1. 用户水平滑动
2. `touchesMoved` 被调用
3. 我们的代码检测到水平方向
4. `directionLocked` 保持为 `NO`
5. 返回 `NO`
6. **正常调用 %orig**
7. 原始水平滑动逻辑执行（如果有）

## 更新的视图类

以下5个类的`touchesMoved`钩子已更新：

1. `WBMainInputView` - 主输入视图
2. `WBKeyboardView` - 键盘视图
3. `WXKBKeyboardView` - WeType键盘视图
4. `WXKBMainKeyboardView` - 主键盘视图
5. `WXKBKeyContainerView` - 按键容器视图

## 测试验证点

### 功能测试

- [ ] 在键盘上任意位置向上滑动，应该切换到上一个输入模式
- [ ] 在键盘上任意位置向下滑动，应该切换到下一个输入模式
- [ ] 慢速滑动应该和快速滑动一样有效
- [ ] 滑动约30pt距离后应该触发

### 兼容性测试

- [ ] 正常点击按键，应该输入字符
- [ ] 长按按键，应该显示备选字符（如果支持）
- [ ] 快速点击多个按键，应该正常输入
- [ ] IME候选词选择应该正常工作

### 调试验证

查看日志文件 `/var/mobile/Library/Logs/wxkeyboard.log`：

```
# 成功的垂直滑动应该显示：
[ViewClass] Touch moved: dx=..., dy=... (not locked yet)
[ViewClass] Direction locked to vertical (dx=..., dy=..., ...)
[ViewClass] Vertical swipe in progress: dy=..., absDy=..., threshold=28.0, detected=1
[ViewClass] Blocking original touchesMoved due to vertical swipe
[ViewClass] ✓ Up/Down swipe detected: dy=..., distance=...
Successfully switched to ... (from ...)
```

## 技术优势

### 1. 更精确的手势控制

通过条件性地阻止原始处理器，我们获得了对触摸事件的更精确控制。

### 2. 避免竞态条件

不再有"我们的代码执行了，但原始代码覆盖了我们的操作"的竞态条件。

### 3. 更好的兼容性

- 垂直滑动：我们完全控制
- 其他情况：完全交给原始处理器

### 4. 可观测性

通过日志清楚地知道何时阻止了原始处理器。

## 代码变更统计

- **修改的函数**: 1个（`WTSProcessTouchMovedForView`）
- **修改的hooks**: 5个视图类的`touchesMoved`方法
- **新增日志**: 1个（阻止原始处理时）
- **版本号**: 1.2.1 → 1.2.2

## 向后兼容性

此更改向后兼容：
- 没有修改配置选项
- 没有改变外部API
- 只优化了内部触摸事件处理逻辑

用户无需修改任何配置即可获得修复。
