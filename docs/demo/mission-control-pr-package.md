# Mission Control PR Package

This file is the copy-ready review package for the NullOS Mission Control
hackathon contribution.

## Suggested PR Title

Add NullOS Mission Control local agent recovery demo

## Suggested PR Description

Adds a local-first Mission Control demo to NullHub: a three-minute control-room
experience for lightweight agent infrastructure.

The demo shows a deterministic agent mission from launch to failure, human
checkpoint recovery, recovered validation, review, trace links, telemetry, and
replay export. It is designed to run locally without hosted services, model
keys, or external infrastructure.

What changed:

- Added `/api/mission-control/*` for mission state, reset, launch, recovery,
  and replay export.
- Added a Mission Control domain/state-machine layer in
  `src/core/mission_control.zig` and kept `src/api/mission_control.zig` as the
  HTTP adapter.
- Added a versioned replay fixture at
  `src/core/mission_control/code_red.v1.json`.
- Added replay fixture parsing and validation in
  `src/core/mission_control_replay.zig`.
- Added `/mission-control` UI with mission controls, role board, workflow
  graph, telemetry, timeline, trace links, story beats, and failed-vs-recovered
  comparison.
- Added deep links from mission events to `/observability?run_id=...`.
- Hydrates failure/recovery trace panels from a running NullWatch instance via
  the existing observability proxy when live run detail is available, with
  embedded replay refs as the fallback.
- Added local smoke test, judge-mode demo driver, macOS video recorder,
  screenshots, README docs, and hackathon submission notes.

Why:

NullHub already acts as the control plane for the nullclaw ecosystem, and the
surrounding repositories already sketch out runtime, orchestration, task state,
and observability. What was missing was a memorable local vertical slice that
lets reviewers see those concepts working as one operator experience.

This PR keeps the demo deterministic and honest: it does not pretend to mutate
real NullTickets, NullBoiler, NullClaw, or NullWatch services. Instead it
provides a stable local replay with explicit ecosystem mapping and a future path
for real service hydration.

Validation performed:

```bash
zig build test -Dembed-ui=false -Dbuild-ui=false --summary all
npm --prefix ui run build
zig build test --summary all
zig build test-integration -Dembed-ui=false -Dbuild-ui=false --summary all
NULLHUB_URL=http://127.0.0.1:19802 ./tests/test_mission_control_smoke.sh
NULLHUB_URL=http://127.0.0.1:19802 MISSION_CONTROL_OPEN_BROWSER=0 ./scripts/mission_control_demo.sh
git diff --check
```

Demo:

```bash
zig build run -- serve --host 127.0.0.1 --port 19802 --no-open
MISSION_CONTROL_OPEN_BROWSER=1 ./scripts/mission_control_demo.sh
```

Open:

```text
http://127.0.0.1:19802/mission-control
```

Screenshots:

- `docs/screenshots/nullhub-mission-control-live.png`
- `docs/screenshots/nullhub-mission-control-recovered.png`

## Reviewer Path

1. Start NullHub:

   ```bash
   zig build run -- serve --host 127.0.0.1 --port 19802 --no-open
   ```

2. Open the UI:

   ```text
   http://127.0.0.1:19802/mission-control
   ```

3. Run the automated demo in another terminal:

   ```bash
   MISSION_CONTROL_OPEN_BROWSER=1 ./scripts/mission_control_demo.sh
   ```

4. Watch the page move through:

   - launch
   - research
   - patching
   - checkpoint
   - test failure
   - human fork from checkpoint
   - recovered validation
   - review complete

5. Open a trace link or export the replay artifact:

   ```bash
   curl -fsS http://127.0.0.1:19802/api/mission-control/replay \
     -o mission-control-replay.json
   ```

## Three-Minute Hackathon Story

0:00 - Launch the mission from NullHub.

0:30 - Agents light up on the role board and workflow graph.

1:00 - Tests fail. The graph marks the tool step red, telemetry increments
errors, and the timeline points at the failed NullWatch-style eval.

1:30 - The operator forks from the checkpoint with the instruction
`apply missing validation guard`.

2:00 - The recovered run replays validation and passes.

2:30 - The final screen compares failed and recovered runs, with trace links and
exportable replay evidence.

## Latest Local Validation

Last run: 2026-05-25

| Command | Result |
| --- | --- |
| `npm --prefix ui run build` | pass |
| `zig build test -Dembed-ui=false -Dbuild-ui=false --summary all` | pass |
| `zig build test --summary all` | pass |
| `zig build test-integration -Dembed-ui=false -Dbuild-ui=false --summary all` | pass |
| `NULLHUB_URL=http://127.0.0.1:19802 ./tests/test_mission_control_smoke.sh` | pass |
| `NULLHUB_URL=http://127.0.0.1:19802 MISSION_CONTROL_OPEN_BROWSER=0 ./scripts/mission_control_demo.sh` | pass |
| Browser check of `/mission-control` load, controls, overlay, and console errors | pass |
| `git diff --check` | pass |

## Video Artifact

On macOS:

```bash
./scripts/record_mission_control_demo.sh
```

The generated video defaults to:

```text
docs/demo/nullhub-mission-control-demo.mov
```

The video is ignored by git and can be uploaded to PR discussion or the
hackathon submission.

Latest local recording: 2026-05-10, `36M`.

## Scope Boundaries

This PR intentionally does not:

- run real model calls;
- require hosted infrastructure;
- require NullTickets, NullBoiler, NullClaw, or NullWatch to be running;
- mutate real task or workflow state;
- replace the existing observability page.

## Future Work

- Connect real NullBoiler workflow run ids and checkpoint metadata.
- Compare failed and recovered replay artifacts side by side.
- Add durable mission replay storage.
- Add a one-click judge replay button in the UI.
