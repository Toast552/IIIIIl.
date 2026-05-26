import {
  BOILER_INSTANCE_QUERY_PARAM,
  TICKETS_INSTANCE_QUERY_PARAM,
  getSelectedBoilerInstance,
  getSelectedTicketsInstance,
} from "./backendSelection";

export function encodePathSegment(value: string): string {
  return encodeURIComponent(value);
}

type StackRouteOptions = {
  boilerInstance?: string;
  ticketsInstance?: string;
};

function setQueryParam(path: string, key: string, value: string): string {
  const hashIndex = path.indexOf("#");
  const withoutHash = hashIndex >= 0 ? path.slice(0, hashIndex) : path;
  const hash = hashIndex >= 0 ? path.slice(hashIndex) : "";
  const queryIndex = withoutHash.indexOf("?");
  const pathname = queryIndex >= 0 ? withoutHash.slice(0, queryIndex) : withoutHash;
  const query = queryIndex >= 0 ? withoutHash.slice(queryIndex + 1) : "";
  const params = new URLSearchParams(query);

  if (value) params.set(key, value);
  else params.delete(key);

  const nextQuery = params.toString();
  return `${pathname}${nextQuery ? `?${nextQuery}` : ""}${hash}`;
}

export function routePath(path: string): string {
  const queryIndex = path.search(/[?#]/);
  return queryIndex >= 0 ? path.slice(0, queryIndex) : path;
}

export function withBoilerInstance(path: string, boilerInstance?: string): string {
  const value = boilerInstance ?? getSelectedBoilerInstance();
  return setQueryParam(path, BOILER_INSTANCE_QUERY_PARAM, value);
}

export function withTicketsInstance(path: string, ticketsInstance?: string): string {
  const value = ticketsInstance ?? getSelectedTicketsInstance();
  return setQueryParam(path, TICKETS_INSTANCE_QUERY_PARAM, value);
}

const nullboilerUiRoot = '/nullboiler';
const nullticketsUiRoot = '/nulltickets';
const nullboilerApiRoot = '/nullboiler';
const nullticketsApiRoot = '/nulltickets';
const workflowsBase = `${nullboilerUiRoot}/workflows`;
const runsBase = `${nullboilerUiRoot}/runs`;
const storeBase = `${nullticketsApiRoot}/store`;

export const nullboilerUiRoutes = {
  dashboard: (options?: StackRouteOptions) => withBoilerInstance(nullboilerUiRoot, options?.boilerInstance),
  workflows: (options?: StackRouteOptions) => withBoilerInstance(workflowsBase, options?.boilerInstance),
  newWorkflow: (options?: StackRouteOptions) => withBoilerInstance(`${workflowsBase}/new`, options?.boilerInstance),
  workflow: (id: string, options?: StackRouteOptions) => withBoilerInstance(`${workflowsBase}/${encodePathSegment(id)}`, options?.boilerInstance),
  runs: (options?: StackRouteOptions) => withBoilerInstance(runsBase, options?.boilerInstance),
  run: (id: string, options?: StackRouteOptions) => withBoilerInstance(`${runsBase}/${encodePathSegment(id)}`, options?.boilerInstance),
  runFork: (id: string, options?: StackRouteOptions) => withBoilerInstance(`${runsBase}/${encodePathSegment(id)}/fork`, options?.boilerInstance),
};

export const nullticketsUiRoutes = {
  store: (options?: StackRouteOptions) => withTicketsInstance(`${nullticketsUiRoot}/store`, options?.ticketsInstance),
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

export const nullticketsApiPaths = {
  storeNamespace: (namespace: string) => `${storeBase}/${encodePathSegment(namespace)}`,
  storeEntry: (namespace: string, key: string) => `${storeBase}/${encodePathSegment(namespace)}/${encodePathSegment(key)}`,
};
