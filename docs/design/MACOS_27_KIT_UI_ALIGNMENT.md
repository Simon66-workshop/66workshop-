# 66TaskLight macOS 27 UI Kit Alignment

Status: `evidence_ready`
Source: Figma macOS 27 Community file
Date: 2026-07-09

## Purpose

This note records how 66TaskLight should use the macOS 27 UI Kit as a design
source for future UI polish. The goal is to adopt the kit's native macOS
component language where it improves the app, without turning reference images
into runtime screenshots or weakening 66TaskLight status semantics.

## Current Figma Access Result

Figma file:

`https://www.figma.com/design/2dgs23LHHdmTgIOhkkonUF/macOS-27--Community-`

Observed through the Figma MCP tools:

- Initial `get_metadata` without plugin-page loading exposed `Cover` only.
- Figma Plugin API inspection then confirmed the file has 42 pages, including
  `Materials`, `Text Styles`, `Menu Bar and Dock`, `Menus`, `Popovers`,
  `Buttons`, `Toolbars`, and `Windows`.
- Cover page id: `131:8996`.
- Cover frame id: `197:2631`.
- The cover frame content is a cover image node named
  `Cover - UI Kit - macOS 27`.
- The file currently has no enabled library variable collections.
- The available library list includes Apple's `macOS 27` library, updated
  July 3, 2026, with macOS components, windows, popovers, dialogs, menus,
  desktop templates, system colors, materials, text styles, and vibrancy
  effects.
- Available macOS 27 library key:
  `lk-9b6046629e11db2bbe15e5a3fa0443ecd557a34812bc69997a2b8598852d86fb806d4036ca6c146521c7e1cf898a1e3d46dda55a15bf1f86579794b29480aa80`.

Conclusion: direct component adoption is authorized by the user and real
component nodes are discoverable through Figma Plugin API page inspection. Use
the node index below as the current source of truth for the first 66TaskLight
alignment pass.

## Hard Boundaries

- Do not recreate macOS kit screens by screenshot overlay.
- Do not ship the kit cover art or screenshots as runtime UI.
- Do not copy status semantics from Figma art. 66TaskLight status semantics stay
  in `TaskLightViewModel`, `TaskLightUIState`, Hook Bridge, State Projector, and
  Turn Runtime Arbiter.
- Do not let quota visuals affect `global_status` or `lamp_status`.
- Do not change hooks, trust, auth, provider credentials, or external API access
  while doing visual alignment.
- Do not claim a Figma component was imported unless `get_design_context` or a
  library/component import returned that specific component.

## Component Adoption Rules

When an exact macOS 27 component node is available:

1. Fetch `get_design_context` for the exact node.
2. Fetch `get_screenshot` for the same node.
3. Translate the Figma representation into native SwiftUI/AppKit primitives.
4. Reuse existing 66TaskLight tokens and state helpers before adding new ones.
5. Add an isolated preview fixture for each visible status affected.
6. Run the nearest UI smoke and, when practical, capture live runtime evidence.

When only a broad Figma page or cover is available:

1. Use it as design direction only.
2. Write an explicit visual gap or alignment note.
3. Do not implement pixel-matched controls from screenshots.
4. Ask for a node-specific link or selection before claiming direct adoption.

## 66TaskLight Mapping

### Menu Bar Mini Status Item

Use macOS menu-bar conventions:

- Keep the title compact and glanceable.
- Use one semantic state dot plus concise status text.
- Keep quota secondary and visually separated.
- Menu actions should respond immediately and should not rebuild heavy panels
  synchronously during menu tracking.

Current target:

`● Run 4  ⚡61·94`

Recommended kit references to fetch when available:

- Menu Bar and Dock.
- Menus.
- Pop-up and pull-down buttons.
- Text Styles / Caption.
- Materials / vibrancy.

### Task Radar Popover

Use macOS popover/window card conventions:

- Lightweight glass surface, not the full LuckyCat mascot visual.
- Clear hierarchy: status summary, quota pace, active tasks, hooks doctor,
  replay diagnostics.
- Dense but readable rows.
- No large decorative card inside another card.
- Avoid blocking the menu event loop; heavy data loading must be cached or
  deferred.

Recommended kit references to fetch when available:

- Popovers.
- Windows.
- Lists and Tables.
- Group Boxes.
- Text Fields / Labels.
- Materials.

### Visual State Matrix

Use the matrix as an engineering preview surface, not a user dashboard:

- Show full cat, edge capsule, menu-bar title, radar summary, quota pace, and
  hooks badge across fixed fixtures.
- Include light, dark, and complex backgrounds.
- Include low quota and Pending yellow status readability cases.
- Never rely on static screenshots for the component itself.

Recommended kit references to fetch when available:

- Materials.
- Text Styles.
- Windows.
- Alerts / status surfaces.

### Edge Capsule / Liquid Glass

Keep the existing custom 66TaskLight glass capsule, but align it with macOS kit
material behavior:

- Transparent glass body, not black glass or white plastic.
- Directional rim and cap arcs.
- Separate bottom ellipse shadow from edge thickness.
- Status orb is the primary visual anchor.
- Thread counts and quota remain smaller secondary information.
- Typography must stay readable on bright, dark, and busy backgrounds.

Recommended kit references to fetch when available:

- Materials.
- Color styles.
- Text styles / Caption.
- Windows / popover surfaces.

## Token Translation Draft

These are implementation-facing names for future SwiftUI/AppKit token work.
They do not change runtime behavior by themselves.

| Token | Purpose | SwiftUI/AppKit direction |
| --- | --- | --- |
| `kitWindowGlass` | Radar and floating panel base | `.regularMaterial` or availability-gated native glass |
| `kitPopoverGlass` | Menu/radar popover surface | `.thinMaterial`, soft rim, readable rows |
| `kitMenuHighlight` | Hover/selected menu item | Native `NSMenu` highlight; avoid custom slow hover drawing |
| `kitCaptionPrimary` | Menu/radar compact data | SF Pro caption, semibold, fixed-width digits where needed |
| `kitCaptionSecondary` | Diagnostics and helper text | Lower opacity, never below accessible contrast target |
| `kitDividerSubtle` | Row separation | 1 px vibrancy-aware separator |
| `kitStatusAccent` | State dot/orb rim only | Existing semantic status color, controlled saturation |
| `kitWarningAccent` | Low quota / warning only | Warning chip/text, no main lamp effect |

## Required Evidence Before Runtime UI Changes

For each future macOS 27 kit adoption pass, record:

- Figma node URL or node id.
- Whether `get_design_context` succeeded.
- Whether `get_screenshot` succeeded.
- Which SwiftUI/AppKit component was changed.
- Which fixture states were added or updated.
- Which smoke/build checks passed.
- Whether live app runtime was inspected.

## Discovered Node Index

These nodes were discovered from the macOS 27 Community file and are suitable
for 66TaskLight's next UI-alignment pass. `get_design_context` has already been
run for the rows marked `context=pass`.

| Area | Page id | Node id | Node name | Best use in 66TaskLight | Context |
| --- | --- | --- | --- | --- | --- |
| Materials | `483:8848` | `483:9263` | `Liquid Glass - Small` | Menu bar icon states, small chips, compact glass controls | `pass` |
| Materials | `483:8848` | `483:9237` | `Liquid Glass - Large` | Radar card shell and visual-matrix material reference | `pass` |
| Materials | `483:8848` | `483:9250` | `Liquid Glass - Medium` | Capsule/radar secondary glass surface | `metadata` |
| Materials | `483:8848` | `483:9316` | `Liquid Glass - Light` | Light-background glass readability checks | `metadata` |
| Materials | `483:8848` | `488:17448` | `Liquid Glass - Dark` | Dark-background glass readability checks | `metadata` |
| Materials | `483:8848` | `4331:12157` | `Materials` | Ultra Thin / Thin / Medium / Thick material variants | `metadata` |
| Text Styles | `0:962` | `0:1745` | `Text Styles - Left Aligned - Light Opaque` | Radar/menu typography baseline on light surface | `metadata` |
| Text Styles | `0:962` | `0:1673` | `Text Styles - Left Aligned - Light Vibrant` | Vibrant text on glass surface | `metadata` |
| Text Styles | `0:962` | `0:1603` | `Text Styles - Left Aligned - Dark Opaque` | Dark mode typography baseline | `metadata` |
| Text Styles | `0:962` | `0:1531` | `Text Styles - Left Aligned - Dark Vibrant` | Dark glass/vibrancy text behavior | `metadata` |
| Menu Bar | `207:14475` | `121:13196` | `Menu Bar` | Menu bar mini item layout and density | `metadata` |
| Menu Bar | `207:14475` | `121:13187` | `_Menu Bar/Menu Item / Light` | Light selected/unselected menu-bar item | `metadata` |
| Menu Bar | `207:14475` | `164:9698` | `_Menu Bar/Menu Item / Dark` | Dark selected/unselected menu-bar item | `metadata` |
| Menu Bar | `207:14475` | `4355:8233` | `Dock` | Desktop-template context, not direct runtime UI | `metadata` |
| Menus | `207:14481` | `488:2741` | `Menu` light example | Native menu surface, row rhythm, separators, hover row | `pass` |
| Menus | `207:14481` | `121:12600` | `Menu Items` | Action/submenu/hover/disabled row states | `metadata` |
| Menus | `207:14481` | `4353:2293` | `Menu Background` | Menu glass/background material | `metadata` |
| Popovers | `207:14483` | `4336:13205` | `Popover` light example | Task Radar popover shell reference | `pass` |
| Popovers | `207:14483` | `121:11291` | `Popover` variants | Arrow edge placement variants | `metadata` |
| Windows | `207:14504` | `4374:54811` | `Utility Panel` | Expanded panel / diagnostic panel shape reference | `metadata` |
| Windows | `207:14504` | `4363:18459` | `Windows - Composed` | Window frame and toolbar variants | `metadata` |
| Windows | `207:14504` | `488:17656` | `Window Controls/Standard` | Native window-control sizing reference only | `metadata` |
| Buttons | `207:14487` | `121:11923` | `Buttons` | Over-glass button states for radar actions | `metadata` |
| Buttons | `207:14487` | `4341:8462` | `Buttons - Toggle` | Focus/menu-only toggle visual reference | `metadata` |
| Toolbars | `207:14501` | `121:11848` | `Segmented Control` | Visual matrix filters or radar tabs | `metadata` |
| Toolbars | `207:14501` | `641:1685` | `Pop-Up Button` | Radar filter controls | `metadata` |
| Toolbars | `207:14501` | `177:10807` | `Search` | Future hooks doctor search/filter field | `metadata` |

### Immediate Design Facts From Context Nodes

- Small Liquid Glass is a `48 x 48` control with `Light/Dark`,
  `Active=True/False`, and `State=Default/Primary` variants.
- Large Liquid Glass is a `160 x 160` rounded square, radius about `34`,
  with light/dark modes and distinct fill, rim, and glass-effect layers.
- Menu example uses `12 px` horizontal inset, `5 px` vertical inset, `19 px`
  row height for compact rows, `13 px` SF Pro Medium text, `12 px` radius, and
  subtle material shadow/rim.
- Popover example uses a `200 x 200` content area with a rounded glass shell and
  pointer edge. The node renders the shell as an image asset from Figma; do not
  ship that asset directly. Translate the shape/material behavior into AppKit or
  SwiftUI instead.

## Current 66TaskLight Code Touchpoints

Use these files as the first implementation targets once an exact kit component
node is available:

| Surface | Current code touchpoint | Adoption goal |
| --- | --- | --- |
| Menu bar title/menu | `TaskLightMenuBarController.swift` | Match macOS menu item density, highlight behavior, and instant command response |
| Task Radar | `TaskRadarPopoverView.swift` | Align popover spacing, row rhythm, typography, materials, and diagnostic hierarchy |
| Visual Matrix | `LuckyCatVisualStateMatrixView.swift` | Keep as preview/test surface for kit-aligned states |
| Edge capsule | `LuckyCatEdgeRailView.swift` and related glass primitives | Keep custom identity, align material/typography rules only |
| Shared presentation | `TaskLightViewModel.swift` helpers | Keep all displayed values derived from existing read model |
| Smoke guards | `script/smoke_luckycat_*.sh`, `script/check_ui_client.sh` | Prevent delayed menu interactions, screenshot overlays, and status semantic drift |

## Next Implementation Queue

Once a real menu/popover/window node is available from Figma, implement in this
order:

1. Menu bar menu polish:
   - Native menu highlight must remain instant.
   - Menu commands should only flip lightweight state synchronously.
   - Heavy popover/dashboard content should load outside menu tracking.
2. Task Radar popover polish:
   - Replace any overly dark custom surface with macOS kit-aligned glass.
   - Use compact rows and SF caption/title hierarchy.
   - Keep Hooks Doctor, Quota Pace, and Status Replay visually distinct but not
     card-heavy.
3. Visual Matrix update:
   - Add a macOS kit alignment row for menu, popover, and capsule.
   - Keep low-quota and Pending yellow readability fixtures.
4. Runtime proof:
   - Run UI smoke.
   - Inspect live app after restart.
   - Record whether menu open, mode toggle, and full panel open feel immediate.

## Component Intake Template

Use this checklist when the user points to a macOS 27 kit component:

```text
Figma node URL:
Target 66TaskLight surface:
Component type: menu / popover / window / material / text style / control
MCP get_design_context: pass / fail
MCP get_screenshot: pass / fail
Runtime code files changed:
Preview fixtures updated:
Checks run:
Live app inspected:
Remaining visual gap:
```

## Open Follow-up

To directly bring real macOS 27 components into 66TaskLight, provide one of:

- A node-specific Figma URL for the exact menu, popover, window, material, or
  text style component.
- A selected layer/component in Figma before asking Codex to fetch design
  context.
- A working Figma file where the `macOS 27` library is enabled and the target
  components are placed on a page.

Until then, the kit is a design reference and library availability proof, not a
runtime component source.
