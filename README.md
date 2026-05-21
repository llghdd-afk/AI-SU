# AI+SU

[![CI](https://github.com/llghdd-afk/AI-SU/actions/workflows/ci.yml/badge.svg)](https://github.com/llghdd-afk/AI-SU/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/llghdd-afk/AI-SU?display_name=tag)](https://github.com/llghdd-afk/AI-SU/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**AI建模助手** 是一个面向 SketchUp 的 AI 建模插件。它通过自然语言对话引导用户确认设计细节，生成可在 SketchUp 中执行的 Ruby 建模代码，并在执行后尽量把新增几何整理成一个可选择、可移动的整体对象。

> Repository slug: `AI-SU`<br>
> Plugin entry file: `AI+SU.rb`<br>
> In-app display name: `AI建模助手`

## 功能亮点

- 对话式建模：先确认尺寸、材质、装配关系和风格，再生成 SketchUp Ruby 代码。
- 整体化建模：提示词和执行器会尽量把新增几何收拢进顶层 Group/Component，避免散成孤立零件。
- DeepSeek 友好：DeepSeek/Coder 模式下不会发送不兼容的 `image_url` 消息，截图和参考图会降级为文字上下文工作流。
- 参考图粘贴：输入框支持粘贴最多 3 张参考图；视觉模型可直接接收图片，不支持视觉的模型会提示用户补充文字描述。
- 安全拦截：执行 AI 代码前会做基础危险调用检查，拦截文件、目录、系统命令、网络、嵌套 `eval` 等高风险操作。
- 一键打包：提供 PowerShell 打包脚本生成 SketchUp 可安装的 `.rbz` 扩展包。

## 下载与安装

推荐从 GitHub Release 下载正式安装包：

[下载 AI+SU.rbz](https://github.com/llghdd-afk/AI-SU/releases/latest/download/AI%2BSU.rbz)

安装步骤：

1. 下载 `AI+SU.rbz`。
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

## 支持的模型

| Provider | 文本建模 | 参考图/截图 | 说明 |
| --- | --- | --- | --- |
| DeepSeek | 支持 | 自动降级为文字上下文 | 推荐用于 coder/Ruby 代码生成。 |
| Gemini | 支持 | 支持视觉模型 | 适合直接分析截图和参考图。 |
| Qwen | 支持 | 取决于模型 | Qwen-VL、Omni、QVQ 等视觉模型可处理图片。 |
| Kimi | 支持 | 取决于接口能力 | 按兼容接口返回能力使用。 |
| 自定义 OpenAI 兼容接口 | 支持 | 取决于模型名称和接口能力 | 可接入本地或第三方兼容服务。 |

## DeepSeek 使用建议

如果你接入的是 DeepSeek，并选择 coder 模型：

- 适合生成 SketchUp Ruby 代码。
- 不适合直接分析截图或参考图，因为当前 DeepSeek OpenAI 兼容接口会拒绝 `image_url` 多模态消息。
- 截图分析和参考图粘贴会自动降级为文字上下文：插件会读取当前模型结构，并提示用户补充图片里的关键造型、尺寸比例和装配关系。

如果你希望 AI 直接看图，请切换到支持视觉输入的模型，例如 Gemini、Qwen-VL 或自定义视觉模型。

## 建模工作流

1. **方案沟通**：描述目标模型、用途、风格和参考信息。
2. **参数确认**：确认尺寸、数量、位置、材质、连接方式和装配关系。
3. **代码生成**：生成 Ruby 代码并放入下方控制台。
4. **人工审阅**：检查 Ruby 控制台中的代码，确认没有不符合预期的操作。
5. **执行整理**：执行代码后，插件会尝试把本次新增对象整理成一个顶层整体对象并选中。

## 隐私与密钥安全

本仓库是公开仓库，不要把真实 API Key 写入 `AI+SU.rb`、README、示例文件或提交历史。

插件设置页输入的 API Key 会通过 SketchUp 的 `Sketchup.write_default` 保存在本机用户配置中，用于运行时请求，不会作为源码或安装包内容上传到 GitHub。

用户输入、当前模型摘要、截图或粘贴的参考图可能会发送给你在插件中配置的模型服务商。请不要向第三方模型发送敏感项目、客户资料、私密空间图纸或未授权的商业信息。

如果误把密钥提交到仓库，请立即撤销提交、清理历史，并在服务商控制台轮换密钥。

## 安全边界

插件会在执行 AI 生成的 Ruby 代码前做基本安全检查，拦截文件、目录、系统命令、网络、嵌套 `eval` 等危险操作。不过 AI 代码执行仍然是高权限本地行为，建议先阅读 Ruby 控制台里的代码，再手动执行。

如果你发现安全问题，请参考 [SECURITY.md](SECURITY.md)，不要把真实密钥、私有图纸或可复现漏洞细节直接发到公开 issue。

## 开发

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

更多贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 项目结构

```text
AI+SU.rb                 # SketchUp 插件入口和主要实现
tools/package.ps1        # 生成 dist/AI+SU.rbz 的打包脚本
dist/AI+SU.rbz           # 当前发布安装包
.github/workflows/ci.yml # 语法检查、打包检查和密钥模式扫描
```

## Roadmap

- 增加更多 SketchUp 版本兼容性验证。
- 增加截图和参考图工作流的演示素材。
- 将单文件实现逐步拆分为更易维护的模块结构。
- 增加自动化 UI 回归测试或 SketchUp 侧 smoke test。

## 许可证

本项目使用 [MIT License](LICENSE)。

## 参考

项目结构和交互方式参考了 SketchUp Ruby 扩展的常见做法，以及同类 AI 辅助 SketchUp 项目中“场景检查、组件操作、Ruby 执行、安装包发布”的组织方式。本仓库不复制第三方项目代码。
