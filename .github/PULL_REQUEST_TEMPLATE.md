## Summary

Describe the change and the user-facing behavior it affects.

## Validation

- [ ] `ruby -c .\AI+SU.rb`
- [ ] `.\tools\package.ps1` if packaging behavior changed
- [ ] Manual SketchUp smoke test if UI, callbacks, model creation, or execution changed

## Safety

- [ ] No API keys, `.env` files, private drawings, or customer data are included
- [ ] AI-generated Ruby execution behavior was reviewed if touched
- [ ] Provider request payload changes were checked for DeepSeek/non-vision fallback behavior if touched

## Notes

Add screenshots, logs, or migration notes when useful. Redact secrets before attaching anything.
