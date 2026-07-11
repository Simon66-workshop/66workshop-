# Codex Quota Widget

M3.6 adds a local Codex usage widget for LuckyCat. Quota is display-only: it never changes `global_status`, `lamp_status`, `global_display_title`, task status, sounds, or hook/runtime arbitration.

## Data Flow

```text
Codex App Server account/rateLimits/read
Codex App Server account/rateLimits/updated
manual text / clipboard / file fallback
        -> quota_state.json
        -> state_projector.py
        -> ui_state.quota
        -> LuckyCat compact + expanded dashboard
```

The preferred source is local Codex App Server. The short probe reads `account/rateLimits/read`; the watcher prefers `account/rateLimits/updated` and falls back to bounded polling when local notifications are unavailable. Manual and clipboard import exist as fallback. OCR, cookie scraping, keychain reads, auth-file reads, external API calls, purchases, and automatic resets are out of scope.

## Commands

```bash
python3 script/codex_quota_appserver_probe.py
python3 script/codex_quota_appserver_watcher.py --once
python3 script/codex_quota_appserver_watcher.py --watch
./script/install_codex_quota_watcher_launch_agent.sh
./script/check_codex_quota_watcher_launch_agent.sh
./script/uninstall_codex_quota_watcher_launch_agent.sh
python3 script/codex_quota_reset_credits_probe.py --fixture /path/to/sanitized-reset-credits.json
python3 script/codex_quota_import.py --text "5小时 93% 11:44
1周 42% 6月18日
1次可用重置"
python3 script/codex_quota_import.py --from-clipboard
python3 script/codex_quota_import.py --input-file /path/to/usage.txt
./script/check_codex_quota.sh
```

## Percent Semantics

App Server reports `usedPercent`, so TaskLight converts it to remaining percent:

```text
remaining_percent = 100 - usedPercent
```

Manual Usage text is treated as already being remaining percent. This avoids reversing dashboard values such as `5小时 93%`.

## Display Rules

Compact examples:

```text
⚡ 93 · 42 · R1
⚡ 93 · 42
⚡ 42%
⚡ Q?
```

Expanded dashboard shows short window, long window, reset count, quota status, source, capture time, and recommendation.

M3.7 adds a small compact freshness dot:

- green dot: quota is fresh.
- gray dot: quota is stale or missing.
- the dot does not affect `RUNNING`, `BLOCKED`, `PENDING`, or `DONE`.

Expanded dashboard also shows `captured_at`, `bucket_id`, probe mode, and raw bucket count so the value can be compared against the Codex Usage UI.

## Reset Credits

M5 adds a sanitized reset-credit fixture importer for the Codex reset counter.
It accepts only a local sanitized fixture and normalizes records to stable display fields:

- `status`
- `issued_at`
- `issued_date`
- `expires_at`
- `expiry_date`
- `redeemed`

Derived fields:

- `total_count`
- `available_count`
- `used_count`
- `expired_count`
- `next_expiry`

`expires_at` is kept as the precise local ISO timestamp and is the source for
the UI's "最迟有效期 M月d日 HH:mm" display. `expiry_date` remains only a date
compatibility field and must not be used when the precise timestamp exists.

Only normalized reset metadata is saved under `manual_resets`; tokens, account
ids, prompts, responses, auth material, and raw API bodies are never read or
written by this importer. Reset credits are diagnostic quota
metadata only; they do not affect `global_status`, `lamp_status`, task status,
or any reset/redeem action.

## Burn-Rate Prediction

M4/M5 adds a display-only burn-rate panel in Task Radar. It uses sanitized
samples from `~/.66tasklight/quota_history.jsonl`:

- `captured_at`
- `window_id`
- `bucket_id`
- `remaining_percent`
- `reset_label` / `reset_at`
- `source`
- `fresh`

Prediction rules:

1. At least 3 valid samples are required before showing `%/hour`.
2. If remaining percent increases after a reset, the baseline restarts from that
   newer sample.
3. Estimated empty time is capped at the next reset time when reset metadata is
   available.
4. Confidence is surfaced as `insufficient`, `warming`, `stable`, or `stale`.
5. Low quota warnings affect only quota text/chips, never the main lamp.

Confidence semantics:

```text
insufficient  fewer than 3 usable samples
warming       enough to estimate, but too new or sparse
stable        enough samples over a wider window
stale         newest sample is older than the freshness window
```

Quota health:

```text
>= 50    ok
20-49    watch
5-19     low
< 5      critical
missing  unknown
```

`effective_remaining_percent` is the minimum remaining percent across valid `display_windows`.

## Quota Calendar

M6 adds a display-only calendar in Task Radar. It orders upcoming window resets
and each unredeemed reset credit's precise expiry time. Entries within 24 hours
are marked `attention`; entries within 72 hours are marked `warning`. These are
local diagnostic reminders only: they never trigger a reset, redeem a credit,
change `global_status`, or change `lamp_status`.

## Quota State Schema

`quota_state.json` stores two window sets:

- `raw_windows[]`: every sanitized codex-like bucket from App Server or manual input.
- `display_windows[]`: the windows selected for UI display.

When multiple buckets share a duration, display selection is:

1. `bucket_id == "codex"`
2. account-level codex-like bucket
3. model-specific bucket such as `codex_bengalfox`
4. conservative fallback

`windows[]` remains a backwards-compatible alias for `display_windows[]`.

## Safety

Quota state is a sidecar at `~/.66tasklight/quota_state.json`. Projector copies a sanitized view to `ui_state.quota`. If quota is missing, stale, or invalid, LuckyCat shows `⚡ Q?` and the main lamp stays governed only by task/runtime state.
