# 66TaskLight Scope Generator

`generate_scope.py` is the local candidate builder for scoped self-review.
It inspects the current git diff, classifies changed files, and recommends what
the next self-review should include.

It is intentionally conservative:

- local only
- candidate only
- no auto apply
- no auto commit
- no auto push
- no external API

## CLI

```bash
python3 script/self-review/generate_scope.py \
  --task-id M3.4c \
  --task-type state_projector \
  --task-type hook_bridge \
  --write-scope-file
```

Useful flags:

- `--output-dir <path>` writes the candidate files somewhere else
- `--format json|md|both` controls what gets written
- `--write-scope-file` emits `self-review-scope.json`
- `--scope-name <name>` changes the generated scope file name
- `--include-current-staged` and `--include-unstaged` keep the source
  selection explicit in the report metadata

## Outputs

The default output directory is `docs/reports/self-review/<task-id>/`.

Written files:

- `scope-candidate.json`
- `scope-candidate.md`
- `<scope-name>.json` when `--write-scope-file` is used

## Classification

The generator classifies each changed file into:

- in-scope candidates
- out-of-scope candidates
- risky launch/trust files
- risky auth/secret files
- build artifacts
- cache artifacts
- docs assets
- app assets
- unknown

Decision rules:

- auth/secret files force `REJECT`
- launch/trust files force `NEEDS_HUMAN_REVIEW`
- ordinary out-of-scope dirty files keep the candidate at `CONDITIONAL_PASS`
- clean in-scope candidates with no risky out-of-scope files can be `PASS`

## Recommended Flow

1. Run `generate_scope.py`.
2. Inspect `scope-candidate.md`.
3. If the candidate looks right, use the generated scope file with
   `run_self_review.py`.

Example:

```bash
python3 script/self-review/generate_scope.py \
  --task-id M3.4c \
  --task-type state_projector \
  --task-type hook_bridge \
  --write-scope-file

python3 script/self-review/run_self_review.py \
  --task-id M3.4c \
  --task-type state_projector \
  --task-type hook_bridge \
  --scope-file docs/reports/self-review/M3.4c/self-review-scope.json \
  --evidence-profile full \
  --mode final
```
