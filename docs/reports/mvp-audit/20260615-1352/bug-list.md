# Bug List

| Priority | Title | Evidence | Impact | Recommendation | Blocks MVP |
| --- | --- | --- | --- | --- | --- |
| P0 | ./script/check_all.sh did not pass | Traceback + KeyError: 'total' in check_all substep | MVP validation cannot be treated as fully clean. | Review failing check output in a controlled developer follow-up. | yes |
| P1 | 29 workspaces are missing hooks | workspace_coverage latest summary | 66TaskLight cannot reliably observe all discovered workspaces. | Onboard preferred workspaces first, then manually trust hooks in Codex UI. | no |
