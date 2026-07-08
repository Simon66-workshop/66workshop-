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

## 66TaskLight Completion Self-Review Rules

After every non-trivial task, complete a self-review before the final response:

1. Re-check the original user goal, hard boundaries, changed files, and runtime
   or test evidence. Do not treat build success alone as product acceptance.
2. Run the narrowest meaningful verification for the actual change. For UI work,
   prefer live-app or preview evidence when practical, not code inspection only.
3. Score the result from 0.0 to 10.0 using a task-specific rubric:
   - goal completion and user-facing behavior
   - regression risk and state/semantic correctness
   - architecture fit with existing project patterns
   - visual polish, accessibility, and interaction quality for UI work
   - test coverage and evidence quality
   - safety boundaries, including no secret reads and no unauthorized trust,
     commit, push, or production action
4. When useful for the task type, compare against relevant GitHub project
   patterns or established open-source architecture/UI references before
   finalizing the rubric. Use current sources when the reference may have
   changed or when the user explicitly asks for research.
5. If the self-score is below 9.8, continue one focused optimization pass before
   handing back, unless blocked by a hard constraint, missing user approval, or a
   risk that should be escalated instead of changed automatically.
6. In the final response, summarize the self-review in boss-readable language:
   score, remaining risk, verification passed, and whether further work is
   recommended. Keep this concise unless the user asks for a full audit.
