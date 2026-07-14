# TaskLight Storage Lifecycle

TaskLight keeps the active read model under `~/.66tasklight` and treats archive
maintenance as a separate, explicit operation.

## Safety Contract

- Default mode is report-only/dry-run.
- `running`, `queued`, `blocked`, `stale`, and `done_unverified` are protected.
- Active, pending, or open-blocker files are never archived.
- Archive destinations are under `~/.66tasklight/archive/` and preserve the
  source filename and UTC month partition.
- No auth, credential, prompt, response, or raw log body is read for decisions.
- No task status, lamp status, quota, trust, purchase, or reset action is changed
  by the audit command.

## Commands

Read-only baseline:

```bash
python3 script/tasklight_storage_audit.py \
  --output-json /tmp/tasklight-storage.json \
  --output-md /tmp/tasklight-storage.md
```

Preview archive candidates:

```bash
python3 script/tasklight_storage_maintenance.py --report-only
```

Apply archive moves only after human review:

```bash
python3 script/tasklight_storage_maintenance.py --apply
```

`--apply` moves only eligible completed/cancelled/released records. It does not
permanently delete files and does not alter the primary status projector.
