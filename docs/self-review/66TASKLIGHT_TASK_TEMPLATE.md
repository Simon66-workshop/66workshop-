# 66TaskLight Self-Review Task Template

Use this command after a task finishes:

```bash
python3 script/self-review/run_self_review.py --task-id M3.4 --task-type state_projector --task-type hook_bridge --evidence-profile full --mode final
```

Recommended flow when the working tree is already noisy:

```bash
python3 script/self-review/generate_scope.py \
  --task-id M3.4c \
  --task-type state_projector \
  --task-type hook_bridge \
  --write-scope-file

cat docs/reports/self-review/M3.4c/scope-candidate.md

python3 script/self-review/run_self_review.py \
  --task-id M3.4c \
  --task-type state_projector \
  --task-type hook_bridge \
  --scope-file docs/reports/self-review/M3.4c/self-review-scope.json \
  --evidence-profile full \
  --mode final
```

Scoped review:

```bash
python3 script/self-review/run_self_review.py \
  --task-id M3.4a \
  --task-type state_projector \
  --task-type hook_bridge \
  --scope-file /path/to/self-review-scope.json \
  --evidence-profile full \
  --mode final
```

Optional wrapper:

```bash
./script/self-review/run_self_review.sh --task-id M3.4 --task-type state_projector --task-type hook_bridge --mode final
```

## Checklist

1. Pick the matching `--task-type` values.
2. Prefer `generate_scope.py` first when the working tree already contains unrelated dirty files.
3. Inspect `scope-candidate.md` before converting it into `self-review-scope.json`.
4. Use `--evidence-profile fast|full|release` to match the task cost and evidence depth.
5. Keep the working tree local; do not auto commit or auto push.
6. Let the review collect required checks and optional smoke evidence.
7. Read `final-review.md` before treating the task as accepted.

Recommended scope file:

```json
{
  "task_id": "M3.4a",
  "include": [
    "script/self-review/",
    "config/self-review/",
    "docs/self-review/",
    "script/smoke_self_review.sh"
  ],
  "exclude": [
    "dist/",
    "mac/66TaskLight/.build/",
    "__pycache__/"
  ],
  "reason": "Limit review to Self-Review Arbiter Phase 1 files."
}
```

The report directory also contains `scope-summary.json` for downstream audit
and roll-up jobs.

## Decision Outputs

The engine may emit only:

- `PASS`
- `CONDITIONAL_PASS`
- `REJECT`
- `NEEDS_HUMAN_REVIEW`
- `NO_AUTO_APPLY`
