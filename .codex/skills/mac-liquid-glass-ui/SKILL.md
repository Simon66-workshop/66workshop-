---
name: mac-liquid-glass-ui
description: Design, implement, review, or refine macOS SwiftUI/AppKit Liquid Glass visual components, especially compact floating widgets, capsules, edge rails, glass cards, status orbs, quota/status displays, and screenshot-backed UI polish. Use when a task asks for Apple-style glass, macOS 3D translucent cards, rounded glass edges, refraction, readable text on glass, drag/click behavior, or regression checks for visual components.
---

# Mac Liquid Glass UI

## Core Rule

Build the component from native SwiftUI/AppKit drawing primitives, design tokens, gradients, masks, materials, and typed props. Do not recreate reference images by screenshot overlay or static art. Keep status semantics in code.

## Workflow

1. Identify the component state model before drawing: status values, counts, quota, interaction mode, collapsed/expanded mode, and persisted window state.
2. Separate behavior from visual treatment. Do not change status algorithms, quota sources, hooks, projectors, or business semantics while polishing glass UI unless explicitly requested.
3. Build glass as layers, not a single frosted rectangle.
4. Make the content readable before increasing glass effects.
5. Preserve interaction quality: click/toggle and drag must be split, and window movement must use native AppKit frame/drag behavior where possible.
6. Validate with build checks, targeted smoke tests, and screenshots across meaningful states.

## Liquid Glass Layer Stack

Use this stack for macOS floating cards and vertical capsules:

- Background lift: clean the sampled environment visually with brightness and saturation, but avoid opaque white fill.
- Main glass fill: translucent white/blue-white fill plus blur/material fallback.
- Edge thickness: top/left highlights, right/bottom cut depth, inner rim, and cap arcs. Treat thickness as edge distance/light behavior, not a heavy box shadow.
- Refraction/highlight: direction-aware sweeps, Fresnel-like rim light, bottom lens/refraction, and subtle internal diffusion.
- Content glass: status orb, title, counts, and quota get their own readable micro-surfaces instead of sitting directly on noisy glass.

Prefer explicit top/bottom cap arcs for narrow vertical capsules. Avoid flat clipped ends.

## Edge And Shadow Rules

- Keep outer shadows off the card body when corners get dirty. Use separate bottom-centered elliptical float/contact shadows.
- Split edge effects into directional strips: top, left, bottom, right. Do not let top/left highlights or bottom/right darkening accumulate in rounded corners.
- Add corner attenuation when edge effects overlap: straight edges should stay bright; corners should not become gray, white, or dirty.
- Use cold gray-blue for depth shadows, never pure black.
- Keep right/bottom dark edges subtle. If they read as plastic shell, reduce opacity and move depth into rim/refraction.

See `references/liquid-glass-parameters.md` for parameter ranges and SDF-style pseudocode.

## Status Orb Pattern

For a premium status orb, use six layers:

- Contact shadow: small bottom ellipse.
- Body: offset radial gradient with top light and deeper bottom hue.
- Inner glow: soft lens haze.
- Caustic: subtle internal bright patch.
- Highlights: large elliptical main highlight plus a smaller secondary highlight.
- Rim: thin semi-transparent white refraction ring plus semantic color glow.

Keep the glass body blue-biased for Running, but expose semantic states through controlled accent/rim/wash colors. Do not tint the whole orb yellow/red/green at high opacity.

## Typography And Data Readability

- Add local readability haze behind titles instead of strengthening text shadow until it blurs.
- Use fixed-width digits for quota and counters.
- Keep status text saturated enough to scan, but avoid candy colors.
- For count panels, use label/value contrast: labels lower opacity, values higher opacity and weight.
- For quota chips, reserve color for meaning: normal numbers high-contrast light or dark depending on surface; low quota can turn red.

## Interaction And Window Behavior

- Split click and drag. A click toggles; a press that moves beyond threshold drags.
- Avoid SwiftUI click catchers that steal native dragging from a floating panel.
- Do not use delayed single-click schedulers for core toggle paths if the user expects millisecond response.
- Keep collapsed edge rails independently draggable unless the product explicitly requires side docking.
- Persist drag positions only after drag end or debounce; do not write state continuously during drag.
- For startup placement, decide separately from runtime restore. If the product wants a default visible position, make startup frame explicit and traceable.

## Validation

Run the nearest available checks:

- `swift build`
- component-specific atomic smoke
- component-specific runtime smoke
- UI client/app launch check
- full check-all when the change touches shared UI/window behavior

For visual acceptance, produce screenshots or screenshot strips across all visible statuses and at least one dark and one light/background context. Passing tests is not enough to claim visual quality.

## Review Checklist

- No screenshot overlay/static art.
- Status and quota semantics unchanged.
- Text readable on light and dark backgrounds.
- Corners clean: no dirty shadow, clipped caps, or gray highlight piles.
- Edges have thickness without plastic heaviness.
- Orb looks dimensional across semantic states.
- Click, drag, collapse, restore, and startup placement still work.
- Smoke guards protect the visual decisions that previously regressed.
