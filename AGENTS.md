## 66VS UI Engineering Rules

For visual UI components, do not recreate reference images by screenshot overlay.

When implementing a UI from a visual reference:
1. Treat reference images as non-runtime assets.
2. Build components from typed props, SVG/CSS or native drawing primitives, and design tokens.
3. Add isolated preview states for every visible status.
4. Keep status semantics in code, not in static art.
5. If the target effect cannot be expressed with existing primitives, document the visual gaps instead of faking them with images.
