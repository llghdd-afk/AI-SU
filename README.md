# AI+SU

**AI建模助手** 是一个面向 SketchUp 的 AI 建模插件。它通过自然语言对话引导用户确认设计细节，生成可在 SketchUp 中执行的 Ruby 建模代码，并在执行后尽量把新增几何整理成一个可选择、可移动的整体对象。

## 1.0 目标

本版本聚焦修正实际使用中暴露的几个问题：

- 生成模型不再默认散成一堆孤立零件：系统提示和执行后整理逻辑都会要求把新增对象放入顶层 Group/Component。
- 生成代码前先沟通细节：缺少尺寸、材质、装配关系或风格时，AI 会先追问和确认，不直接丢代码。
- DeepSeek coder 模式下截图分析不再报 `image_url` 反序列化错误：DeepSeek 不支持当前图片消息格式时，插件会降级为文字上下文分析。
- 输入框支持粘贴参考图：支持视觉的模型会收到参考图；不支持视觉的模型会要求用户用文字补充参考图关键信息。
- 修复 HtmlDialog 回调调用方式：前端按 SketchUp 官方 `sketchup.callback_name(...)` 方式调用 Ruby 回调。

## 安装

推荐使用发布包：

1. 下载 `dist/AI+SU.rbz`。
2. 打开 SketchUp。
3. 进入 `窗口 > 扩展管理器 > 安装扩展`。
4. 选择 `AI+SU.rbz`。
5. 重启 SketchUp。
6. 在 `扩展 > AI建模助手` 中打开插件。

也可以手动安装：

1. 将 `AI+SU.rb` 复制到 SketchUp 的 `Plugins` 目录。
2. 重启 SketchUp。

Windows 常见插件目录：

```text
C:\Users\<你的用户名>\AppData\Roaming\SketchUp\SketchUp 20XX\SketchUp\Plugins
```

## DeepSeek 使用建议

如果你接入的是 DeepSeek，并选择 coder 模型：

- 适合生成 SketchUp Ruby 代码。
- 不适合直接分析截图或参考图，因为当前 DeepSeek OpenAI 兼容接口会拒绝 `image_url` 多模态消息。
- 截图分析和参考图粘贴会自动降级为文字上下文：插件会读取当前模型结构，并提示用户补充图片里的关键造型、尺寸比例和装配关系。

如果你希望 AI 直接看图，请切换到支持视觉输入的模型，例如 Gemini、Qwen-VL 或自定义视觉模型。

## 密钥安全

本仓库是公开仓库，不要把真实 API Key 写入 `AI+SU.rb`、README、示例文件或提交历史。

插件设置页输入的 API Key 会通过 SketchUp 的 `Sketchup.write_default` 保存在本机用户配置中，用于运行时请求，不会作为源码或安装包内容上传到 GitHub。

如果误把密钥提交到仓库，请立即撤销提交、清理历史，并在 DeepSeek 控制台轮换密钥。

## 建模工作流

1. **方案沟通**：描述目标模型、用途、风格和参考信息。
2. **参数确认**：确认尺寸、数量、位置、材质、连接方式和装配关系。
3. **代码生成**：生成 Ruby 代码并放入下方控制台。
4. **执行整理**：执行代码后，插件会尝试把本次新增对象整理成一个顶层整体对象并选中。

## 开发与打包

语法检查：

```powershell
ruby -c .\AI+SU.rb
```

生成 SketchUp 安装包：

```powershell
.\tools\package.ps1
```

输出文件：

```text
dist\AI+SU.rbz
```

## 安全边界

插件会在执行 AI 生成的 Ruby 代码前做基本安全检查，拦截文件、目录、系统命令、网络、嵌套 `eval` 等危险操作。不过 AI 代码执行仍然是高权限本地行为，建议先阅读 Ruby 控制台里的代码，再手动执行。

## 参考

项目结构和交互方式参考了 SketchUp Ruby 扩展的常见做法，以及同类 AI 辅助 SketchUp 项目中“场景检查、组件操作、Ruby 执行、安装包发布”的组织方式。本仓库不复制第三方项目代码。
