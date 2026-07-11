# 66TaskLight Usage Provider Adapter

66TaskLight can show usage/quota-like signals from multiple providers, but the
adapter layer is display-only and must stay separate from the main task lamp.

## Current Status

- Codex: enabled through existing sanitized `ui_state.quota`.
- Claude: disabled placeholder.
- Copilot: disabled placeholder.
- OpenAI API: disabled placeholder.

## Safety Rules

- Do not read `~/.codex/auth.json`.
- Do not read prompts, responses, raw logs, cookies, or shell history.
- Do not store provider credentials in this repo.
- Do not call external provider APIs from the default app path.
- External provider executables require an explicit user-owned
  `~/.66tasklight/providers/provider_opt_in.json` allowlist before they run or
  appear in the app. Without it, the default is disabled.
- Provider runners receive `TASKLIGHT_PROVIDER_NETWORK=disabled`, no inherited
  application credentials, and an empty TaskLight-owned `HOME` directory. A
  provider that needs broader access is a separate user-approved integration,
  not a default feature.
- Do not let provider quota change `global_status`, `lamp_status`, task status,
  sounds, hooks, or runtime arbitration.

## Adapter Contract

Every adapter must produce a `UsageProviderSnapshot`:

- `id`
- `display_name`
- `health`
- `quota_text`
- `remaining_percent`
- `is_low_quota`
- `updated_at`
- `diagnostic_only`

The first non-Codex provider implementation must ship with a separate security
review, explicit user opt-in, sanitized storage design, and a dedicated smoke
test proving that the main lamp remains unchanged.
