# Mission Control Local Demo

This is the local runbook for a live hackathon presentation and video capture.
It assumes NullHub is running locally and does not require hosted services,
model keys, or external infrastructure.

## Start NullHub

```bash
zig build run -- serve --host 127.0.0.1 --port 19802 --no-open
```

Open:

```text
http://127.0.0.1:19802/mission-control
```

## Run The Judge-Mode Demo

From `/mission-control`, click `Judge Replay` to run the same deterministic
reset, launch, failure hold, checkpoint fork, and recovered replay sequence from
the UI.

In a second terminal:

```bash
MISSION_CONTROL_OPEN_BROWSER=1 ./scripts/mission_control_demo.sh
```

The script resets the mission, launches the local replay, waits for the
validation failure, forks from the checkpoint, waits for recovered completion,
verifies that the failed and recovered timeline events carry trace refs, and
checks that `/api/mission-control/replay` exports a completed artifact.

## Export A Replay Artifact

The current Mission Control state can be exported as JSON:

```bash
curl -fsS http://127.0.0.1:19802/api/mission-control/replay \
  -o mission-control-replay.json
```

The same export is available from the `Save Replay` button in the UI. The
button also persists a durable copy under `~/.nullhub/mission-control/replays/`.
The artifact contains the current snapshot, the source fixture, and the
ecosystem mapping used to explain the local replay.

## Record A Local Video

On macOS:

```bash
./scripts/record_mission_control_demo.sh
```

The script opens `/mission-control`, records the screen with
`screencapture`, and drives the mission automatically. The default output is:

```text
docs/demo/nullhub-mission-control-demo.mov
```

The video file is intentionally ignored by git because it is a local review
artifact. Upload it directly to the hackathon submission or PR discussion.

If macOS asks for Screen Recording permission, allow it in System Settings and
rerun the command.

## Presenter Script

1. Show that the demo is local-first: one NullHub server, no external services.
2. Click `Judge Replay` and call out the role board, workflow graph, and
   telemetry as the mission advances.
3. Pause at the failure: the test tool fails, errors increment, and recovery is
   blocked until the failure phase.
4. Click or let the script trigger checkpoint recovery.
5. Show the recovered run, passing eval verdict, and trace links into NullWatch
   Flight Recorder via `/nullwatch?run_id=...`.
6. Export the replay artifact to show the scenario can be reviewed after the
   live demo.

## Pre-Demo Quality Gate

```bash
zig build test -Dembed-ui=false --summary all
npm --prefix ui run build
zig build test --summary all
NULLHUB_URL=http://127.0.0.1:19802 ./tests/test_mission_control_smoke.sh
MISSION_CONTROL_OPEN_BROWSER=1 ./scripts/mission_control_demo.sh
```
