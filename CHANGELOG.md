# Changelog

## 1.2.0 - 2026-05-24

- Added first-class image-understanding workflows for pasted reference images and current SketchUp screenshots.
- Added a `参考图` fallback upload button while keeping chat-box paste as the primary image input path.
- Added `按图建模` for turning pasted effect/reference images into a modeling plan or Ruby code.
- Added `截图修正` for screenshot-guided repair of the current SketchUp model.
- Passed image inputs through to the Responses API as `input_image` parts for the Codex CLI relay provider.
- Added current model context to screenshot analysis and repair requests.
- Added lightweight image resizing before sending pasted/uploaded images to reduce payload size.

## 1.1.0 - 2026-05-24

- Added Xiaomi TokenPlan as a first-class provider with a default China-region OpenAI-compatible endpoint.
- Added Codex CLI relay as a first-class provider using the Responses API.
- Added Responses API request conversion with `reasoning.effort = high` and `store = false` for the Codex CLI relay provider.
- Preserved manually edited provider URLs instead of overwriting them every time settings load.
- Added provider fallback model lists for Xiaomi TokenPlan and Codex CLI relay.
- Updated documentation for Xiaomi TokenPlan and Codex CLI relay setup.

## 1.0.0 - 2026-05-21

- Renamed the release entry file to `AI+SU.rb`.
- Renamed the in-plugin display name to `AI建模助手`.
- Added pre-code clarification rules to reduce premature code generation.
- Added grouped-model rules to the system prompt.
- Added automatic post-execution grouping for newly created top-level entities.
- Fixed SketchUp HtmlDialog JavaScript callback usage.
- Added pasted reference-image support in the input area.
- Added DeepSeek-safe fallback for screenshot/reference-image workflows when the active model does not support vision messages.
- Added repository documentation and a PowerShell packaging script.
