import { BOILER_INSTANCE_QUERY_PARAM, getSelectedBoilerInstance } from "$lib/nullstack/backendSelection";
import { encodePathSegment, withQueryParam } from "$lib/nullstack/path";

type NullBoilerRouteOptions = {
  boilerInstance?: string;
};

export function withBoilerInstance(path: string, boilerInstance?: string): string {
  const value = boilerInstance ?? getSelectedBoilerInstance();
  return withQueryParam(path, BOILER_INSTANCE_QUERY_PARAM, value);
}

const nullboilerUiRoot = "/nullboiler";
const nullboilerApiRoot = "/nullboiler";
const workflowsBase = `${nullboilerUiRoot}/workflows`;
const runsBase = `${nullboilerUiRoot}/runs`;

export const nullboilerUiRoutes = {
  dashboard: (options?: NullBoilerRouteOptions) => withBoilerInstance(nullboilerUiRoot, options?.boilerInstance),
  workflows: (options?: NullBoilerRouteOptions) => withBoilerInstance(workflowsBase, options?.boilerInstance),
  newWorkflow: (options?: NullBoilerRouteOptions) => withBoilerInstance(`${workflowsBase}/new`, options?.boilerInstance),
  workflow: (id: string, options?: NullBoilerRouteOptions) => withBoilerInstance(`${workflowsBase}/${encodePathSegment(id)}`, options?.boilerInstance),
  runs: (options?: NullBoilerRouteOptions) => withBoilerInstance(runsBase, options?.boilerInstance),
  run: (id: string, options?: NullBoilerRouteOptions) => withBoilerInstance(`${runsBase}/${encodePathSegment(id)}`, options?.boilerInstance),
  runFork: (id: string, options?: NullBoilerRouteOptions) => withBoilerInstance(`${runsBase}/${encodePathSegment(id)}/fork`, options?.boilerInstance),
};

export const nullboilerApiPaths = {
  workflows: () => `${nullboilerApiRoot}/workflows`,
  workflow: (id: string) => `${nullboilerApiRoot}/workflows/${encodePathSegment(id)}`,
  workflowValidate: (id: string) => `${nullboilerApiRoot}/workflows/${encodePathSegment(id)}/validate`,
  workflowRun: (id: string) => `${nullboilerApiRoot}/workflows/${encodePathSegment(id)}/run`,
  runs: () => `${nullboilerApiRoot}/runs`,
  run: (id: string) => `${nullboilerApiRoot}/runs/${encodePathSegment(id)}`,
  runCancel: (id: string) => `${nullboilerApiRoot}/runs/${encodePathSegment(id)}/cancel`,
  runRetry: (id: string) => `${nullboilerApiRoot}/runs/${encodePathSegment(id)}/retry`,
  runResume: (id: string) => `${nullboilerApiRoot}/runs/${encodePathSegment(id)}/resume`,
  runReplay: (id: string) => `${nullboilerApiRoot}/runs/${encodePathSegment(id)}/replay`,
  runState: (id: string) => `${nullboilerApiRoot}/runs/${encodePathSegment(id)}/state`,
  runsFork: () => `${nullboilerApiRoot}/runs/fork`,
  runCheckpoints: (runId: string) => `${nullboilerApiRoot}/runs/${encodePathSegment(runId)}/checkpoints`,
  runCheckpoint: (runId: string, checkpointId: string) => `${nullboilerApiRoot}/runs/${encodePathSegment(runId)}/checkpoints/${encodePathSegment(checkpointId)}`,
  runStream: (runId: string) => `${nullboilerApiRoot}/runs/${encodePathSegment(runId)}/stream`,
  trackerStatus: () => `${nullboilerApiRoot}/tracker/status`,
  trackerTasks: () => `${nullboilerApiRoot}/tracker/tasks`,
  trackerStats: () => `${nullboilerApiRoot}/tracker/stats`,
  trackerRefresh: () => `${nullboilerApiRoot}/tracker/refresh`,
  workers: () => `${nullboilerApiRoot}/workers`,
  worker: (id: string) => `${nullboilerApiRoot}/workers/${encodePathSegment(id)}`,
};
