# Detailed Workflow

## 1. Prepare

Start by creating a run folder with the helper script. Use a neutral project slug if the user does not provide one. If the user wants to work from an existing screenshot, copy it into `input/`; if they want a fresh SketchUp capture, use Computer Use to inspect SketchUp and capture the viewport.

Before any browser action, clarify the search mode:

- **Text search mode:** search Pinterest with generated keywords. This is the default and does not upload the user's project image.
- **Visual search mode:** upload or paste the white-model screenshot into Pinterest visual search. Ask for action-time confirmation because the local image is transmitted to Pinterest.

## 2. Capture and Analyze the White Model

Record these facts in notes or the manifest:

- Project/view name and screenshot path.
- Space type: lobby, retail, exhibition, office, restaurant, villa, facade, etc.
- Geometry: linear, L-shaped, atrium, double-height, arch, curved wall, exposed columns, grid ceiling, stair, mezzanine.
- Camera: eye-level, bird's-eye, one-point perspective, corner perspective, elevation-like.
- Fixed constraints: openings, windows, doors, columns, ceiling height, primary circulation, client-required zones.
- Design opportunities: feature wall, ceiling treatment, material transition, lighting rhythm, greenery, display system, signage, furniture.

## 3. Generate Pinterest Queries

Generate 3-6 search phrases. Put structure before style. Examples:

- `narrow modern showroom interior linear ceiling warm wood stone`
- `small lobby white walls curved reception desk indirect lighting`
- `retail interior exposed columns microcement floor wood slat ceiling`
- `minimal exhibition space arch opening track lighting concrete`

Use broad queries first. Add style terms only after finding structurally similar results.

## 4. Browse Pinterest

Use normal viewing behavior:

- Open Pinterest search results.
- Scroll gradually and inspect visible cards.
- Open promising pins in new tabs/windows only when needed to get a URL or larger view.
- Do not bulk-download images.
- Do not scrape hidden page data.
- Do not bypass login prompts, CAPTCHAs, paywalls, or safety interstitials.
- If login is required and not already approved, ask the user to handle login.

For each candidate, capture:

- Index number.
- Source URL or a source note if the URL is unavailable.
- Screenshot/crop path when practical.
- Why it matches the SU structure.
- What design language can transfer.
- What must not be copied exactly.

## 5. Candidate Scoring

Score candidates from 1-5:

- **Structure match:** similar massing, opening rhythm, perspective, or circulation.
- **Style transfer value:** useful materials, lighting, ceiling/wall/floor language.
- **Feasibility:** plausible to apply to the white model without rebuilding the whole scene.
- **Client suitability:** appropriate for the project type and likely proposal tone.
- **Diversity:** contributes a distinct direction compared with the other picks.

Shortlist at least 10. If there are too many similar pins, keep the strongest one and search for a different style family.

## 6. Reverse Prompts

For each approved inspiration, write a prompt that:

- Starts with preserving the original white-model structure and camera.
- Adds material palette, lighting, architectural details, furniture, decor, and mood.
- Avoids direct copying of identifiable copyrighted or branded elements.
- Specifies realistic interior photography, render quality, and no geometry drift.
- Includes a short negative prompt for unwanted changes.

Save each prompt as `prompts/NN_prompt.md`.

## 7. Generate and Save Outputs

Use the user's chosen generation chain:

- If AI+SU is available, prefer pasting the screenshot into the chat box and sending the prompt there.
- If the user has a different image generator, adapt the prompt format but keep the white-model constraints.
- Save each result as `outputs/NN_render.png` or the actual returned extension.
- If generation fails, save the error note in `outputs/NN_error.txt` and continue with the next prompt when reasonable.

## 8. Final Review

Before finishing, check:

- The count of approved inspiration directions is at least the requested target.
- Each result can be mapped back to its prompt and inspiration note.
- The final summary is usable by a designer: name the strongest directions, not only file paths.

