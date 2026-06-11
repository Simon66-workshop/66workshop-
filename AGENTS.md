## 66VS UI Engineering Rules

For visual UI components, do not recreate reference images by screenshot overlay.

When implementing a UI from a visual reference:
1. Treat reference images as non-runtime assets.
2. Build components from typed props, SVG/CSS or native drawing primitives, and design tokens.
3. Add isolated preview states for every visible status.
4. Keep status semantics in code, not in static art.
5. If the target effect cannot be expressed with existing primitives, document the visual gaps instead of faking them with images.

## 66TaskLight Current Codex Status Rules

When working in this repository from Codex and `CODEX_THREAD_ID` is available:
1. Bind the current session with `script/codex_current_task.sh start --title "<work title>" --phase "<phase>" --progress "<0-1>"` before meaningful work.
2. Send `script/codex_current_task.sh heartbeat --phase "<phase>" --progress "<0-1>"` during long work so the desktop light reflects the real active task.
3. Use `script/codex_current_task.sh block --reason needs_human_review --message "<message>" --evidence "<evidence>"` for real blockers.
4. Use `script/codex_current_task.sh done --summary "<summary>"` only when implementation work is complete; use `verify` only after the requested acceptance checks have actually passed.
5. Use `script/codex_current_task.sh clear` when the session should stop advertising an active managed task.
6. Before a final response, leave the binding in a terminal or cleared state; do not leave a managed task running after active work has stopped.
