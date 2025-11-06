# WeType Vertical Swipe Toggle - Version 1.2.2 发布说明

## 🎯 本次更新重点

**解决了垂直滑动手势被IME内容处理器阻止的问题**

## 📋 问题描述

在之前的版本（v1.2.1）中，代码能够正确检测到垂直滑动手势并调用模式切换逻辑，但部分用户报告手势仍然不生效。经过分析发现，原始的触摸处理器（特别是IME内容处理器）在我们的代码执行后也会执行，导致：

- 触摸事件被消费
- 模式切换被干扰
- 手势序列被中断

## ✅ 解决方案

### 核心改进

修改了触摸事件处理逻辑，**当检测到垂直滑动时，不再调用原始的触摸处理器**。

### 技术实现

1. **返回值机制**：`WTSProcessTouchMovedForView` 现在返回 `BOOL` 值
   - `YES`: 已检测到垂直滑动，应阻止原始处理器
   - `NO`: 无垂直滑动，可调用原始处理器

2. **条件性原始调用**：所有 `touchesMoved` 钩子现在根据返回值决定是否调用 `%orig`

3. **智能判断**：基于方向锁定状态 (`directionLocked`) 来决定是否阻止

## 🔧 具体变更

### 修改的函数

```objc
// 之前
static void WTSProcessTouchMovedForView(UIView *view, NSSet<UITouch *> *touches)

// 现在  
static BOOL WTSProcessTouchMovedForView(UIView *view, NSSet<UITouch *> *touches)
```

### 更新的 Hooks

以下5个视图类的 `touchesMoved` 方法已更新：

- `WBMainInputView`
- `WBKeyboardView`
- `WXKBKeyboardView`
- `WXKBMainKeyboardView`
- `WXKBKeyContainerView`

## 📊 效果对比

### v1.2.1（之前）
```
用户滑动 → 我们检测 → 我们切换模式 → 原始处理器执行 → 可能被干扰 ❌
```

### v1.2.2（现在）
```
用户滑动 → 我们检测 → 锁定方向 → 阻止原始处理器 → 我们切换模式 ✅
```

## 🎮 使用体验改进

### 现在可以正常工作
- ✅ 在键盘任意位置上下滑动，可靠触发模式切换
- ✅ 慢速滑动和快速滑动都能正常工作
- ✅ 不受IME内容处理器干扰

### 不受影响的功能
- ✅ 正常点击按键输入字符
- ✅ 长按按键显示备选字符
- ✅ IME候选词选择
- ✅ 水平滑动手势（如果有）

## 🔍 如何验证

### 1. 功能测试

在微信或其他应用中打开键盘：

- 在键盘上向上滑动约30pt，应该切换输入模式
- 在键盘上向下滑动约30pt，应该切换输入模式
- 正常点击按键，应该输入字符
- 长按按键，应该显示备选（如支持）

### 2. 查看日志

日志文件位置：`/var/mobile/Library/Logs/wxkeyboard.log`

成功的滑动应该显示：
```
[ViewClass] Direction locked to vertical (...)
[ViewClass] Blocking original touchesMoved due to vertical swipe
[INFO] [ViewClass] ✓ Up/Down swipe detected: dy=..., distance=...
Successfully switched to [mode] (from [mode])
```

## 📦 安装说明

### 通过包管理器
1. 添加您的软件源
2. 搜索 "WeType Vertical Swipe Toggle"
3. 安装或更新到 v1.2.2
4. 重启 SpringBoard

### 手动安装
1. 下载 .deb 文件
2. 使用 Filza 或命令行安装
3. 重启 SpringBoard

### 验证版本
```bash
dpkg -l | grep wetype
```

应显示版本 1.2.2

## ⚙️ 配置选项

无需修改配置，现有配置继续有效：

```
域名: com.yourcompany.wxkeyboard

可用选项:
- Enabled (bool): 启用/禁用插件 (默认: true)
- DebugLog (bool): 启用调试日志 (默认: true)
- MinTranslationY (float): 最小滑动距离 (默认: 28.0)
- SuppressKeyTapOnSwipe (bool): 滑动时取消按键事件 (默认: true)
- LogLevel (string): 日志级别 DEBUG/INFO/ERROR (默认: DEBUG)
```

## 🐛 已知问题

目前无已知问题。如有问题请报告。

## 🔜 下一步计划

- 监控用户反馈
- 根据需要优化滑动阈值
- 考虑添加触觉反馈选项
- 可能添加手势可视化（调试用）

## 📝 变更日志摘要

### v1.2.2 (本次更新)
- 修复：垂直滑动被IME处理器阻止
- 改进：条件性阻止原始触摸处理器
- 新增：详细的阻止操作日志

### v1.2.1
- 修复：移除个别按键视图的钩子
- 改进：增强诊断日志

### v1.2.0
- 重构：从 UISwipeGestureRecognizer 改为基于触摸的实现
- 新增：支持慢速滑动
- 新增：方向锁定机制

## 🙏 致谢

感谢所有报告问题和提供反馈的用户！

## 📞 支持

如有问题，请：
1. 检查日志文件
2. 查阅文档（README.md, IMPLEMENTATION_V1.2.2.md）
3. 提交问题报告

---

**版本**: 1.2.2  
**发布日期**: 2024  
**兼容性**: iOS 14.0+, WeType 最新版  
**许可**: 查看 LICENSE 文件  
