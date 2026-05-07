import {
  BOILER_INSTANCE_QUERY_PARAM,
  getSelectedBoilerInstance,
} from "./backendSelection";

export function encodePathSegment(value: string): string {
  return encodeURIComponent(value);
}

type OrchestrationRouteOptions = {
  boilerInstance?: string;
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

const uiRoot = '/orchestration';
const apiRoot = '/orchestration';
const workflowsBase = `${uiRoot}/workflows`;
const runsBase = `${uiRoot}/runs`;
const storeBase = `${apiRoot}/store`;

export const orchestrationUiRoutes = {
  dashboard: (options?: OrchestrationRouteOptions) => withBoilerInstance(uiRoot, options?.boilerInstance),
  workflows: (options?: OrchestrationRouteOptions) => withBoilerInstance(workflowsBase, options?.boilerInstance),
  newWorkflow: (options?: OrchestrationRouteOptions) => withBoilerInstance(`${workflowsBase}/new`, options?.boilerInstance),
  workflow: (id: string, options?: OrchestrationRouteOptions) => withBoilerInstance(`${workflowsBase}/${encodePathSegment(id)}`, options?.boilerInstance),
  runs: (options?: OrchestrationRouteOptions) => withBoilerInstance(runsBase, options?.boilerInstance),
  run: (id: string, options?: OrchestrationRouteOptions) => withBoilerInstance(`${runsBase}/${encodePathSegment(id)}`, options?.boilerInstance),
  runFork: (id: string, options?: OrchestrationRouteOptions) => withBoilerInstance(`${runsBase}/${encodePathSegment(id)}/fork`, options?.boilerInstance),
  store: () => `${uiRoot}/store`,
};

export const orchestrationApiPaths = {
  workflows: () => `${apiRoot}/workflows`,
  workflow: (id: string) => `${apiRoot}/workflows/${encodePathSegment(id)}`,
  workflowValidate: (id: string) => `${apiRoot}/workflows/${encodePathSegment(id)}/validate`,
  workflowRun: (id: string) => `${apiRoot}/workflows/${encodePathSegment(id)}/run`,
  runs: () => `${apiRoot}/runs`,
  run: (id: string) => `${apiRoot}/runs/${encodePathSegment(id)}`,
  runCancel: (id: string) => `${apiRoot}/runs/${encodePathSegment(id)}/cancel`,
  runResume: (id: string) => `${apiRoot}/runs/${encodePathSegment(id)}/resume`,
  runReplay: (id: string) => `${apiRoot}/runs/${encodePathSegment(id)}/replay`,
  runState: (id: string) => `${apiRoot}/runs/${encodePathSegment(id)}/state`,
  runsFork: () => `${apiRoot}/runs/fork`,
  runCheckpoints: (runId: string) => `${apiRoot}/runs/${encodePathSegment(runId)}/checkpoints`,
  runCheckpoint: (runId: string, checkpointId: string) => `${apiRoot}/runs/${encodePathSegment(runId)}/checkpoints/${encodePathSegment(checkpointId)}`,
  runStream: (runId: string) => `${apiRoot}/runs/${encodePathSegment(runId)}/stream`,
  storeNamespace: (namespace: string) => `${storeBase}/${encodePathSegment(namespace)}`,
  storeEntry: (namespace: string, key: string) => `${storeBase}/${encodePathSegment(namespace)}/${encodePathSegment(key)}`,
};
