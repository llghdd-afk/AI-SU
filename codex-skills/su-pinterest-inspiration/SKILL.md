---
name: su-pinterest-inspiration
description: Find 10 or more Pinterest-style inspiration directions for a SketchUp or SU white-model screenshot, reverse-engineer design prompts, and prepare effect-render outputs. Use when the user wants Codex, OpenClaw, Qclaw, or another agent to turn a white model into multiple client-proposal render concepts using available tools such as desktop control, browser automation, attached screenshots, Pinterest, AI+SU, or another image-generation workflow.
---

# SU Pinterest Inspiration

## Overview

Run a human-in-the-loop inspiration workflow for SketchUp white models: capture or receive a white-model view, find at least 10 relevant inspiration references, extract transferable design language, and generate saved render prompts/results through the user's own image-generation chain.

Keep AI+SU plugin code separate from this workflow. This skill is portable: it can live inside a project repo for versioning, then be copied into any supported agent skill directory:

- Codex: `~/.codex/skills/su-pinterest-inspiration` or `%USERPROFILE%\.codex\skills\su-pinterest-inspiration`
- OpenClaw/Qclaw global: `~/.openclaw/skills/su-pinterest-inspiration`
- OpenClaw/Qclaw workspace: `<workspace>/skills/su-pinterest-inspiration`

## Operating Rules

- Use the best available control layer for the current runtime:
  - Codex with Computer Use available: operate SketchUp, Chrome, Pinterest, and AI+SU through Computer Use.
  - OpenClaw/Qclaw with desktop/browser tools available: use those native tools instead of Codex Computer Use.
  - No desktop control: ask the user for a white-model screenshot and use text/browser/search/image-generation tools from there.
- For browser-only steps, use the runtime's browser tool when it is available and appropriate. Use the user's already logged-in browser only when that runtime can safely target it.
- Treat Pinterest as an inspiration-discovery UI, not a scraping target. Do not build crawlers, bulk download pins, bypass login walls, solve CAPTCHAs, or evade platform limits.
- Confirm before uploading a local screenshot or project image to Pinterest or any third-party site. Text search and page viewing do not need that upload confirmation.
- Keep the user in control of final inspiration selection. Codex may recommend candidates, but the user or designer should approve the final 10+ directions before rendering.
- Preserve the original SU structure in prompts: camera angle, proportions, openings, columns, ceiling height, and white-model massing are constraints unless the user says otherwise.
- For AI+SU image workflows, prefer pasting the screenshot into the chat box first. Use upload controls only as a fallback.
- Do not copy distinctive copyrighted artwork, logos, branded interiors, proprietary fixtures, or exact Pinterest compositions into final prompts. Extract generic material, lighting, layout, mood, and detailing principles.

## Runtime Decision Tree

1. If the agent can directly control the desktop, capture the current SketchUp view and operate the browser normally.
2. If the agent can browse the web but cannot control SketchUp, ask the user to export or attach the white-model screenshot, then search Pinterest or the web with generated text queries.
3. If the agent cannot browse Pinterest directly, produce the search queries and candidate-evaluation sheet for the user to fill, then reverse prompts from the user's chosen references.
4. If the agent can generate images, run the user's chosen image chain and save results; otherwise stop at high-quality prompts and a ready-to-run generation plan.

## Standard Workflow

1. **Create a run folder.** Use `scripts/create_inspiration_run.py` to make a timestamped folder with `input/`, `inspiration/`, `prompts/`, `outputs/`, and `review/`.
2. **Capture the white model.** If SketchUp is open and the runtime can control the desktop, capture the target view without changing the model. If the user already has a screenshot, place it in `input/` and record it in `manifest.json`.
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

Install into OpenClaw/Qclaw from WSL or Linux:

```bash
./codex-skills/install-openclaw-su-pinterest-inspiration.sh --global
```

Or install into an explicit workspace:

```bash
./codex-skills/install-openclaw-su-pinterest-inspiration.sh --workspace "$HOME/.openclaw/workspace"
```

## Completion Checklist

- The original white-model screenshot is saved or referenced in `input/`.
- `manifest.json` records project, view, target count, source screenshot, and run status.
- There are at least 10 approved inspiration directions or the final answer explains why fewer were possible.
- Each approved direction has a source URL or source note, transfer notes, and a reverse prompt.
- Generated outputs are saved locally when generation was requested and available.
- The final user summary names the run folder and the best 3-5 directions for proposal use.
