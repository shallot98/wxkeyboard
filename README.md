# WeType Vertical Swipe Toggle v1.0.1

这个插件为微信输入法（WeType）添加垂直滑动手势，通过上下滑动键盘区域快速切换中英文输入模式。

## 🆕 v1.0.1 重大更新

### 主要变更
- **统一的中英文切换**：现在所有键盘区域（除顶部任务栏外）的上下滑动都只切换中英文，不再根据区域触发数字/符号键盘
- **最高优先级**：手势识别器设置为最高优先级（`cancelsTouchesInView=YES`），覆盖微信输入法原有的滑动功能
- **增强的日志系统**：在发布版本中也启用日志功能，方便用户反馈和调试

### 新增文档
- [更新日志](CHANGELOG.md) - 详细的版本变更记录
- [日志查看指南](LOG_GUIDE.md) - 如何查看和分析日志

## 功能特性

### 垂直滑动手势
- 在键盘任意区域（除顶部任务栏外）向上或向下滑动
- 自动在中文和英文输入模式之间切换
- 与普通点击和长按操作完全兼容
- 自动适配 VoiceOver 辅助功能

### 智能区域检测
- 顶部任务栏（候选词、工具栏）不响应滑动手势
- 自动识别并排除表情、剪贴板等特殊面板
- 多层检测机制确保准确性

### 安全特性
- 仅在微信输入法激活时工作
- 完整的错误处理和回退机制
- 保留原有长按功能
- 详细的日志记录便于故障排查

## 配置选项

插件支持以下配置（存储在 `com.yourcompany.wxkeyboard`）：

- `Enabled` (bool): 主开关 (默认: true)
- `DebugLog` (bool): 启用调试日志 (默认: true，v1.0.1+ 在发布版本也启用)
- `GlobalSwipe` (bool): 全局滑动切换中英文 (默认: true)
- `SwipeThreshold` (float): 滑动距离阈值，单位像素 (默认: 25.0)

**注意**：v1.0.1 移除了区域特定的键盘切换功能，以下配置已不再使用：
- `RegionSwipe`、`NineKeyEnabled`、`NumberKeyEnabled`、`SpacebarEnabled`

## 安装

### 从源码构建
```bash
# 项目使用 GitHub Actions 自动构建
# 推送到 GitHub 后会自动生成 .deb 包
```

### 手动安装
1. 从 [Releases](../../releases) 下载最新的 `.deb` 文件
2. 使用 Filza 或其他包管理器安装
3. 重启微信输入法
4. 开始使用！

## 使用方法

1. 打开任何支持微信输入法的应用
2. 激活键盘
3. 在键盘区域（除顶部任务栏外）向上或向下滑动
4. 输入法将自动在中文和英文之间切换

## 兼容性

- **输入法**: WeType (微信输入法) `com.tencent.wetype.keyboard`
- **iOS版本**: iOS 13+ (测试环境: iOS 16+)
- **越狱类型**: 支持 rootless 越狱
- **架构**: arm64, arm64e

## 日志和调试

### 日志位置
- 主日志：`/var/mobile/Library/Preferences/wxkeyboard.log`
- 备份日志：`/var/mobile/Library/Preferences/wxkeyboard.log.1`

### 查看实时日志
```bash
tail -f /var/mobile/Library/Preferences/wxkeyboard.log
```

### 日志内容
启用 `DebugLog` 后，日志将包含：
- 插件启动和配置信息
- 手势识别器安装状态
- 每次滑动的详细信息（位置、距离、方向）
- 语言切换结果
- 错误和警告信息

详细的日志分析指南请查看 [LOG_GUIDE.md](LOG_GUIDE.md)。

## 故障排查

### 滑动没有响应
1. 确认 `Enabled` 选项为 true
2. 确认不是在顶部任务栏区域滑动
3. 尝试增加滑动距离（确保超过 25 像素）
4. 查看日志文件了解详细信息

### 切换失败
1. 确认微信输入法已正确安装
2. 检查是否添加了中英文输入法
3. 查看日志中的错误信息
4. 尝试重启微信输入法进程

### 性能问题
1. 如果日志文件过大，可以删除重新生成
2. 调整 `SwipeThreshold` 减少误触发

## 开发信息

### 项目结构
- `Tweak.xm` - 主要实现代码
- `control` - 包信息和依赖
- `Makefile` - 构建配置
- `.github/workflows/build-deb.yml` - CI/CD 配置

### 构建系统
- 使用 Theos 构建系统
- GitHub Actions 自动构建和发布
- 支持 rootless 和传统越狱

### 代码特点
- 完整的 Objective-C 运行时方法发现
- 多层回退机制确保兼容性
- 详细的日志记录和错误处理
- 模块化设计便于扩展

## 技术实现

### 手势识别
- 使用 `UIPanGestureRecognizer` 识别垂直滑动
- 设置为最高优先级（`cancelsTouchesInView=YES`）
- 自动判断滑动方向和距离
- 与其他手势和谐共存

### Hook 机制
- Hook WeType 的主要 view 类
- 在合适的生命周期方法注入手势识别器
- 使用 associated objects 管理状态
- 完整的清理机制避免内存泄漏

### 语言切换策略
1. 尝试调用 WeType 私有 API
2. 使用 UIInputViewController 的 inputModes
3. 回退到轮询模式

## 反馈和支持

### 报告问题
在提交 Issue 时，请包含：
1. iOS 版本和越狱类型
2. 微信输入法版本
3. 详细的问题描述和重现步骤
4. 相关的日志内容（最后 100-200 行）

### 贡献代码
欢迎提交 Pull Request！请确保：
1. 遵循现有代码风格
2. 添加适当的日志信息
3. 更新文档和版本号
4. 测试多个 iOS 版本

## 版本历史

### v1.0.1 (当前版本)
- 移除区域特定的键盘切换逻辑
- 统一为中英文切换
- 提升手势优先级
- 增强日志系统
- 添加详细文档

### v1.0.0
- 初始版本
- 基础垂直滑动功能
- 区域检测和特定操作

详细的变更记录请查看 [CHANGELOG.md](CHANGELOG.md)。

## 许可证

本项目仅供学习和个人使用。

## 致谢

- [Theos](https://theos.dev/) - iOS 越狱开发框架
- [Randomblock1/theos-action](https://github.com/Randomblock1/theos-action) - GitHub Actions 构建工具
- WeType 团队 - 优秀的输入法应用
