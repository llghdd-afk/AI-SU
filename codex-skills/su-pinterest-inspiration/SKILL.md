---
name: su-pinterest-inspiration
description: Find 10 or more Pinterest-style inspiration directions for a SketchUp or SU white-model screenshot, reverse-engineer design prompts, and prepare effect-render outputs. Use when the user wants Codex to operate SketchUp, a browser, Pinterest, AI+SU, or another image-generation workflow with Computer Use to turn a white model into multiple client-proposal render concepts.
---

# SU Pinterest Inspiration

## Overview

Run a human-in-the-loop inspiration workflow for SketchUp white models: capture or receive a white-model view, find at least 10 relevant inspiration references, extract transferable design language, and generate saved render prompts/results through the user's own image-generation chain.

Keep AI+SU plugin code separate from this workflow. This skill is portable: it can live inside a project repo for versioning, then be copied into `~/.codex/skills/su-pinterest-inspiration` or `%USERPROFILE%\.codex\skills\su-pinterest-inspiration` on another Codex machine.

## Operating Rules

- Use Computer Use for SketchUp, local desktop windows, and any workflow that depends on the user's visible Windows session.
- For browser-only steps, use the Browser plugin when it is available and appropriate; use Computer Use when the user explicitly asks for it or when the desktop browser state matters.
- Treat Pinterest as an inspiration-discovery UI, not a scraping target. Do not build crawlers, bulk download pins, bypass login walls, solve CAPTCHAs, or evade platform limits.
- Confirm before uploading a local screenshot or project image to Pinterest or any third-party site. Text search and page viewing do not need that upload confirmation.
- Keep the user in control of final inspiration selection. Codex may recommend candidates, but the user or designer should approve the final 10+ directions before rendering.
- Preserve the original SU structure in prompts: camera angle, proportions, openings, columns, ceiling height, and white-model massing are constraints unless the user says otherwise.
- For AI+SU image workflows, prefer pasting the screenshot into the chat box first. Use upload controls only as a fallback.
- Do not copy distinctive copyrighted artwork, logos, branded interiors, proprietary fixtures, or exact Pinterest compositions into final prompts. Extract generic material, lighting, layout, mood, and detailing principles.

## Standard Workflow

1. **Create a run folder.** Use `scripts/create_inspiration_run.py` to make a timestamped folder with `input/`, `inspiration/`, `prompts/`, `outputs/`, and `review/`.
2. **Capture the white model.** If SketchUp is open, use Computer Use to capture the target view without changing the model. If the user already has a screenshot, place it in `input/` and record it in `manifest.json`.
3. **Analyze the structure.** Identify space type, camera angle, dominant geometry, circulation, openings, ceiling/wall/floor zones, scale cues, and design constraints.
4. **Generate search briefs.** Produce 3-6 Pinterest search phrases that describe structure and use-case first, then style. Prefer English search terms, with Chinese notes if helpful.
5. **Search Pinterest.** Browse results with text queries first. Use visual search/upload only after action-time confirmation because it transmits the user's image.
6. **Collect 10+ candidates.** For each candidate, save the URL when available, a short note, and a local screenshot/crop only when obtained through normal viewing. Aim for structural similarity plus style diversity.
7. **Score and shortlist.** Rate candidates on structure match, style transfer value, client suitability, feasibility, and diversity. Avoid choosing ten near-duplicates.
8. **Reverse-engineer prompts.** Convert each selected inspiration into a prompt that keeps the SU white-model structure and borrows only general design language.
9. **Generate outputs.** Use AI+SU or the user's chosen image chain. Save each generated render into `outputs/` with matching prompt files in `prompts/`.
10. **Review deliverables.** Ensure the run has at least 10 inspiration entries, 10 prompts, generated outputs if requested, and a concise summary for the user.

## When To Load References

- Read `references/workflow.md` before executing a real Pinterest/Computer Use run.
- Read `references/prompt-templates.md` when drafting search queries, scoring candidates, reverse prompts, or the final summary.
- Read the helper script only if it fails or needs adjustment for a different machine.

## Helper Script

Create a run folder:

```powershell
python .\codex-skills\su-pinterest-inspiration\scripts\create_inspiration_run.py --project "client-lobby" --view "main-view"
```

Useful options:

```powershell
python .\codex-skills\su-pinterest-inspiration\scripts\create_inspiration_run.py `
  --root "D:\AI-SU-runs" `
  --project "showroom" `
  --view "entrance-perspective" `
  --target-count 12 `
  --source-screenshot "C:\path\white-model.png"
```

After creation, update `manifest.json` as the workflow proceeds. Keep file names aligned by index, for example `prompts/01_prompt.md`, `outputs/01_render.png`, and `inspiration/01_source.txt`.

## Completion Checklist

- The original white-model screenshot is saved or referenced in `input/`.
- `manifest.json` records project, view, target count, source screenshot, and run status.
- There are at least 10 approved inspiration directions or the final answer explains why fewer were possible.
- Each approved direction has a source URL or source note, transfer notes, and a reverse prompt.
- Generated outputs are saved locally when generation was requested and available.
- The final user summary names the run folder and the best 3-5 directions for proposal use.
