# Mission Control PR Package

This file is the copy-ready review package for the NullOS Mission Control
hackathon contribution.

## Suggested PR Title

Add NullOS Mission Control local agent recovery demo

## Suggested PR Description

Adds a local-first Mission Control demo to NullHub: a three-minute control-room
experience for lightweight agent infrastructure.

The demo shows a deterministic agent mission from launch to failure, human
checkpoint recovery, recovered validation, review, trace links, telemetry,
side-by-side failed/recovered replay evidence, and durable replay save/export.
It is designed to run locally without hosted services, model keys, or external
infrastructure.

What changed:

- Added `/api/mission-control/*` for mission state, reset, launch, recovery,
  replay export, durable replay save, durable replay list, and durable replay
  readback.
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
- Added a one-click `Judge Replay` button that runs reset, launch, failure
  hold, checkpoint recovery, and recovered validation from the UI.
- Added deep links from mission events to `/observability?run_id=...`.
- Hydrates failure/recovery trace panels from a running NullWatch instance via
  the existing observability proxy when live run detail is available.
- Resolves real NullBoiler workflow run ids and checkpoint metadata server-side
  through the existing orchestration proxy when matching workflow evidence is
  available.
- Stores saved replay artifacts under
  `~/.nullhub/mission-control/replays/` using atomic durable writes.
- Keeps mission runtime state scoped to the NullHub server instance and keeps
  live hydration discovery outside the Svelte route component.
- Keeps the Judge Replay transition model in a standalone frontend helper with
  a local unit test.
- Added local smoke test, judge-mode demo driver, macOS video recorder,
  screenshots, README docs, and hackathon submission notes.

Why:

NullHub already acts as the control plane for the nullclaw ecosystem, and the
surrounding repositories already sketch out runtime, orchestration, task state,
and observability. What was missing was a memorable local vertical slice that
lets reviewers see those concepts working as one operator experience.

This PR keeps the demo deterministic and honest: it does not mutate real
NullTickets, NullBoiler, NullClaw, or NullWatch state. When local NullWatch or
NullBoiler instances are running and contain matching evidence, Mission Control
hydrates trace panels, workflow run ids, and checkpoint metadata from those
services. Without matching live evidence, the deterministic replay fixture
remains the source of truth for the local Mission Control run.

Validation performed:

```bash
npm --prefix ui run build
npm --prefix ui run test:mission-control
zig build test
zig build
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

5. Open a trace link or save/export the replay artifact:

   ```bash
   curl -fsS http://127.0.0.1:19802/api/mission-control/replay \
     -o mission-control-replay.json
   ```

   The same artifact can be persisted from the UI with `Save Replay`.

## Three-Minute Hackathon Story

0:00 - Click `Judge Replay` in NullHub.

0:30 - Agents light up on the role board and workflow graph.

1:00 - Tests fail. The graph marks the tool step red, telemetry increments
errors, and the timeline points at the failed NullWatch-style eval.

1:30 - The operator forks from the checkpoint with the instruction
`apply missing validation guard`.

2:00 - The recovered run replays validation and passes.

2:30 - The final screen compares failed and recovered runs, with trace links and
exportable replay evidence.

## Latest Local Validation

Last run: 2026-05-26

| Command | Result |
| --- | --- |
| `npm --prefix ui run build` | pass |
| `npm --prefix ui run test:mission-control` | pass |
| `zig build test` | pass |
| `zig build` | pass |
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
