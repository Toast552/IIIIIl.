# Mission Control Replay Artifact

Mission Control exposes the current deterministic replay as JSON:

```text
GET /api/mission-control/replay
```

The artifact is intended for local debugging, PR review, and hackathon
submission evidence. It does not mutate runtime state and does not require
NullTickets, NullBoiler, NullClaw, or NullWatch to be running.

## Shape

The exported JSON contains:

- `artifact_schema_version` - version of the export wrapper.
- `artifact_kind` - `nullhub.mission_control.replay`.
- `generated_at_ms` - export timestamp.
- `replay_fixture_path` - repository path of the embedded scenario fixture.
- `scenario_id`, `scenario_version`, `mode` - replay identity.
- `snapshot` - the current rendered Mission Control state.
- `replay_fixture` - the source fixture used to derive the replay.
- `ecosystem_mapping` - how the fixture maps to nullclaw ecosystem concepts.

## Ecosystem Mapping

`ecosystem_mapping.nulltickets` points to tracker-style evidence:

- `events[source=nulltickets]`
- `graph.nodes[kind=tracker]`

`ecosystem_mapping.nullboiler` points to orchestration evidence:

- phase timing and workflow graph edges
- `checkpoint_id`
- failed and recovered run ids
- human fork instruction

`ecosystem_mapping.nullclaw` points to agent evidence:

- role-based agents
- agent graph nodes
- NullClaw-style event source entries

`ecosystem_mapping.nullwatch` points to observability evidence:

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
/mission-control -> Export Replay
```

The exported JSON can be attached to PR discussion or used as a compact record
of the local demo state at the moment it was captured.
