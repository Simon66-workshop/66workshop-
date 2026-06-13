# Codex Workspace Onboarding

66TaskLight can only follow a Codex workspace reliably when that workspace has
trusted project hooks or fresh high-confidence appserver evidence. A hook setup
inside this 66TaskLight project does not automatically cover other Codex
projects.

## Commands

Run a read-only batch report:

```bash
./script/check_codex_workspaces_coverage.sh
```

Install hooks into preferred/common workspaces first:

```bash
./script/install_hooks_for_workspaces.sh --preferred
```

Install only preferred workspaces that the latest report says are missing or invalid:

```bash
./script/install_hooks_for_workspaces.sh --from-report
```

Install every discovered workspace only after reviewing the report:

```bash
./script/install_hooks_for_workspaces.sh --all-discovered
```

Install one workspace:

```bash
./script/install_hooks_for_workspaces.sh --workspace "/path/to/project"
```

## LuckyCat Nose Shortcut

Triple-click the LuckyCat nose to run the read-only batch report and open the
latest Markdown report. This shortcut does not install hooks, does not trust
hooks, and does not write task state.

The small bubble near the cat feet shows report status only:

- `正在检查 Codex 项目...`
- `发现 2 个项目需要 Trust`
- `有 1 个项目缺 hooks`
- `状态入口正常`

The bubble is not part of the main lamp state. It never changes
`RUNNING`, `BLOCKED`, `PENDING`, or `DONE`.

## Workflow

1. Triple-click the cat nose to generate a report.
2. Run batch install for preferred `missing_hooks` or `invalid_hooks` workspaces.
3. Open each affected Codex workspace and approve hooks in the Codex UI.
4. Triple-click the cat nose again to confirm coverage.

## Preferred vs Discovered

The report can discover many old, archived, copied, or experimental workspaces.
Those are useful diagnostics but not the same as reliable coverage.
When a workspace is listed as `hidden_not_loaded`, its hooks file exists but the
Codex UI has not loaded that workspace yet. That is different from
`visible_untrusted`, which means the workspace is open in Codex but still needs a
manual Trust click.

- `preferred`: common projects to onboard first.
- `discovered_non_preferred`: visible candidates, usually install only on demand.
- excluded paths: backups, archives, build outputs, and caches.

Edit `config/workspace_coverage.json` to adjust preferred workspaces and exclude
patterns.

## Boundaries

- No external API calls.
- No `~/.codex/auth.json` reads.
- No prompt, response, auth, or raw log body output.
- No automatic Trust bypass.
- No task state writes from the batch report.
