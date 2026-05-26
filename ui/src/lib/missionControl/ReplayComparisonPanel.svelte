<script lang="ts">
  import type {
    MissionControlReplayArtifactPanel,
    MissionControlReplayComparison,
  } from '$lib/api/missionControl';
  import { nullboilerUiRoutes } from '$lib/orchestration/routes';
  import {
    formatTokens,
    signedMetric,
    statusClass,
  } from '$lib/missionControl/display';

  let {
    replayComparison,
    traceWatchName = null,
    boilerInstance = null,
  }: {
    replayComparison: MissionControlReplayComparison;
    traceWatchName?: string | null;
    boilerInstance?: string | null;
  } = $props();

  function nullwatchHref(runId: string | null | undefined): string {
    const params = new URLSearchParams();
    if (runId) params.set('run_id', runId);
    if (traceWatchName) params.set('watch', traceWatchName);
    const query = params.toString();
    return query ? `/nullwatch?${query}` : '/nullwatch';
  }

  function workflowRunHref(runId: string): string {
    return nullboilerUiRoutes.run(runId, { boilerInstance: boilerInstance || undefined });
  }

  function artifactWorkflowLabel(artifact: MissionControlReplayArtifactPanel): string {
    if (!artifact.workflow_run_id) return 'workflow unavailable';
    return artifact.workflow_status ? `${artifact.workflow_run_id} · ${artifact.workflow_status}` : artifact.workflow_run_id;
  }

  function artifactAnchorLabel(artifact: MissionControlReplayArtifactPanel): string {
    if (artifact.artifact_role === 'failed') return artifact.checkpoint_id || artifact.checkpoint_step || '-';
    return artifact.forked_from || artifact.human_instruction || '-';
  }
</script>

<section class="comparison-panel">
  <div class="panel-heading">
    <h2>Replay Artifacts</h2>
    <span>{`${replayComparison.failed.verdict} -> ${replayComparison.recovered.verdict}`}</span>
  </div>
  <div class="delta-strip">
    <div><span>Verdict</span><strong>{replayComparison.failed.verdict} -> {replayComparison.recovered.verdict}</strong></div>
    <div><span>New errors</span><strong class:error={replayComparison.delta.errors_delta > 0}>{signedMetric(replayComparison.delta.errors_delta)}</strong></div>
    <div><span>Extra tokens</span><strong>{signedMetric(replayComparison.delta.tokens_delta)}</strong></div>
    <div><span>Extra cost</span><strong>{signedMetric(replayComparison.delta.cost_delta_usd, 3)}</strong></div>
  </div>
  <div class="comparison-grid">
    <div class="run-card artifact-card failed">
      <span>Failed artifact</span>
      <strong>{replayComparison.failed.run_id}</strong>
      <dl>
        <div><dt>Phase</dt><dd>{replayComparison.failed.phase}</dd></div>
        <div><dt>Verdict</dt><dd class="error">{replayComparison.failed.verdict}</dd></div>
        <div><dt>Errors</dt><dd>{replayComparison.failed.telemetry.errors}</dd></div>
        <div><dt>Tokens</dt><dd>{formatTokens(replayComparison.failed.telemetry.total_tokens)}</dd></div>
      </dl>
      <p>{replayComparison.failed.failure_message || replayComparison.failed.headline}</p>
      <code>{replayComparison.failed.trace_id || '-'}</code>
      <p class="trace-evidence">Workflow {artifactWorkflowLabel(replayComparison.failed)}</p>
      <p class="trace-evidence">Checkpoint {artifactAnchorLabel(replayComparison.failed)}</p>
      <a href={nullwatchHref(replayComparison.failed.run_id)}>Open failed trace</a>
      {#if replayComparison.failed.workflow_run_id}
        <a href={workflowRunHref(replayComparison.failed.workflow_run_id)}>Open failed workflow</a>
      {/if}
    </div>

    <div class="run-card artifact-card recovered">
      <span>Recovered artifact</span>
      <strong>{replayComparison.recovered.run_id}</strong>
      <dl>
        <div><dt>Phase</dt><dd>{replayComparison.recovered.phase}</dd></div>
        <div><dt>Verdict</dt><dd class={statusClass(replayComparison.recovered.verdict)}>{replayComparison.recovered.verdict}</dd></div>
        <div><dt>Errors</dt><dd>{replayComparison.recovered.telemetry.errors}</dd></div>
        <div><dt>Tokens</dt><dd>{formatTokens(replayComparison.recovered.telemetry.total_tokens)}</dd></div>
      </dl>
      <p>{replayComparison.recovered.human_instruction || replayComparison.recovered.headline}</p>
      <code>{replayComparison.recovered.trace_id || '-'}</code>
      <p class="trace-evidence">Workflow {artifactWorkflowLabel(replayComparison.recovered)}</p>
      <p class="trace-evidence">Forked from {artifactAnchorLabel(replayComparison.recovered)}</p>
      <a href={nullwatchHref(replayComparison.recovered.run_id)}>Open recovered trace</a>
      {#if replayComparison.recovered.workflow_run_id}
        <a href={workflowRunHref(replayComparison.recovered.workflow_run_id)}>Open recovered workflow</a>
      {/if}
    </div>
  </div>
</section>

<style>
  .comparison-panel {
    border: 1px solid var(--border);
    background: var(--bg-surface);
    border-radius: 4px;
    padding: 1rem;
    min-width: 0;
  }

  .panel-heading {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }

  h2,
  p {
    margin: 0;
    letter-spacing: 0;
  }

  h2 {
    font-size: 0.9rem;
    color: var(--accent);
    text-transform: uppercase;
  }

  .panel-heading span {
    color: var(--fg-dim);
    font-size: 0.8125rem;
  }

  .delta-strip {
    margin-top: 1rem;
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 0.75rem;
  }

  .delta-strip div {
    border: 1px solid var(--border);
    border-radius: 4px;
    background: var(--bg);
    padding: 0.75rem;
    min-width: 0;
  }

  .delta-strip span,
  .run-card span {
    display: block;
    color: var(--fg-dim);
    font-size: 0.68rem;
    text-transform: uppercase;
    margin-bottom: 0.35rem;
  }

  .delta-strip strong {
    color: var(--fg);
    font-family: var(--font-mono);
    font-size: 0.95rem;
    overflow-wrap: anywhere;
  }

  .comparison-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 1rem;
  }

  .run-card {
    margin-top: 1rem;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: var(--bg);
    padding: 0.85rem;
    min-width: 0;
  }

  .run-card.failed {
    border-color: var(--error);
  }

  .run-card.recovered {
    border-color: var(--success);
  }

  .run-card strong {
    display: block;
    margin-bottom: 0.35rem;
    color: var(--fg);
  }

  .run-card dl {
    margin: 0.75rem 0;
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 0.65rem;
  }

  .run-card dt,
  .run-card dd {
    margin: 0;
  }

  .run-card dt {
    color: var(--fg-dim);
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

  .run-card p {
    color: var(--fg-dim);
    font-size: 0.8125rem;
    margin-bottom: 0.65rem;
  }

  .run-card p.trace-evidence {
    margin: 0.65rem 0 0;
    color: var(--fg-dim);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    overflow-wrap: anywhere;
  }

  code {
    display: block;
    color: var(--accent);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    overflow-wrap: anywhere;
  }

  a {
    display: inline-flex;
    width: fit-content;
    border: 1px solid var(--accent-dim);
    border-radius: 4px;
    padding: 0.35rem 0.5rem;
    margin-top: 0.65rem;
    color: var(--accent);
    text-decoration: none;
    font-family: var(--font-mono);
    font-size: 0.75rem;
    overflow-wrap: anywhere;
  }

  .done {
    color: var(--success) !important;
  }

  .error {
    color: var(--error) !important;
  }

  .pending {
    color: var(--fg-dim) !important;
  }

  @media (max-width: 1200px) {
    .comparison-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 720px) {
    .delta-strip,
    .run-card dl {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
</style>
