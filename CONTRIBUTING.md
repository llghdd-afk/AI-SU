# Contributing to AI+SU

感谢你愿意改进 AI+SU。这个项目的目标是让 SketchUp 用户用自然语言更稳地生成、审阅和执行建模代码，同时避免散件模型、错误的多模态调用和危险的本地执行行为。

## Development Setup

Requirements:

- SketchUp with Ruby extension support.
- Ruby available on the command line for syntax checks.
- PowerShell 5.1+ or PowerShell 7+ for packaging.

Useful commands:

```powershell
ruby -c .\AI+SU.rb
.\tools\package.ps1
```

## Pull Request Checklist

Before opening a pull request:

- Keep changes focused and avoid unrelated rewrites.
- Run `ruby -c .\AI+SU.rb`.
- Run `.\tools\package.ps1` when packaging behavior changes.
- Do not commit API keys, `.env` files, private SketchUp models, screenshots with sensitive customer data, or generated local settings.
- Update `README.md` or `CHANGELOG.md` when behavior changes for users.
- Prefer conservative changes around AI code execution and model-provider request formats.

## Coding Notes

- `AI+SU.rb` is currently a single-file SketchUp extension for easy installation and packaging.
- Keep UI callback names stable unless the Ruby and JavaScript sides are updated together.
- Treat AI-generated Ruby execution as a security-sensitive path.
- For provider support, prefer graceful fallback over hard failure when a model does not support images.

## Reporting Bugs

Please include:

- SketchUp version and operating system.
- Provider and model name, with all keys redacted.
- What you asked the plugin to generate.
- Expected result versus actual result.
- Error message or screenshot if safe to share.

Never paste a real API key into an issue or pull request.
