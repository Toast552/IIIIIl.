import type {
  MissionControlControls,
  MissionControlPhase,
  MissionControlTelemetry,
} from '$lib/api/missionControl';
import { isAvailableTrace, type TraceHydration } from '$lib/missionControl/traceHydration';

export const emptyControls: MissionControlControls = {
  can_launch: false,
  can_recover: false,
  can_reset: true,
};

export const emptyTelemetry: MissionControlTelemetry = {
  runs: 0,
  spans: 0,
  evals: 0,
  errors: 0,
  total_tokens: 0,
  total_cost_usd: 0,
  verdict: '-',
};

export const phaseOrder: MissionControlPhase[] = [
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

export const phaseMilestones: {
  phase: MissionControlPhase;
  time: string;
  title: string;
  detail: string;
  tone?: 'error' | 'success';
}[] = [
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

export function statusClass(value: string | undefined): string {
  if (value === 'done' || value === 'completed' || value === 'pass') return 'done';
  if (value === 'active' || value === 'running' || value === 'recovering') return 'active';
  if (value === 'error' || value === 'failed' || value === 'fail' || value === 'intervention_required') return 'error';
  if (value === 'blocked') return 'warning';
  return 'pending';
}

export function formatDuration(ms: number | undefined | null): string {
  if (ms == null || ms <= 0) return '0.0s';
  return `${(ms / 1000).toFixed(1)}s`;
}

export function formatCost(cost: number | undefined | null): string {
  if (!cost) return '$0.000';
  return `$${cost.toFixed(3)}`;
}

export function formatTokens(tokens: number | undefined | null): string {
  return tokens ? tokens.toLocaleString() : '0';
}

export function formatScore(score: number | undefined | null): string {
  return score == null ? '-' : score.toFixed(2);
}

export function formatBytes(value: number | undefined | null): string {
  if (!value) return '0 B';
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

export function signedMetric(value: number, decimals = 0): string {
  const formatted = decimals > 0 ? value.toFixed(decimals) : Math.trunc(value).toLocaleString();
  return value > 0 ? `+${formatted}` : formatted;
}

export function traceSourceLabel(trace: TraceHydration | null, hydrating: boolean): string {
  if (isAvailableTrace(trace)) return 'Live NullWatch';
  if (hydrating) return 'Checking NullWatch';
  if (trace?.message) return trace.message;
  return 'NullWatch unavailable';
}

export function traceSourceSummary(options: {
  liveTraceAvailable: boolean;
  traceHydrating: boolean;
  hasRunIds: boolean;
}): string {
  if (options.liveTraceAvailable) return 'Live NullWatch';
  if (options.traceHydrating && options.hasRunIds) return 'Checking NullWatch';
  return 'NullWatch unavailable';
}

export function tracePanelNote(options: {
  liveTraceAvailable: boolean;
  traceHydrating: boolean;
  hasRunIds: boolean;
  hasWatch: boolean;
  unavailableMessage?: string | null;
}): string {
  if (options.liveTraceAvailable) return 'Hydrated run detail';
  if (options.traceHydrating && options.hasRunIds) return 'Looking for live traces';
  if (options.unavailableMessage) return options.unavailableMessage;
  if (options.hasRunIds && options.hasWatch) return 'No matching live runs';
  if (options.hasRunIds) return 'No running instance';
  return 'No run ids';
}

export function spanCount(trace: TraceHydration | null): number {
  if (!isAvailableTrace(trace)) return 0;
  return trace.summary?.span_count ?? trace.spans.length ?? 0;
}

export function evalCount(trace: TraceHydration | null): number {
  if (!isAvailableTrace(trace)) return 0;
  return trace.summary?.eval_count ?? trace.evals.length ?? 0;
}

export function errorCount(trace: TraceHydration | null): number {
  if (!isAvailableTrace(trace)) return 0;
  return trace.summary?.error_count ?? trace.spans.filter((span) => span.status === 'error' || span.error_message).length;
}

export function tokenCount(trace: TraceHydration | null): number {
  if (!isAvailableTrace(trace) || !trace.summary) return 0;
  return (trace.summary.total_input_tokens || 0) + (trace.summary.total_output_tokens || 0);
}

export function traceCost(trace: TraceHydration | null): number {
  if (!isAvailableTrace(trace)) return 0;
  return trace.summary?.total_cost_usd || 0;
}

export function traceVerdict(trace: TraceHydration | null): string | null {
  if (!isAvailableTrace(trace)) return null;
  if (trace.summary?.overall_verdict) return trace.summary.overall_verdict;
  const failedEval = trace.evals.find((evaluation) => evaluation.verdict === 'fail');
  if (failedEval) return 'fail';
  const passedEval = trace.evals.find((evaluation) => evaluation.verdict === 'pass');
  if (passedEval) return 'pass';
  return 'live';
}

export function traceSuffix(trace: TraceHydration | null): string {
  return isAvailableTrace(trace) ? ` · ${spanCount(trace)} spans · ${evalCount(trace)} evals` : '';
}

export function primaryErrorText(trace: TraceHydration | null): string {
  if (!isAvailableTrace(trace)) return '';
  const span = trace.spans.find((item) => item.status === 'error' || item.error_message);
  if (!span) return '';
  const operation = span.operation || span.tool_name || 'span';
  const detail = span.error_message || span.status || 'error';
  return `${operation}: ${detail}`;
}

export function primaryEvalText(trace: TraceHydration | null, evalKey?: string): string {
  if (!isAvailableTrace(trace)) return '';
  const evaluation =
    (evalKey ? trace.evals.find((item) => item.eval_key === evalKey) : null) ||
    trace.evals.find((item) => item.verdict === 'fail') ||
    trace.evals[0];
  if (!evaluation) return '';
  const key = evaluation.eval_key || 'eval';
  const verdict = evaluation.verdict || 'unknown';
  return `${key}: ${verdict} (${formatScore(evaluation.score)})`;
}

export function hydratedTelemetry(base: MissionControlTelemetry, traces: (TraceHydration | null)[]): MissionControlTelemetry {
  const liveTraces = traces.filter(isAvailableTrace);
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
