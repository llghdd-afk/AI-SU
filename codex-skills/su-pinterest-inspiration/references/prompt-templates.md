# Prompt Templates

## White-Model Analysis Prompt

```text
Analyze this SketchUp white-model screenshot for an interior/exterior design inspiration workflow.

Return:
1. Space type and likely design use.
2. Fixed geometry constraints that should not change.
3. Camera/view constraints.
4. 5-8 searchable structure/style keywords in English.
5. Design opportunities for materials, lighting, ceiling, wall, floor, furniture, landscape, or signage.
```

## Pinterest Search Brief

```text
Based on the white model, generate 3-6 Pinterest search queries.

Rules:
- Put structure and space type first.
- Add style/material terms after structure.
- Prefer English keywords.
- Avoid overly narrow brand names or exact designer names.
- Include one broad query, two structure-similar queries, and two style-diverse queries.
```

## Candidate Note Format

```markdown
# Inspiration NN

- Source URL:
- Local screenshot/crop:
- Structure match:
- Transferable design language:
- Materials:
- Lighting:
- Ceiling/wall/floor ideas:
- Furniture/decor/signage:
- Avoid copying:
- Scores:
  - Structure match:
  - Style transfer:
  - Feasibility:
  - Client suitability:
  - Diversity:
```

## Reverse Prompt Template

```text
Use the provided SketchUp white-model screenshot as the exact spatial base. Preserve the original camera angle, scale, wall/opening positions, columns, circulation, ceiling height, and overall massing. Do not redesign the geometry unless explicitly requested.

Transform the space into [STYLE / PROJECT TYPE] inspired by the reference direction: [TRANSFERABLE DESIGN LANGUAGE].

Apply [MATERIALS] to the main architectural surfaces, [LIGHTING STRATEGY] for atmosphere and depth, [CEILING/WALL/FLOOR DETAILS] for spatial hierarchy, and [FURNITURE/DECOR/SIGNAGE] appropriate for the client proposal.

Render as realistic architectural/interior photography, high detail, natural proportions, clean composition, physically plausible lighting, premium but buildable materials.

Negative prompt: do not change the base layout, do not move major openings or columns, do not add impossible structural elements, do not copy logos, artwork, exact furniture pieces, people, text, watermarks, or the original Pinterest composition.
```

## Final Summary Template

```markdown
Run folder: [path]

Completed:
- White-model input: [path]
- Inspiration directions: [count]
- Prompts: [count]
- Generated outputs: [count or reason unavailable]

Best proposal directions:
1. [Name] - [why it fits the client/model]
2. [Name] - [why it fits the client/model]
3. [Name] - [why it fits the client/model]

Notes:
- [Any Pinterest access, login, generation, or upload limitations]
```

