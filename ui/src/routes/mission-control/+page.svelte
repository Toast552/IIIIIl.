<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { api } from '$lib/api/client';
  import type {
    MissionControlEvent,
    MissionControlControls,
    MissionControlPhase,
    MissionControlReplayArtifact,
    MissionControlState,
    MissionControlTelemetry,
    MissionControlTraceRef,
  } from '$lib/api/missionControl';
  import {
    findRunningNullWatchName,
    hydrateMissionTracePanels,
    missionTracePanelRunIds,
    type TraceHydration,
  } from '$lib/missionControl/traceHydration';

  type MissionAction = 'launch' | 'reset' | 'recover';
  const emptyControls: MissionControlControls = {
    can_launch: false,
    can_recover: false,
    can_reset: true,
  };
  const emptyTelemetry: MissionControlTelemetry = {
    runs: 0,
    spans: 0,
    evals: 0,
    errors: 0,
    total_tokens: 0,
    total_cost_usd: 0,
    verdict: '-',
  };
  const phaseOrder: MissionControlPhase[] = [
    'idle',
    'launching',
    'research',
    'coding',
    'checkpoint',
    'testing',
    'failed',
    'forking',
    'patching',
    'retesting',
    'review',
    'completed',
  ];
  const storyBeats: { phase: MissionControlPhase; time: string; title: string; detail: string; tone?: 'error' | 'success' }[] = [
    {
      phase: 'launching',
      time: '0:00',
      title: 'Launch',
      detail: 'Backlog claim and workflow dispatch start.',
    },
    {
      phase: 'checkpoint',
      time: '0:45',
      title: 'Checkpoint',
      detail: 'Agents save state before validation.',
    },
    {
      phase: 'failed',
      time: '1:10',
      title: 'Failure',
      detail: 'Test telemetry flags a failed tool call.',
      tone: 'error',
    },
    {
      phase: 'forking',
      time: '1:35',
      title: 'Intervene',
      detail: 'Human forks from checkpoint with a fix instruction.',
    },
    {
      phase: 'retesting',
      time: '2:05',
      title: 'Replay',
      detail: 'Recovered run replays validation.',
    },
    {
      phase: 'completed',
      time: '2:30',
      title: 'Review',
      detail: 'Recovered mission reaches a passing verdict.',
      tone: 'success',
    },
  ];

  let mission = $state<MissionControlState | null>(null);
  let loading = $state(true);
  let acting = $state<MissionAction | null>(null);
  let exporting = $state(false);
  let error = $state<string | null>(null);
  let traceHydration = $state<Record<string, TraceHydration>>({});
  let traceHydrating = $state(false);
  let traceWatchName = $state<string | null>(null);
  let traceHydrationRequest = 0;
  let traceWatchCheckedAt = 0;
  let pollTimer: ReturnType<typeof setTimeout> | null = null;
  let disposed = false;

  const nodes = $derived(mission?.graph?.nodes || []);
  const edges = $derived(mission?.graph?.edges || []);
  const agents = $derived(mission?.agents || []);
  const events = $derived(mission?.events || []);
  const telemetry = $derived(mission?.telemetry || emptyTelemetry);
  const controls = $derived(mission?.controls || emptyControls);
  const modeLabel = $derived((mission?.mode || 'deterministic_local_replay').replaceAll('_', ' '));
  const activePoll = $derived(mission?.status === 'running' || mission?.status === 'intervention_required');
  const failedRunId = $derived(mission?.failure?.run_id || mission?.failed_run_id || '');
  const recoveredRunId = $derived(mission?.recovery?.run_id || mission?.recovered_run_id || '');
  const failedTrace = $derived(failedRunId ? traceHydration[failedRunId] || null : null);
  const recoveredTrace = $derived(recoveredRunId ? traceHydration[recoveredRunId] || null : null);
  const liveTraceAvailable = $derived(Boolean(failedTrace || recoveredTrace));
  const displayTelemetry = $derived(hydratedTelemetry(telemetry, [failedTrace, recoveredTrace]));

  function schedulePoll() {
    if (disposed) return;
    if (pollTimer) clearTimeout(pollTimer);
    pollTimer = setTimeout(() => void loadMission(), activePoll ? 1000 : 5000);
  }

  async function loadMission() {
    try {
      const nextMission = await api.getMissionControlState();
      mission = nextMission;
      void hydrateTracePanels(nextMission);
      error = null;
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
    acting = name;
    try {
      let nextMission: MissionControlState | null = null;
      if (name === 'launch') nextMission = await api.launchMissionControl();
      if (name === 'reset') nextMission = await api.resetMissionControl();
      if (name === 'recover') nextMission = await api.recoverMissionControl();
      if (nextMission) {
        mission = nextMission;
        void hydrateTracePanels(nextMission);
      }
      error = null;
    } catch (e) {
      error = (e as Error).message;
    } finally {
      acting = null;
      schedulePoll();
    }
  }

  async function exportReplay() {
    exporting = true;
    try {
      const artifact = await api.getMissionControlReplay();
      const json = JSON.stringify(artifact, null, 2);
      const blob = new Blob([json], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = replayFileName(artifact);
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
      error = null;
    } catch (e) {
      error = (e as Error).message;
    } finally {
      exporting = false;
    }
  }

  onMount(() => {
    void loadMission();
  });

  onDestroy(() => {
    disposed = true;
    if (pollTimer) clearTimeout(pollTimer);
  });

  async function hydrateTracePanels(snapshot: MissionControlState) {
    const runIds = missionTracePanelRunIds(snapshot);
    const requestId = ++traceHydrationRequest;
    if (runIds.length === 0) {
      traceHydration = {};
      traceHydrating = false;
      return;
    }

    traceHydrating = true;
    const watch = await runningNullWatchName();
    if (disposed || requestId !== traceHydrationRequest) return;
    const traces = await hydrateMissionTracePanels(api, snapshot, watch);
    if (disposed || requestId !== traceHydrationRequest) return;

    traceHydration = traces;
    traceHydrating = false;
  }

  async function runningNullWatchName(): Promise<string | null> {
    const now = Date.now();
    if (now - traceWatchCheckedAt < 5000) return traceWatchName;
    traceWatchCheckedAt = now;

    traceWatchName = await findRunningNullWatchName(api);
    return traceWatchName;
  }

  function statusClass(value: string | undefined): string {
    if (value === 'done' || value === 'completed' || value === 'pass') return 'done';
    if (value === 'active' || value === 'running' || value === 'recovering') return 'active';
    if (value === 'error' || value === 'failed' || value === 'fail' || value === 'intervention_required') return 'error';
    if (value === 'blocked') return 'warning';
    return 'pending';
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

  function formatDuration(ms: number | undefined | null): string {
    if (ms == null || ms <= 0) return '0.0s';
    return `${(ms / 1000).toFixed(1)}s`;
  }

  function formatCost(cost: number | undefined | null): string {
    if (!cost) return '$0.000';
    return `$${cost.toFixed(3)}`;
  }

  function formatTokens(tokens: number | undefined | null): string {
    return tokens ? tokens.toLocaleString() : '0';
  }

  function formatScore(score: number | undefined | null): string {
    return score == null ? '-' : score.toFixed(2);
  }

  function observabilityHref(runId: string | null | undefined): string {
    return runId ? `/observability?run_id=${encodeURIComponent(runId)}` : '/observability';
  }

  function traceLabel(trace: MissionControlTraceRef): string {
    return trace.eval_key || trace.span_id || trace.operation;
  }

  function replayFileName(artifact: MissionControlReplayArtifact): string {
    const scenario = (artifact.scenario_id || mission?.scenario_id || 'mission').replace(/[^a-z0-9._-]+/gi, '-');
    const phase = (artifact.snapshot?.phase || mission?.phase || 'snapshot').replace(/[^a-z0-9._-]+/gi, '-');
    return `nullhub-${scenario}-${phase}-replay.json`;
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
    if (trace) return 'Live NullWatch';
    if (traceHydrating) return 'Checking NullWatch';
    return 'NullWatch unavailable';
  }

  function traceSourceSummary(): string {
    if (liveTraceAvailable) return 'Live NullWatch';
    if (traceHydrating && (failedRunId || recoveredRunId)) return 'Checking NullWatch';
    return 'NullWatch unavailable';
  }

  function tracePanelNote(): string {
    if (liveTraceAvailable) return 'Hydrated run detail';
    if (traceHydrating && (failedRunId || recoveredRunId)) return 'Looking for live traces';
    if (failedRunId || recoveredRunId) return 'No running instance';
    return 'No run ids';
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

<div class="mission-page" aria-busy={loading || acting !== null || exporting}>
  <header class="mission-header">
    <div>
      <h1>Mission Control</h1>
      <p>{mission?.headline || 'Loading mission state...'}</p>
    </div>
    <div class="actions">
      <button onclick={() => runAction('reset')} disabled={acting !== null || loading}>Reset</button>
      <button class="primary" onclick={() => runAction('launch')} disabled={!controls.can_launch || acting !== null || loading}>
        {acting === 'launch' ? 'Launching...' : 'Launch Mission'}
      </button>
      <button class="danger" onclick={() => runAction('recover')} disabled={!controls.can_recover || acting !== null || loading}>
        {acting === 'recover' ? 'Forking...' : 'Fork From Checkpoint'}
      </button>
      <button onclick={() => exportReplay()} disabled={!mission || exporting || loading}>
        {exporting ? 'Exporting...' : 'Export Replay'}
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

        {#if mission.failure}
          <div class="failure-box">
            <span>Failure</span>
            <strong>{mission.failure.failed_step}</strong>
            <p>{mission.failure.error_message}</p>
            <code>{mission.failure.checkpoint_id}</code>
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

    {#if mission.failure || mission.recovery || mission.status === 'completed'}
      <section class="comparison-panel">
        <div class="panel-heading">
          <h2>Failure Recovery</h2>
          <span>{runVerdict('failed')} -> {runVerdict('recovered')}</span>
        </div>
        <div class="comparison-grid">
          <div class="run-card failed">
            <span>Failed run</span>
            <strong>{mission.failure?.run_id || mission.failed_run_id || '-'}</strong>
            <dl>
              <div>
                <dt>Verdict</dt>
                <dd class="error">{runVerdict('failed')}</dd>
              </div>
              <div>
                <dt>Evidence</dt>
                <dd>{mission.failure?.failed_step || 'awaiting validation'}</dd>
              </div>
              <div>
                <dt>Checkpoint</dt>
                <dd>{mission.failure?.checkpoint_id || '-'}</dd>
              </div>
            </dl>
            {#if mission.failure}
              <p>{mission.failure.error_message}</p>
              {#if failedTrace}
                <p class="trace-evidence">{spanCount(failedTrace)} spans · {evalCount(failedTrace)} evals · {formatCost(traceCost(failedTrace))}</p>
              {/if}
              <a href={observabilityHref(mission.failure.run_id)}>Open failed trace</a>
            {/if}
          </div>

          <div class="run-card recovered">
            <span>Recovered run</span>
            <strong>{mission.recovery?.run_id || mission.recovered_run_id || '-'}</strong>
            <dl>
              <div>
                <dt>Verdict</dt>
                <dd class={statusClass(runVerdict('recovered'))}>{runVerdict('recovered')}</dd>
              </div>
              <div>
                <dt>Forked from</dt>
                <dd>{mission.recovery?.forked_from || mission.failure?.checkpoint_id || '-'}</dd>
              </div>
              <div>
                <dt>Instruction</dt>
                <dd>{mission.recovery?.human_instruction || mission.failure?.suggested_intervention || '-'}</dd>
              </div>
            </dl>
            {#if mission.recovery}
              <p>{mission.recovery.status}</p>
              {#if recoveredTrace}
                <p class="trace-evidence">{spanCount(recoveredTrace)} spans · {evalCount(recoveredTrace)} evals · {formatCost(traceCost(recoveredTrace))}</p>
              {/if}
              <a href={observabilityHref(mission.recovery.run_id)}>Open recovered trace</a>
            {:else}
              <p>Waiting for human checkpoint fork.</p>
            {/if}
          </div>
        </div>
      </section>
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
  .run-card span,
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
  .comparison-panel,
  .timeline-panel {
    border: 1px solid var(--border);
    background: var(--bg-surface);
    border-radius: 4px;
    padding: 1rem;
    min-width: 0;
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
  .trace-card,
  .run-card {
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

  .comparison-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 1rem;
  }

  .run-card {
    min-width: 0;
  }

  .run-card.failed {
    border-color: var(--error);
  }

  .run-card.recovered {
    border-color: var(--success);
  }

  .run-card dl {
    margin: 0.75rem 0;
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 0.65rem;
  }

  .run-card dt,
  .run-card dd {
    margin: 0;
  }

  .run-card dt {
    color: var(--fg-muted);
    font-size: 0.68rem;
    text-transform: uppercase;
    margin-bottom: 0.25rem;
  }

  .run-card dd {
    color: var(--fg);
    font-family: var(--font-mono);
    font-size: 0.78rem;
    overflow-wrap: anywhere;
  }

  .trace-card {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto auto;
    align-items: center;
    gap: 0.75rem;
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
  .trace-card strong,
  .run-card strong {
    display: block;
    margin-bottom: 0.35rem;
    color: var(--fg);
  }

  .failure-box p,
  .recovery-box p,
  .run-card p {
    color: var(--fg-muted);
    font-size: 0.8125rem;
    margin-bottom: 0.65rem;
  }

  .failure-box p.trace-evidence,
  .recovery-box p.trace-evidence,
  .run-card p.trace-evidence {
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
  .run-card a,
  .event-meta a {
    color: var(--accent);
    text-decoration: none;
    font-family: var(--font-mono);
    font-size: 0.75rem;
    overflow-wrap: anywhere;
  }

  .trace-card a,
  .failure-box a,
  .recovery-box a,
  .run-card a {
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
  .recovery-box a,
  .run-card a {
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

    .comparison-grid {
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
    .metric-grid,
    .run-card dl {
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
