<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { api } from '$lib/api/client';
  import type {
    MissionControlEvent,
    MissionControlPhase,
    MissionControlReplayArtifact,
    MissionControlReplayRecord,
    MissionControlState,
    MissionControlTelemetry,
    MissionControlTraceRef,
    MissionControlWorkflowEvidenceCheckpoint,
    MissionControlWorkflowEvidenceRun,
  } from '$lib/api/missionControl';
  import {
    findRunningNullWatchName,
    hydrateMissionTracePanels,
    missionTracePanelRunIds,
    type TraceHydration,
  } from '$lib/missionControl/traceHydration';
  import {
    emptyControls,
    emptyTelemetry,
    formatBytes,
    formatCost,
    formatDuration,
    formatScore,
    formatTokens,
    phaseOrder,
    statusClass,
    storyBeats,
    tracePanelNote as missionTracePanelNote,
    traceSourceLabel as missionTraceSourceLabel,
    traceSourceSummary as missionTraceSourceSummary,
  } from '$lib/missionControl/display';
  import ReplayComparisonPanel from '$lib/missionControl/ReplayComparisonPanel.svelte';
  import {
    JUDGE_REPLAY_PREROLL_MS,
    nextJudgeReplayTransition,
  } from '$lib/missionControl/judgeReplay.js';
  import { orchestrationUiRoutes } from '$lib/orchestration/routes';

  type MissionAction = 'launch' | 'reset' | 'recover';
  type JudgeReplayStage = 'idle' | 'resetting' | 'preroll' | 'launching' | 'waiting_failure' | 'holding_failure' | 'recovering' | 'watching';

  let mission = $state<MissionControlState | null>(null);
  let loading = $state(true);
  let acting = $state<MissionAction | null>(null);
  let exporting = $state(false);
  let judgeReplayActive = $state(false);
  let judgeReplayStage = $state<JudgeReplayStage>('idle');
  let judgeReplayStartedAt = 0;
  let judgeReplayRecoverAfterMs = 0;
  let advancingJudgeReplay = false;
  let savedReplays = $state<MissionControlReplayRecord[]>([]);
  let savedReplaysLoading = $state(false);
  let savedReplaysError = $state<string | null>(null);
  let error = $state<string | null>(null);
  let traceHydration = $state<Record<string, TraceHydration>>({});
  let traceHydrating = $state(false);
  let traceWatchName = $state<string | null>(null);
  let traceHydrationKey = '';
  let traceHydrationInFlightKey = '';
  let traceHydrationCheckedAt = 0;
  let traceWatchCheckedAt = 0;
  let pollTimer: ReturnType<typeof setTimeout> | null = null;
  let disposed = false;
  const traceHydrationRefreshMs = 5000;
  const nodes = $derived(mission?.graph?.nodes || []);
  const edges = $derived(mission?.graph?.edges || []);
  const agents = $derived(mission?.agents || []);
  const events = $derived(mission?.events || []);
  const telemetry = $derived(mission?.telemetry || emptyTelemetry);
  const controls = $derived(mission?.controls || emptyControls);
  const modeLabel = $derived((mission?.mode || 'deterministic_local_replay').replaceAll('_', ' '));
  const activePoll = $derived(judgeReplayActive || mission?.status === 'running' || mission?.status === 'intervention_required');
  const failedRunId = $derived(mission?.failure?.run_id || mission?.failed_run_id || '');
  const recoveredRunId = $derived(mission?.recovery?.run_id || mission?.recovered_run_id || '');
  const failedTrace = $derived(failedRunId ? traceHydration[failedRunId] || null : null);
  const recoveredTrace = $derived(recoveredRunId ? traceHydration[recoveredRunId] || null : null);
  const liveTraceAvailable = $derived(Boolean(failedTrace || recoveredTrace));
  const workflowEvidence = $derived(mission?.workflow_evidence || null);
  const failedWorkflowRun = $derived(workflowEvidence?.failed_run || null);
  const recoveredWorkflowRun = $derived(workflowEvidence?.recovered_run || null);
  const workflowCheckpoint = $derived(workflowEvidence?.checkpoint || null);
  const replayComparison = $derived(mission?.replay_comparison || null);
  const liveWorkflowAvailable = $derived(
    workflowEvidence?.status === 'available' && Boolean(failedWorkflowRun || recoveredWorkflowRun || workflowCheckpoint),
  );
  const displayTelemetry = $derived(hydratedTelemetry(telemetry, [failedTrace, recoveredTrace]));
  const pageBusy = $derived(loading || acting !== null || exporting || judgeReplayActive);

  function schedulePoll() {
    if (disposed) return;
    if (pollTimer) clearTimeout(pollTimer);
    pollTimer = setTimeout(() => void loadMission(), activePoll ? 1000 : 5000);
  }

  async function loadMission() {
    try {
      const nextMission = await api.getMissionControlState();
      applyMissionState(nextMission);
      error = null;
      await advanceJudgeReplay(nextMission);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      loading = false;
      schedulePoll();
    }
  }

  async function runAction(name: MissionAction) {
    if (pollTimer) {
      clearTimeout(pollTimer);
      pollTimer = null;
    }
    judgeReplayActive = false;
    judgeReplayStage = 'idle';
    acting = name;
    try {
      let nextMission: MissionControlState | null = null;
      if (name === 'launch') nextMission = await api.launchMissionControl();
      if (name === 'reset') nextMission = await api.resetMissionControl();
      if (name === 'recover') nextMission = await api.recoverMissionControl();
      if (nextMission) {
        applyMissionState(nextMission);
      }
      error = null;
    } catch (e) {
      error = (e as Error).message;
    } finally {
      acting = null;
      schedulePoll();
    }
  }

  async function runJudgeReplay() {
    if (pollTimer) {
      clearTimeout(pollTimer);
      pollTimer = null;
    }
    judgeReplayActive = true;
    judgeReplayStage = 'resetting';
    judgeReplayStartedAt = Date.now();
    judgeReplayRecoverAfterMs = 0;
    try {
      applyMissionState(await api.resetMissionControl());
      error = null;
      if (disposed) return;

      judgeReplayStage = 'preroll';
      await sleep(JUDGE_REPLAY_PREROLL_MS);
      if (disposed) return;

      judgeReplayStage = 'launching';
      applyMissionState(await api.launchMissionControl());
      judgeReplayStage = 'waiting_failure';
      error = null;
    } catch (e) {
      judgeReplayActive = false;
      judgeReplayStage = 'idle';
      error = (e as Error).message;
    } finally {
      schedulePoll();
    }
  }

  async function advanceJudgeReplay(snapshot: MissionControlState) {
    if (!judgeReplayActive || advancingJudgeReplay) return;

    const now = Date.now();
    const transition = nextJudgeReplayTransition(
      snapshot,
      {
        active: judgeReplayActive,
        stage: judgeReplayStage,
        startedAtMs: judgeReplayStartedAt,
        recoverAfterMs: judgeReplayRecoverAfterMs,
      },
      now,
    );
    judgeReplayActive = transition.active;
    judgeReplayStage = transition.stage;
    judgeReplayRecoverAfterMs = transition.recoverAfterMs;
    if (transition.error) error = transition.error;
    if (transition.action !== 'recover') return;

    advancingJudgeReplay = true;
    judgeReplayStage = 'recovering';
    try {
      const recoveredMission = await api.recoverMissionControl();
      applyMissionState(recoveredMission);
      if (recoveredMission.status === 'completed') {
        judgeReplayActive = false;
        judgeReplayStage = 'idle';
      } else {
        judgeReplayStage = 'watching';
      }
      error = null;
    } catch (e) {
      judgeReplayActive = false;
      judgeReplayStage = 'idle';
      error = (e as Error).message;
    } finally {
      advancingJudgeReplay = false;
    }
  }

  async function exportReplay() {
    exporting = true;
    try {
      const saved = await api.saveMissionControlReplay();
      savedReplays = [saved.record, ...savedReplays.filter((item) => item.id !== saved.record.id)].slice(0, 10);
      savedReplaysError = null;
      downloadReplayArtifact(saved.artifact, replayFileName(saved.artifact));
      error = null;
    } catch (e) {
      error = (e as Error).message;
    } finally {
      exporting = false;
    }
  }

  async function loadSavedReplays() {
    savedReplaysLoading = true;
    try {
      const result = await api.listMissionControlReplays();
      savedReplays = result.items || [];
      savedReplaysError = null;
    } catch (e) {
      savedReplaysError = (e as Error).message;
    } finally {
      savedReplaysLoading = false;
    }
  }

  async function downloadStoredReplay(record: MissionControlReplayRecord) {
    try {
      const artifact = await api.getStoredMissionControlReplay(record.id);
      downloadReplayArtifact(artifact, storedReplayFileName(record));
      error = null;
    } catch (e) {
      error = (e as Error).message;
    }
  }

  function downloadReplayArtifact(artifact: MissionControlReplayArtifact, filename: string) {
    const json = JSON.stringify(artifact, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(url);
  }

  function applyMissionState(nextMission: MissionControlState) {
    mission = nextMission;
    queueTraceHydration(nextMission);
  }

  function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  onMount(() => {
    void loadMission();
    void loadSavedReplays();
  });

  onDestroy(() => {
    disposed = true;
    if (pollTimer) clearTimeout(pollTimer);
  });

  function queueTraceHydration(snapshot: MissionControlState) {
    void refreshTraceHydration(snapshot);
  }

  async function refreshTraceHydration(snapshot: MissionControlState) {
    const runIds = missionTracePanelRunIds(snapshot);
    if (runIds.length === 0) {
      traceHydration = {};
      traceHydrationKey = '';
      traceHydrationInFlightKey = '';
      traceHydrationCheckedAt = Date.now();
      traceHydrating = false;
      return;
    }

    const watch = await runningNullWatchName();
    if (disposed) return;

    const key = `${watch || 'none'}:${runIds.join('|')}`;
    const now = Date.now();
    if (traceHydrationInFlightKey === key) return;
    if (traceHydrationKey === key && now - traceHydrationCheckedAt < traceHydrationRefreshMs) return;

    traceHydrationInFlightKey = key;
    traceHydrating = Boolean(watch);
    try {
      const traces = await hydrateMissionTracePanels(api, snapshot, watch);
      if (disposed || traceHydrationInFlightKey !== key) return;

      traceHydration = traces;
      traceHydrationKey = key;
      traceHydrationCheckedAt = Date.now();
    } finally {
      if (traceHydrationInFlightKey === key) {
        traceHydrationInFlightKey = '';
        traceHydrating = false;
      }
    }
  }

  async function runningNullWatchName(): Promise<string | null> {
    const now = Date.now();
    if (now - traceWatchCheckedAt < 5000) return traceWatchName;
    traceWatchCheckedAt = now;

    traceWatchName = await findRunningNullWatchName(api);
    return traceWatchName;
  }

  function phaseRank(phase: MissionControlPhase | undefined | null): number {
    if (!phase) return -1;
    return phaseOrder.indexOf(phase);
  }

  function phaseReached(phase: MissionControlPhase): boolean {
    if (!mission) return false;
    return phaseRank(mission.phase) >= phaseRank(phase);
  }

  function storyClass(phase: MissionControlPhase, tone: 'error' | 'success' | undefined): string {
    if (!mission || !phaseReached(phase)) return 'pending';
    if (mission.phase === phase && tone === 'error') return 'error';
    if (mission.phase === phase) return 'active';
    if (tone === 'error' && !mission.recovery) return 'error';
    if (tone === 'success' && mission.status === 'completed') return 'done';
    return 'done';
  }

  function observabilityHref(runId: string | null | undefined): string {
    const params = new URLSearchParams();
    if (runId) params.set('run_id', runId);
    if (traceWatchName) params.set('watch', traceWatchName);
    const query = params.toString();
    return query ? `/observability?${query}` : '/observability';
  }

  function traceLabel(trace: MissionControlTraceRef): string {
    return trace.eval_key || trace.span_id || trace.operation;
  }

  function replayFileName(artifact: MissionControlReplayArtifact): string {
    const scenario = (artifact.scenario_id || mission?.scenario_id || 'mission').replace(/[^a-z0-9._-]+/gi, '-');
    const phase = (artifact.snapshot?.phase || mission?.phase || 'snapshot').replace(/[^a-z0-9._-]+/gi, '-');
    return `nullhub-${scenario}-${phase}-replay.json`;
  }

  function judgeReplayButtonLabel(): string {
    if (!judgeReplayActive) return 'Judge Replay';
    if (judgeReplayStage === 'resetting') return 'Resetting...';
    if (judgeReplayStage === 'preroll') return 'Cueing...';
    if (judgeReplayStage === 'launching') return 'Launching...';
    if (judgeReplayStage === 'waiting_failure') return 'Waiting Failure...';
    if (judgeReplayStage === 'holding_failure') return 'Holding Failure...';
    if (judgeReplayStage === 'recovering') return 'Forking...';
    return 'Watching...';
  }

  function storedReplayFileName(record: MissionControlReplayRecord): string {
    const scenario = (record.scenario_id || 'mission').replace(/[^a-z0-9._-]+/gi, '-');
    const phase = (record.phase || 'snapshot').replace(/[^a-z0-9._-]+/gi, '-');
    return `nullhub-${scenario}-${phase}-${record.saved_at_ms}.json`;
  }

  function replaySavedAt(record: MissionControlReplayRecord): string {
    if (!record.saved_at_ms) return '-';
    return new Date(record.saved_at_ms).toLocaleString();
  }

  function spanCount(trace: TraceHydration | null): number {
    return trace?.summary?.span_count ?? trace?.spans.length ?? 0;
  }

  function evalCount(trace: TraceHydration | null): number {
    return trace?.summary?.eval_count ?? trace?.evals.length ?? 0;
  }

  function errorCount(trace: TraceHydration | null): number {
    if (!trace) return 0;
    return trace.summary?.error_count ?? trace.spans.filter((span) => span.status === 'error' || span.error_message).length;
  }

  function tokenCount(trace: TraceHydration | null): number {
    if (!trace?.summary) return 0;
    return (trace.summary.total_input_tokens || 0) + (trace.summary.total_output_tokens || 0);
  }

  function traceCost(trace: TraceHydration | null): number {
    return trace?.summary?.total_cost_usd || 0;
  }

  function traceVerdict(trace: TraceHydration | null): string | null {
    if (!trace) return null;
    if (trace.summary?.overall_verdict) return trace.summary.overall_verdict;
    const failedEval = trace.evals.find((evaluation) => evaluation.verdict === 'fail');
    if (failedEval) return 'fail';
    const passedEval = trace.evals.find((evaluation) => evaluation.verdict === 'pass');
    if (passedEval) return 'pass';
    return 'live';
  }

  function traceSuffix(trace: TraceHydration | null): string {
    return trace ? ` · ${spanCount(trace)} spans · ${evalCount(trace)} evals` : '';
  }

  function traceSourceLabel(trace: TraceHydration | null): string {
    return missionTraceSourceLabel(trace, traceHydrating);
  }

  function traceSourceSummary(): string {
    return missionTraceSourceSummary({
      liveTraceAvailable,
      traceHydrating,
      hasRunIds: Boolean(failedRunId || recoveredRunId),
    });
  }

  function tracePanelNote(): string {
    return missionTracePanelNote({
      liveTraceAvailable,
      traceHydrating,
      hasRunIds: Boolean(failedRunId || recoveredRunId),
      hasWatch: Boolean(traceWatchName),
    });
  }

  function workflowRunHref(runId: string): string {
    return orchestrationUiRoutes.run(runId, { boilerInstance: workflowEvidence?.boiler_instance || undefined });
  }

  function workflowSourceSummary(): string {
    if (liveWorkflowAvailable) return 'Live NullBoiler';
    if (workflowEvidence?.status === 'not_configured') return 'NullBoiler not configured';
    if (workflowEvidence?.status === 'ambiguous') return 'Ambiguous NullBoiler evidence';
    if (workflowEvidence?.status === 'not_found') return 'No matching NullBoiler evidence';
    if (workflowEvidence?.status === 'schema_mismatch') return 'NullBoiler schema mismatch';
    return 'NullBoiler unavailable';
  }

  function workflowPanelNote(): string {
    if (liveWorkflowAvailable) return 'Hydrated workflow evidence';
    if (workflowEvidence?.reason) return workflowEvidence.reason.replaceAll('_', ' ');
    if (mission?.failure || mission?.recovery) return 'No matching workflow evidence';
    return 'Waiting for checkpoint';
  }

  function workflowRunSuffix(run: MissionControlWorkflowEvidenceRun | null): string {
    if (!run) return '';
    const parts = [run.status];
    if (run.checkpoint_count != null) parts.push(`${run.checkpoint_count} checkpoints`);
    return ` · ${parts.join(' · ')}`;
  }

  function workflowCheckpointLabel(checkpoint: MissionControlWorkflowEvidenceCheckpoint | null): string {
    if (!checkpoint) return '';
    const parts = [checkpoint.step_id || 'checkpoint'];
    if (checkpoint.version != null) parts.push(`v${checkpoint.version}`);
    return parts.join(' · ');
  }

  function workflowCheckpointMetadata(checkpoint: MissionControlWorkflowEvidenceCheckpoint | null): string {
    if (!checkpoint?.metadata || typeof checkpoint.metadata !== 'object' || Array.isArray(checkpoint.metadata)) return '';
    const metadata = checkpoint.metadata as Record<string, unknown>;
    const keys = Object.keys(metadata).filter((key) => key !== 'route_results');
    if (keys.length === 0) return '';
    return `metadata: ${keys.slice(0, 4).join(', ')}`;
  }

  function primaryErrorText(trace: TraceHydration | null): string {
    if (!trace) return '';
    const span = trace.spans.find((item) => item.status === 'error' || item.error_message);
    if (!span) return '';
    const operation = span.operation || span.tool_name || 'span';
    const detail = span.error_message || span.status || 'error';
    return `${operation}: ${detail}`;
  }

  function primaryEvalText(trace: TraceHydration | null, evalKey?: string): string {
    if (!trace) return '';
    const evaluation =
      (evalKey ? trace.evals.find((item) => item.eval_key === evalKey) : null) ||
      trace.evals.find((item) => item.verdict === 'fail') ||
      trace.evals[0];
    if (!evaluation) return '';
    const key = evaluation.eval_key || 'eval';
    const verdict = evaluation.verdict || 'unknown';
    return `${key}: ${verdict} (${formatScore(evaluation.score)})`;
  }

  function hydratedTelemetry(base: MissionControlTelemetry, traces: (TraceHydration | null)[]): MissionControlTelemetry {
    const liveTraces = traces.filter((trace): trace is TraceHydration => Boolean(trace));
    if (liveTraces.length === 0) return base;

    const verdicts = liveTraces.map(traceVerdict).filter((value): value is string => Boolean(value));
    return {
      ...base,
      runs: liveTraces.length,
      spans: liveTraces.reduce((total, trace) => total + spanCount(trace), 0),
      evals: liveTraces.reduce((total, trace) => total + evalCount(trace), 0),
      errors: liveTraces.reduce((total, trace) => total + errorCount(trace), 0),
      total_tokens: liveTraces.reduce((total, trace) => total + tokenCount(trace), 0),
      total_cost_usd: liveTraces.reduce((total, trace) => total + traceCost(trace), 0),
      verdict: verdicts.includes('fail') ? 'fail' : verdicts.includes('pass') ? 'pass' : base.verdict,
    };
  }

  function runVerdict(kind: 'failed' | 'recovered'): string {
    const liveVerdict = traceVerdict(kind === 'failed' ? failedTrace : recoveredTrace);
    if (liveVerdict && liveVerdict !== 'live') return liveVerdict;
    if (kind === 'failed') return mission?.failure ? 'fail' : 'pending';
    if (!mission?.recovery) return 'pending';
    return mission.status === 'completed' ? 'pass' : 'recovering';
  }
</script>

<div class="mission-page" aria-busy={pageBusy}>
  <header class="mission-header">
    <div>
      <h1>Mission Control</h1>
      <p>{mission?.headline || 'Loading mission state...'}</p>
    </div>
    <div class="actions">
      <button onclick={() => runAction('reset')} disabled={acting !== null || loading || judgeReplayActive}>Reset</button>
      <button class="primary" onclick={() => runJudgeReplay()} disabled={loading || acting !== null || exporting || judgeReplayActive}>
        {judgeReplayButtonLabel()}
      </button>
      <button onclick={() => runAction('launch')} disabled={!controls.can_launch || acting !== null || loading || judgeReplayActive}>
        {acting === 'launch' ? 'Launching...' : 'Launch Mission'}
      </button>
      <button class="danger" onclick={() => runAction('recover')} disabled={!controls.can_recover || acting !== null || loading || judgeReplayActive}>
        {acting === 'recover' ? 'Forking...' : 'Fork From Checkpoint'}
      </button>
      <button onclick={() => exportReplay()} disabled={!mission || exporting || loading || judgeReplayActive}>
        {exporting ? 'Saving...' : 'Save Replay'}
      </button>
    </div>
  </header>

  {#if error}
    <div class="error-banner" role="alert">
      <span>ERR: {error}</span>
      <button onclick={() => loadMission()} disabled={acting !== null}>Retry</button>
    </div>
  {/if}

  {#if loading && !mission}
    <div class="loading">Loading mission...</div>
  {:else if mission}
    <section class="mode-strip" aria-label="Mission replay metadata">
      <div>
        <span>Mode</span>
        <strong>{modeLabel}</strong>
      </div>
      <div>
        <span>Scenario</span>
        <strong>{mission.scenario_id}</strong>
      </div>
      <div>
        <span>Schema</span>
        <strong>v{mission.schema_version}</strong>
      </div>
      <div>
        <span>Polling</span>
        <strong>{activePoll ? 'live' : 'idle'}</strong>
      </div>
    </section>

    <section class="command-strip">
      <div>
        <span>Status</span>
        <strong class={statusClass(mission.status)}>{mission.status}</strong>
      </div>
      <div>
        <span>Phase</span>
        <strong>{mission.phase}</strong>
      </div>
      <div>
        <span>Elapsed</span>
        <strong>{formatDuration(mission.elapsed_ms)}</strong>
      </div>
      <div>
        <span>Run</span>
        <strong>{mission.active_run_id || '-'}</strong>
      </div>
    </section>

    {#if savedReplays.length > 0 || savedReplaysLoading || savedReplaysError}
      <section class="saved-replays-panel">
        <div class="panel-heading">
          <h2>Saved Replays</h2>
          <span>{savedReplaysLoading ? 'loading' : savedReplaysError ? 'unavailable' : `${savedReplays.length} stored`}</span>
        </div>
        {#if savedReplaysError}
          <p class="saved-replay-error">{savedReplaysError}</p>
        {/if}
        {#if savedReplays.length > 0}
          <div class="saved-replay-list">
            {#each savedReplays.slice(0, 4) as replay}
              <button class="saved-replay-row" onclick={() => downloadStoredReplay(replay)}>
                <span>{replaySavedAt(replay)}</span>
                <strong>{replay.phase} · {replay.status}</strong>
                <small>{replay.scenario_id} · {formatBytes(replay.size_bytes)}</small>
              </button>
            {/each}
          </div>
        {/if}
      </section>
    {/if}

    <section class="story-strip" aria-label="Three minute mission story">
      {#each storyBeats as beat}
        <div class="story-beat {storyClass(beat.phase, beat.tone)}">
          <span>{beat.time}</span>
          <strong>{beat.title}</strong>
          <p>{beat.detail}</p>
        </div>
      {/each}
    </section>

    <div class="progress-track" aria-label="Mission progress">
      <div style="width: {mission.progress}%"></div>
    </div>

    <section class="graph-panel">
      <div class="panel-heading">
        <h2>Live Orchestration</h2>
        <span>{mission.progress}%</span>
      </div>
      <div class="graph-row">
        {#each nodes as node, index}
          <div class="node-wrap">
            <div class="node {statusClass(node.status)}">
              <span>{node.kind}</span>
              <strong>{node.label}</strong>
            </div>
            {#if index < nodes.length - 1}
              <div class="edge {statusClass(edges[index]?.status)}"></div>
            {/if}
          </div>
        {/each}
      </div>
    </section>

    <div class="mission-grid">
      <section class="agents-panel">
        <div class="panel-heading">
          <h2>Agent Board</h2>
          <span>{agents.length}</span>
        </div>
        <div class="agent-list">
          {#each agents as agent}
            <div class="agent-row {statusClass(agent.status)}">
              <div>
                <strong>{agent.role}</strong>
                <span>{agent.id}</span>
              </div>
              <p>{agent.current_step}</p>
              <span class="pill {statusClass(agent.status)}">{agent.status}</span>
            </div>
          {/each}
        </div>
      </section>

      <section class="telemetry-panel">
        <div class="panel-heading">
          <h2>Telemetry</h2>
          <span>{displayTelemetry.verdict || '-'}</span>
        </div>
        <div class="metric-grid">
          <div><span>Runs</span><strong>{displayTelemetry.runs || 0}</strong></div>
          <div><span>Spans</span><strong>{displayTelemetry.spans || 0}</strong></div>
          <div><span>Evals</span><strong>{displayTelemetry.evals || 0}</strong></div>
          <div><span>Errors</span><strong class:error={(displayTelemetry.errors || 0) > 0}>{displayTelemetry.errors || 0}</strong></div>
          <div><span>Tokens</span><strong>{formatTokens(displayTelemetry.total_tokens)}</strong></div>
          <div><span>Cost</span><strong>{formatCost(displayTelemetry.total_cost_usd)}</strong></div>
        </div>

        <div class="trace-card">
          <div>
            <span>Traceability</span>
            <strong>{traceSourceSummary()}</strong>
            <em>{tracePanelNote()}</em>
          </div>
          {#if failedTrace}
            <a href={observabilityHref(failedRunId)}>Failed run{traceSuffix(failedTrace)}</a>
          {:else if failedRunId && traceHydrating}
            <span class="trace-placeholder">Checking failed run</span>
          {:else if failedRunId}
            <span class="trace-placeholder">Failed run unavailable</span>
          {:else}
            <span class="trace-placeholder">Failed pending</span>
          {/if}
          {#if recoveredTrace}
            <a href={observabilityHref(recoveredRunId)}>Recovered run{traceSuffix(recoveredTrace)}</a>
          {:else if recoveredRunId && traceHydrating}
            <span class="trace-placeholder">Checking recovered run</span>
          {:else if recoveredRunId}
            <span class="trace-placeholder">Recovered run unavailable</span>
          {:else}
            <span class="trace-placeholder">Recovery pending</span>
          {/if}
        </div>

        <div class="trace-card workflow-card">
          <div>
            <span>Workflow</span>
            <strong>{workflowSourceSummary()}</strong>
            <em>{workflowPanelNote()}</em>
          </div>
            {#if failedWorkflowRun}
              <a href={workflowRunHref(failedWorkflowRun.run_id)}>Failed workflow{workflowRunSuffix(failedWorkflowRun)}</a>
            {:else if failedRunId || mission.failure}
              <span class="trace-placeholder">Failed workflow unavailable</span>
          {:else}
            <span class="trace-placeholder">Workflow pending</span>
          {/if}
            {#if recoveredWorkflowRun}
              <a href={workflowRunHref(recoveredWorkflowRun.run_id)}>Recovered workflow{workflowRunSuffix(recoveredWorkflowRun)}</a>
            {:else if recoveredRunId || mission.recovery}
              <span class="trace-placeholder">Recovered workflow unavailable</span>
          {:else}
            <span class="trace-placeholder">Recovery pending</span>
          {/if}
        </div>

        {#if mission.failure}
          <div class="failure-box">
            <span>Failure</span>
            <strong>{mission.failure.failed_step}</strong>
            <p>{mission.failure.error_message}</p>
            <code>{workflowCheckpoint?.id || mission.failure.checkpoint_id}</code>
            {#if workflowCheckpoint}
              <p class="trace-evidence">
                NullBoiler checkpoint {workflowCheckpointLabel(workflowCheckpoint)}
                {#if workflowCheckpointMetadata(workflowCheckpoint)}
                  · {workflowCheckpointMetadata(workflowCheckpoint)}
                {/if}
              </p>
                {#if failedWorkflowRun}
                  <a href={workflowRunHref(failedWorkflowRun.run_id)}>Open failed workflow</a>
              {/if}
            {/if}
            {#if failedTrace}
              <a href={observabilityHref(mission.failure.run_id)}>Open failed trace</a>
            {/if}
            {#if failedTrace || traceHydrating}
            <div class="trace-detail {failedTrace ? 'live' : 'loading'}">
              <div class="trace-detail-top">
                <span>{traceSourceLabel(failedTrace)}</span>
                <strong>{traceVerdict(failedTrace) || runVerdict('failed')}</strong>
              </div>
              {#if failedTrace}
                <dl class="trace-stats">
                  <div><dt>Spans</dt><dd>{spanCount(failedTrace)}</dd></div>
                  <div><dt>Evals</dt><dd>{evalCount(failedTrace)}</dd></div>
                  <div><dt>Errors</dt><dd>{errorCount(failedTrace)}</dd></div>
                </dl>
                {#if primaryErrorText(failedTrace)}
                  <p class="trace-evidence">{primaryErrorText(failedTrace)}</p>
                {/if}
                {#if primaryEvalText(failedTrace, 'tool_success')}
                  <p class="trace-evidence">{primaryEvalText(failedTrace, 'tool_success')}</p>
                {/if}
              {/if}
            </div>
            {/if}
          </div>
        {/if}

        {#if mission.recovery}
          <div class="recovery-box">
            <span>Recovery</span>
            <strong>{mission.recovery.status}</strong>
            <p>{mission.recovery.human_instruction}</p>
            <code>{mission.recovery.run_id}</code>
              {#if recoveredWorkflowRun}
                <p class="trace-evidence">NullBoiler run {recoveredWorkflowRun.run_id}{workflowRunSuffix(recoveredWorkflowRun)}</p>
                <a href={workflowRunHref(recoveredWorkflowRun.run_id)}>Open recovered workflow</a>
            {/if}
            {#if recoveredTrace}
              <a href={observabilityHref(mission.recovery.run_id)}>Open recovered trace</a>
            {/if}
            {#if recoveredTrace || traceHydrating}
            <div class="trace-detail {recoveredTrace ? 'live' : 'loading'}">
              <div class="trace-detail-top">
                <span>{traceSourceLabel(recoveredTrace)}</span>
                <strong>{traceVerdict(recoveredTrace) || runVerdict('recovered')}</strong>
              </div>
              {#if recoveredTrace}
                <dl class="trace-stats">
                  <div><dt>Spans</dt><dd>{spanCount(recoveredTrace)}</dd></div>
                  <div><dt>Evals</dt><dd>{evalCount(recoveredTrace)}</dd></div>
                  <div><dt>Errors</dt><dd>{errorCount(recoveredTrace)}</dd></div>
                </dl>
                {#if primaryErrorText(recoveredTrace)}
                  <p class="trace-evidence">{primaryErrorText(recoveredTrace)}</p>
                {/if}
                {#if primaryEvalText(recoveredTrace, 'tool_success')}
                  <p class="trace-evidence">{primaryEvalText(recoveredTrace, 'tool_success')}</p>
                {/if}
              {/if}
            </div>
            {/if}
          </div>
        {/if}
      </section>
    </div>

    {#if replayComparison}
      <ReplayComparisonPanel
        {replayComparison}
        {traceWatchName}
        boilerInstance={workflowEvidence?.boiler_instance || null}
      />
    {/if}

    <section class="timeline-panel">
      <div class="panel-heading">
        <h2>Mission Timeline</h2>
        <span>{events.filter((event: MissionControlEvent) => event.status !== 'pending').length}/{events.length}</span>
      </div>
      <div class="timeline">
        {#each events as event}
          <div class="event-row {statusClass(event.status)}">
            <div class="event-marker"></div>
            <div class="event-body">
              <div class="event-top">
                <strong>{event.title}</strong>
                <span>{formatDuration(event.at_ms)}</span>
              </div>
              <div class="event-meta">
                <span>{event.source}</span>
                <span>{event.level}</span>
                {#if event.trace}
                  <a href={observabilityHref(event.trace.run_id)} title={event.trace.operation}>
                    {event.trace.kind}: {traceLabel(event.trace)}
                  </a>
                {/if}
              </div>
              <p>{event.detail}</p>
            </div>
          </div>
        {/each}
      </div>
    </section>
  {/if}
</div>

<style>
  .mission-page {
    --fg-muted: var(--fg-dim);
    padding: 1.5rem;
    max-width: 1600px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .mission-header,
  .panel-heading,
  .event-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }

  h1,
  h2,
  p {
    margin: 0;
    letter-spacing: 0;
  }

  h1 {
    font-size: 1.75rem;
    color: var(--fg);
  }

  h2 {
    font-size: 0.9rem;
    color: var(--accent);
    text-transform: uppercase;
  }

  .mission-header p,
  .event-meta,
  .agent-row span,
  .panel-heading span {
    color: var(--fg-muted);
    font-size: 0.8125rem;
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    justify-content: flex-end;
  }

  button {
    min-height: 2.25rem;
    border: 1px solid var(--border);
    background: var(--bg-surface);
    color: var(--fg);
    border-radius: 4px;
    padding: 0.45rem 0.75rem;
    cursor: pointer;
    font-weight: 700;
    text-transform: uppercase;
    font-size: 0.75rem;
  }

  button:hover:not(:disabled) {
    border-color: var(--accent);
    color: var(--accent);
    background: var(--bg-hover);
  }

  button:disabled {
    cursor: not-allowed;
    opacity: 0.45;
  }

  button.primary {
    color: var(--accent);
    border-color: var(--accent-dim);
  }

  button.danger {
    color: var(--error);
    border-color: var(--error);
  }

  .error-banner,
  .loading {
    border: 1px solid var(--border);
    background: var(--bg-surface);
    border-radius: 4px;
    padding: 0.85rem 1rem;
    color: var(--fg-muted);
    font-family: var(--font-mono);
  }

  .error-banner {
    color: var(--error);
    border-color: var(--error);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }

  .command-strip,
  .mode-strip,
  .metric-grid,
  .story-strip {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 0.75rem;
  }

  .command-strip div,
  .mode-strip div,
  .metric-grid div,
  .story-beat {
    border: 1px solid var(--border);
    background: var(--bg-surface);
    border-radius: 4px;
    padding: 0.75rem;
    min-width: 0;
  }

  .command-strip span,
  .mode-strip span,
  .metric-grid span,
  .story-beat span,
  .failure-box span,
  .recovery-box span {
    display: block;
    color: var(--fg-muted);
    font-size: 0.7rem;
    text-transform: uppercase;
    margin-bottom: 0.35rem;
  }

  .command-strip strong,
  .mode-strip strong,
  .metric-grid strong,
  .story-beat strong {
    display: block;
    color: var(--fg);
    font-family: var(--font-mono);
    font-size: 1.1rem;
    overflow-wrap: anywhere;
  }

  .done {
    color: var(--success) !important;
  }

  .active {
    color: var(--accent) !important;
  }

  .error {
    color: var(--error) !important;
  }

  .warning {
    color: var(--warning) !important;
  }

  .pending {
    color: var(--fg-muted) !important;
  }

  .story-strip {
    grid-template-columns: repeat(6, minmax(0, 1fr));
  }

  .story-beat {
    min-height: 7rem;
  }

  .story-beat.active,
  .story-beat.done,
  .story-beat.error {
    border-color: currentColor;
  }

  .story-beat p {
    color: var(--fg-muted);
    font-size: 0.78rem;
    line-height: 1.35;
  }

  .progress-track {
    height: 0.5rem;
    border: 1px solid var(--border);
    background: var(--bg-surface);
    border-radius: 999px;
    overflow: hidden;
  }

  .progress-track div {
    height: 100%;
    background: var(--accent);
    box-shadow: 0 0 14px var(--accent);
    transition: width 0.35s ease;
  }

  .graph-panel,
  .agents-panel,
  .telemetry-panel,
  .saved-replays-panel,
  .timeline-panel {
    border: 1px solid var(--border);
    background: var(--bg-surface);
    border-radius: 4px;
    padding: 1rem;
    min-width: 0;
  }

  .saved-replay-list {
    margin-top: 0.85rem;
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 0.75rem;
  }

  .saved-replay-row {
    min-height: 5rem;
    text-align: left;
    text-transform: none;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    justify-content: center;
    gap: 0.25rem;
    overflow: hidden;
  }

  .saved-replay-row span,
  .saved-replay-row small {
    color: var(--fg-muted);
    font-size: 0.72rem;
    overflow-wrap: anywhere;
  }

  .saved-replay-row strong {
    color: var(--fg);
    font-family: var(--font-mono);
    font-size: 0.95rem;
    overflow-wrap: anywhere;
  }

  .saved-replay-error {
    margin: 0.85rem 0 0;
    color: var(--error);
    font-size: 0.85rem;
    overflow-wrap: anywhere;
  }

  .graph-row {
    margin-top: 1rem;
    display: grid;
    grid-template-columns: repeat(7, minmax(96px, 1fr));
    gap: 0.5rem;
    align-items: center;
  }

  .node-wrap {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 24px;
    align-items: center;
    min-width: 0;
  }

  .node-wrap:last-child {
    grid-template-columns: minmax(0, 1fr);
  }

  .node {
    border: 1px solid var(--border);
    background: var(--bg);
    border-radius: 4px;
    min-height: 5.2rem;
    padding: 0.75rem;
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 0.35rem;
  }

  .node.active {
    border-color: var(--accent);
    box-shadow: 0 0 16px color-mix(in srgb, var(--accent) 40%, transparent);
  }

  .node.error {
    border-color: var(--error);
    box-shadow: 0 0 16px color-mix(in srgb, var(--error) 35%, transparent);
  }

  .node.done {
    border-color: var(--success);
  }

  .node span {
    color: var(--fg-muted);
    font-size: 0.7rem;
    text-transform: uppercase;
  }

  .node strong {
    color: inherit;
    font-size: 0.95rem;
  }

  .edge {
    height: 2px;
    background: var(--border);
  }

  .edge.done,
  .edge.active {
    background: var(--success);
    box-shadow: 0 0 12px var(--success);
  }

  .edge.error {
    background: var(--error);
    box-shadow: 0 0 12px var(--error);
  }

  .mission-grid {
    display: grid;
    grid-template-columns: minmax(320px, 0.9fr) minmax(420px, 1.1fr);
    gap: 1rem;
    align-items: start;
  }

  .agent-list {
    margin-top: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.65rem;
  }

  .agent-row {
    border: 1px solid var(--border);
    background: var(--bg);
    border-radius: 4px;
    padding: 0.75rem;
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr) auto;
    gap: 0.75rem;
    align-items: center;
  }

  .agent-row.active {
    border-color: var(--accent);
  }

  .agent-row.error,
  .agent-row.warning {
    border-color: currentColor;
  }

  .agent-row strong,
  .agent-row p {
    color: var(--fg);
    overflow-wrap: anywhere;
  }

  .pill {
    border: 1px solid currentColor;
    border-radius: 999px;
    padding: 0.15rem 0.45rem;
    font-size: 0.68rem;
    text-transform: uppercase;
    font-weight: 700;
    white-space: nowrap;
  }

  .metric-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
    margin-top: 1rem;
  }

  .failure-box,
  .recovery-box,
  .trace-card {
    margin-top: 1rem;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: var(--bg);
    padding: 0.85rem;
  }

  .failure-box {
    border-color: var(--error);
  }

  .recovery-box {
    border-color: var(--success);
  }

  .trace-card {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto auto;
    align-items: center;
    gap: 0.75rem;
  }

  .workflow-card {
    border-color: var(--accent-dim);
  }

  .trace-card em {
    display: block;
    color: var(--fg-muted);
    font-size: 0.72rem;
    font-style: normal;
  }

  .trace-detail {
    margin-top: 0.75rem;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: color-mix(in srgb, var(--bg-surface) 70%, transparent);
    padding: 0.75rem;
  }

  .trace-detail.live {
    border-color: var(--accent-dim);
  }

  .trace-detail-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
  }

  .trace-detail-top strong {
    margin-bottom: 0;
    color: var(--accent);
    font-family: var(--font-mono);
    font-size: 0.82rem;
    overflow-wrap: anywhere;
  }

  .trace-stats {
    margin: 0.75rem 0 0;
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 0.5rem;
  }

  .trace-stats dt,
  .trace-stats dd {
    margin: 0;
  }

  .trace-stats dt {
    color: var(--fg-muted);
    font-size: 0.68rem;
    text-transform: uppercase;
  }

  .trace-stats dd {
    color: var(--fg);
    font-family: var(--font-mono);
    font-size: 0.82rem;
  }

  .trace-evidence {
    margin: 0.65rem 0 0;
    color: var(--fg-muted);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    overflow-wrap: anywhere;
  }

  .failure-box strong,
  .recovery-box strong,
  .trace-card strong {
    display: block;
    margin-bottom: 0.35rem;
    color: var(--fg);
  }

  .failure-box p,
  .recovery-box p {
    color: var(--fg-muted);
    font-size: 0.8125rem;
    margin-bottom: 0.65rem;
  }

  .failure-box p.trace-evidence,
  .recovery-box p.trace-evidence {
    margin: 0.65rem 0 0;
    color: var(--fg-muted);
    font-family: var(--font-mono);
    font-size: 0.75rem;
  }

  code {
    display: block;
    color: var(--accent);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    overflow-wrap: anywhere;
  }

  .trace-card a,
  .failure-box a,
  .recovery-box a,
  .event-meta a {
    color: var(--accent);
    text-decoration: none;
    font-family: var(--font-mono);
    font-size: 0.75rem;
    overflow-wrap: anywhere;
  }

  .trace-card a,
  .failure-box a,
  .recovery-box a {
    display: inline-flex;
    width: fit-content;
    border: 1px solid var(--accent-dim);
    border-radius: 4px;
    padding: 0.35rem 0.5rem;
  }

  .trace-placeholder {
    display: inline-flex;
    width: fit-content;
    border: 1px solid var(--border);
    border-radius: 4px;
    padding: 0.35rem 0.5rem;
    color: var(--fg-muted);
    font-family: var(--font-mono);
    font-size: 0.75rem;
  }

  .failure-box a,
  .recovery-box a {
    margin-top: 0.65rem;
  }

  .timeline {
    margin-top: 1rem;
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 0.75rem;
  }

  .event-row {
    display: grid;
    grid-template-columns: 12px minmax(0, 1fr);
    gap: 0.65rem;
  }

  .event-marker {
    margin-top: 0.45rem;
    width: 10px;
    height: 10px;
    border: 1px solid currentColor;
    border-radius: 50%;
    background: currentColor;
  }

  .event-body {
    border: 1px solid var(--border);
    background: var(--bg);
    border-radius: 4px;
    padding: 0.75rem;
    min-height: 8rem;
  }

  .event-row.active .event-body,
  .event-row.error .event-body,
  .event-row.done .event-body {
    border-color: currentColor;
  }

  .event-top strong {
    color: var(--fg);
    overflow-wrap: anywhere;
  }

  .event-top span {
    color: var(--fg-muted);
    font-family: var(--font-mono);
    font-size: 0.75rem;
  }

  .event-meta {
    display: flex;
    gap: 0.5rem;
    flex-wrap: wrap;
    margin: 0.35rem 0 0.55rem;
    text-transform: uppercase;
  }

  .event-body p {
    color: var(--fg-muted);
    font-size: 0.8125rem;
  }

  @media (max-width: 1200px) {
    .graph-row,
    .saved-replay-list,
    .story-strip,
    .timeline {
      grid-template-columns: 1fr;
    }

    .node-wrap,
    .node-wrap:last-child {
      grid-template-columns: 1fr;
    }

    .edge {
      display: none;
    }

    .mission-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 720px) {
    .mission-page {
      padding: 1rem;
    }

    .mission-header {
      align-items: flex-start;
      flex-direction: column;
    }

    .actions {
      justify-content: flex-start;
    }

    .command-strip,
    .mode-strip,
    .metric-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .trace-card {
      grid-template-columns: 1fr;
      align-items: stretch;
    }

    .agent-row {
      grid-template-columns: 1fr;
    }
  }
</style>
