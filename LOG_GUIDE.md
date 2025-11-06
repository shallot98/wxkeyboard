# 日志查看指南 - WeType Vertical Swipe Toggle

## 日志文件位置

### 主日志文件
```
/var/mobile/Library/Preferences/wxkeyboard.log
```

### 备份日志文件（当主日志超过256KB时自动轮转）
```
/var/mobile/Library/Preferences/wxkeyboard.log.1
```

## 如何查看日志

### 方法1：通过SSH
```bash
# 查看实时日志（推荐）
tail -f /var/mobile/Library/Preferences/wxkeyboard.log

# 查看最后100行
tail -n 100 /var/mobile/Library/Preferences/wxkeyboard.log

# 查看完整日志
cat /var/mobile/Library/Preferences/wxkeyboard.log
```

### 方法2：通过文件管理器
1. 使用 Filza 或其他文件管理器
2. 导航到 `/var/mobile/Library/Preferences/`
3. 打开 `wxkeyboard.log` 文件
4. 使用文本查看器查看

### 方法3：通过系统日志
```bash
# 查看系统日志中的相关条目
log show --predicate 'eventMessage contains "wxkeyboard"' --last 5m

# 或使用 Console.app（Mac连接设备）
# 搜索关键词：[wxkeyboard] 或 [v1.0.1]
```

## 日志内容说明

### 启动诊断日志
```
================================================================================
WeType Vertical Swipe Toggle v1.0.1 - Launch Diagnostics
================================================================================
```
- 显示插件版本和配置信息
- 列出进程信息和bundle标识
- 说明v1.0.1的行为变更

### 手势识别日志
```
[v1.0.1] Gesture recognizer installed with HIGHEST priority (cancelsTouchesInView=YES) on <WBMainInputView>
```
- 确认手势识别器已安装
- 显示安装位置

### 滑动开始日志
```
[v1.0.1] Pan began at {x, y} (detected region=XXX - will be IGNORED, always CN/EN toggle, mode=zh-Hans)
```
- 显示滑动开始位置
- 显示检测到的区域（但会被忽略）
- 显示当前输入模式

### 切换成功日志
```
[v1.0.1] ✓ CN/EN toggle triggered (Up/Down) dy=50.0 dx=2.0 detected_region=XXX (ignored) mode=zh-Hans -> en-US
```
- ✓ 表示成功
- 显示滑动方向和距离
- 显示模式切换（从中文到英文）

### 切换失败日志
```
[v1.0.1] ✗ Gesture vertical but CN/EN toggle failed (Up) dy=50.0 dx=2.0 detected_region=XXX (ignored) mode=zh-Hans
```
- ✗ 表示失败
- 显示可能的失败原因
- 帮助调试问题

### 滑动结束日志
```
[v1.0.1] Pan ended after CN/EN toggle (direction=Up dy=50.0 dx=2.0 detected_region=XXX (ignored) mode=en-US)
```
- 显示滑动手势完成
- 显示最终状态

## 常见日志模式

### 正常工作
```
[v1.0.1] Pan began at {150, 200}...
[v1.0.1] Force language toggle mode: ignoring region-specific actions
[v1.0.1] ✓ CN/EN toggle triggered...
[v1.0.1] Pan ended after CN/EN toggle...
```

### 滑动距离不足
```
[v1.0.1] Pan began at {150, 200}...
[v1.0.1] Pan ended without action (direction=Up dy=15.0 dx=2.0 threshold=25.0 vertical=NO...)
```
- 滑动距离(dy=15.0)小于阈值(threshold=25.0)

### 顶部任务栏被过滤
```
[v1.0.1] Ignoring touch in disabled zone (<UIView>) limit=80.00
```
- 触摸在顶部任务栏区域，被正确过滤

## 故障排查

### 问题1：插件未加载
查找日志中的启动信息：
```bash
grep "Launch Diagnostics" /var/mobile/Library/Preferences/wxkeyboard.log
```
如果没有找到，说明插件未在WeType进程中加载。

### 问题2：手势未响应
查找滑动开始的日志：
```bash
grep "Pan began" /var/mobile/Library/Preferences/wxkeyboard.log
```
如果没有找到，可能是手势识别器未安装。

### 问题3：切换失败
查找失败日志：
```bash
grep "✗" /var/mobile/Library/Preferences/wxkeyboard.log
```
查看具体失败原因和上下文。

## 反馈信息模板

当向开发者反馈问题时，请提供：

1. **设备信息**
   - iOS版本
   - 越狱类型
   - 微信输入法版本

2. **问题描述**
   - 具体操作步骤
   - 预期行为
   - 实际行为

3. **日志内容**
```bash
# 复制最近的日志（最后200行）
tail -n 200 /var/mobile/Library/Preferences/wxkeyboard.log
```

4. **重现步骤**
   - 打开哪个应用
   - 在哪个区域滑动
   - 滑动方向

## 日志级别控制

日志默认在v1.0.1+中始终启用。可以通过修改配置文件控制：

```bash
# 禁用日志（不推荐，会影响故障排查）
defaults write com.yourcompany.wxkeyboard DebugLog -bool false

# 启用日志（默认）
defaults write com.yourcompany.wxkeyboard DebugLog -bool true

# 重启微信输入法使配置生效
killall -9 WeType WeTypeKeyboard
```

## 日志清理

如果日志文件过大，可以手动清理：

```bash
# 查看日志大小
ls -lh /var/mobile/Library/Preferences/wxkeyboard.log*

# 清空日志（保留文件）
> /var/mobile/Library/Preferences/wxkeyboard.log
> /var/mobile/Library/Preferences/wxkeyboard.log.1

# 或完全删除
rm /var/mobile/Library/Preferences/wxkeyboard.log*
```

日志会在下次插件加载时自动重新创建。
