import { encodePathSegment } from '$lib/orchestration/routes';

export type NullTicketsHttpMethod = 'GET' | 'POST' | 'DELETE';

export type NullTicketsActionRequest = {
  method?: NullTicketsHttpMethod;
  path: string;
  payload?: any;
  bearer_token?: string;
};

type NullTicketsActionFn = (component: string, name: string, payload: NullTicketsActionRequest) => Promise<any>;
type QueryValue = string | number | boolean | null | undefined;

function withNullTicketsQuery(path: string, params: Record<string, QueryValue>): string {
  const query = Object.entries(params)
    .filter(([, value]) => value !== null && value !== undefined && value !== '')
    .map(([key, value]) => {
      let encodedValue = encodeURIComponent(String(value));
      if (key === 'cursor') encodedValue = encodedValue.replace(/%3A/gi, ':');
      return `${encodeURIComponent(key)}=${encodedValue}`;
    })
    .join('&');
  return query ? `${path}?${query}` : path;
}

const ticketsPaths = {
  pipelines: () => '/pipelines',
  pipeline: (pipelineId: string) => `/pipelines/${encodePathSegment(pipelineId)}`,
  taskCollection: () => '/tasks',
  tasks: (params?: { pipelineId?: string; stage?: string; limit?: number; cursor?: string }) =>
    withNullTicketsQuery('/tasks', {
      pipeline_id: params?.pipelineId,
      stage: params?.stage,
      limit: params?.limit,
      cursor: params?.cursor,
    }),
  task: (taskId: string) => `/tasks/${encodePathSegment(taskId)}`,
  taskBulk: () => '/tasks/bulk',
  taskDependencies: (taskId: string) => `/tasks/${encodePathSegment(taskId)}/dependencies`,
  taskAssignments: (taskId: string) => `/tasks/${encodePathSegment(taskId)}/assignments`,
  taskAssignment: (taskId: string, agentId: string) =>
    `/tasks/${encodePathSegment(taskId)}/assignments/${encodePathSegment(agentId)}`,
  taskRunState: (taskId: string) => `/tasks/${encodePathSegment(taskId)}/run-state`,
  leasesClaim: () => '/leases/claim',
  leaseHeartbeat: (leaseId: string) => `/leases/${encodePathSegment(leaseId)}/heartbeat`,
  runEvents: (runId: string, params?: { limit?: number; cursor?: string }) =>
    withNullTicketsQuery(`/runs/${encodePathSegment(runId)}/events`, {
      limit: params?.limit,
      cursor: params?.cursor,
    }),
  runEventTarget: (runId: string) => `/runs/${encodePathSegment(runId)}/events`,
  runTransition: (runId: string) => `/runs/${encodePathSegment(runId)}/transition`,
  runFail: (runId: string) => `/runs/${encodePathSegment(runId)}/fail`,
  artifacts: (params?: { taskId?: string; runId?: string; limit?: number; cursor?: string }) =>
    withNullTicketsQuery('/artifacts', {
      task_id: params?.taskId,
      run_id: params?.runId,
      limit: params?.limit,
      cursor: params?.cursor,
    }),
  artifactCollection: () => '/artifacts',
};

export function createNullTicketsApi(action: NullTicketsActionFn) {
  return {
    nullTicketsAction: action,
    nullTicketsPipelines: (c: string, n: string) =>
      action(c, n, { method: 'GET', path: ticketsPaths.pipelines() }),
    nullTicketsTasks: (
      c: string,
      n: string,
      params?: { pipelineId?: string; stage?: string; limit?: number; cursor?: string },
    ) =>
      action(c, n, {
        method: 'GET',
        path: ticketsPaths.tasks(params),
      }),
    nullTicketsCreateTask: (c: string, n: string, payload: any) =>
      action(c, n, { method: 'POST', path: ticketsPaths.taskCollection(), payload }),
    nullTicketsBulkCreateTasks: (c: string, n: string, tasks: any[]) =>
      action(c, n, { method: 'POST', path: ticketsPaths.taskBulk(), payload: { tasks } }),
    nullTicketsClaimTask: (c: string, n: string, payload: any) =>
      action(c, n, { method: 'POST', path: ticketsPaths.leasesClaim(), payload }),
    nullTicketsHeartbeatLease: (c: string, n: string, leaseId: string, bearerToken: string) =>
      action(c, n, {
        method: 'POST',
        path: ticketsPaths.leaseHeartbeat(leaseId),
        bearer_token: bearerToken,
      }),
    nullTicketsCreatePipeline: (c: string, n: string, payload: any) =>
      action(c, n, { method: 'POST', path: ticketsPaths.pipelines(), payload }),
    nullTicketsGetPipeline: (c: string, n: string, pipelineId: string) =>
      action(c, n, { method: 'GET', path: ticketsPaths.pipeline(pipelineId) }),
    nullTicketsGetTask: (c: string, n: string, taskId: string) =>
      action(c, n, { method: 'GET', path: ticketsPaths.task(taskId) }),
    nullTicketsAssignTask: (c: string, n: string, taskId: string, payload: any) =>
      action(c, n, {
        method: 'POST',
        path: ticketsPaths.taskAssignments(taskId),
        payload,
      }),
    nullTicketsUnassignTask: (c: string, n: string, taskId: string, agentId: string) =>
      action(c, n, {
        method: 'DELETE',
        path: ticketsPaths.taskAssignment(taskId, agentId),
      }),
    nullTicketsAddDependency: (c: string, n: string, taskId: string, payload: any) =>
      action(c, n, {
        method: 'POST',
        path: ticketsPaths.taskDependencies(taskId),
        payload,
      }),
    nullTicketsGetRunState: (c: string, n: string, taskId: string) =>
      action(c, n, {
        method: 'GET',
        path: ticketsPaths.taskRunState(taskId),
      }),
    nullTicketsRunEvents: (
      c: string,
      n: string,
      runId: string,
      params?: { limit?: number; cursor?: string },
    ) =>
      action(c, n, {
        method: 'GET',
        path: ticketsPaths.runEvents(runId, params),
      }),
    nullTicketsAddRunEvent: (c: string, n: string, runId: string, payload: any, bearerToken: string) =>
      action(c, n, {
        method: 'POST',
        path: ticketsPaths.runEventTarget(runId),
        payload,
        bearer_token: bearerToken,
      }),
    nullTicketsTransitionRun: (c: string, n: string, runId: string, payload: any, bearerToken: string) =>
      action(c, n, {
        method: 'POST',
        path: ticketsPaths.runTransition(runId),
        payload,
        bearer_token: bearerToken,
      }),
    nullTicketsFailRun: (c: string, n: string, runId: string, payload: any, bearerToken: string) =>
      action(c, n, {
        method: 'POST',
        path: ticketsPaths.runFail(runId),
        payload,
        bearer_token: bearerToken,
      }),
    nullTicketsArtifacts: (
      c: string,
      n: string,
      params?: { taskId?: string; runId?: string; limit?: number; cursor?: string },
    ) =>
      action(c, n, {
        method: 'GET',
        path: ticketsPaths.artifacts(params),
      }),
    nullTicketsCreateArtifact: (c: string, n: string, payload: any) =>
      action(c, n, { method: 'POST', path: ticketsPaths.artifactCollection(), payload }),
  };
}
