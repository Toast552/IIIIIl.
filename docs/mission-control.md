# Mission Control

Mission Control is a local replay and recovery workspace for NullHub. It keeps
a deterministic mission scenario available without requiring hosted services,
then hydrates that scenario with live NullWatch and NullBoiler evidence when
matching local instances are running.

The built-in scenario fixture is intentionally versioned and checked by tests.
It gives `/mission-control` a stable baseline state while still allowing live
trace and workflow panels to replace fixture-only evidence when real local
services are available.

## Replay API

Mission Control exposes the current replay as JSON:

```text
GET /api/mission-control/replay
```

It can also persist the current replay artifact in NullHub storage:

```text
POST /api/mission-control/replay/save
GET /api/mission-control/replays
GET /api/mission-control/replays/{id}
```

Replay export does not mutate NullTickets, NullBoiler, NullClaw, or NullWatch.
When matching local NullBoiler evidence is available, the artifact includes real
workflow run ids and checkpoint metadata. When a local NullWatch instance is
running, the UI hydrates failed and recovered trace panels before export/save.
Saved artifacts are written to `~/.nullhub/mission-control/replays/` as
self-contained JSON files so they survive process restarts.

## Shape

The exported JSON contains:

- `artifact_schema_version` - version of the export wrapper.
- `artifact_kind` - `nullhub.mission_control.replay`.
- `generated_at_ms` - export timestamp.
- `replay_fixture_path` - repository path of the embedded scenario fixture.
- `scenario_id`, `scenario_version`, `mode` - replay identity.
- `snapshot` - the current rendered Mission Control state.
  - `replay_comparison` - side-by-side failed and recovered run replay
    artifacts with verdicts, telemetry, trace ids, workflow ids, checkpoint
    linkage, and deltas once the recovered run completes; it is `null` before
    the recovered artifact exists in the current state.
- `replay_fixture` - the source fixture used to derive the replay.
- `workflow_evidence` - resolved NullBoiler run/checkpoint evidence when a
  matching local instance is available.
- `ecosystem_mapping` - how the fixture maps to nullclaw ecosystem concepts.

## Ecosystem Mapping

`ecosystem_mapping.nulltickets` points to tracker-style evidence:

- `events[source=nulltickets]`
- `graph.nodes[kind=tracker]`

`ecosystem_mapping.nullboiler` points to NullBoiler workflow evidence:

- phase timing and workflow graph edges
- `workflow_evidence`
- `checkpoint_id`
- failed and recovered run ids
- human fork instruction

`ecosystem_mapping.nullclaw` points to agent evidence:

- role-based agents
- agent graph nodes
- NullClaw-style event source entries

`ecosystem_mapping.nullwatch` points to NullWatch trace evidence:

- failed and recovered run ids
- `events[].trace`
- telemetry counters
- failure and recovery run panels

## Local Export

Start NullHub:

```bash
zig build run -- serve --host 127.0.0.1 --port 19802 --no-open
```

Export the current replay:

```bash
curl -fsS http://127.0.0.1:19802/api/mission-control/replay \
  -o mission-control-replay.json
```

Or use the UI button:

```text
/mission-control -> Save Replay
```

The exported JSON is a compact local record of the replay state at the moment
it was captured.
