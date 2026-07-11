#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANEL="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightApp/TaskLightPanelController.swift"
MACHINE="$ROOT_DIR/mac/66TaskLight/Sources/TaskLightCore/TaskLightInteractionStateMachine.swift"

rg -q "TaskLightInteractionStateMachine" "$PANEL" "$MACHINE"
rg -q "NSEvent.mouseEvent" "$PANEL"
rg -q "cross_surface_double_tap_opened_diagnostics" "$PANEL" "$ROOT_DIR/script/build_and_run.sh"

"$ROOT_DIR/script/build_and_run.sh" --interaction-event-replay-self-test

echo "smoke_tasklight_interaction_event_replay=ok"
echo "STATUS=ok"
