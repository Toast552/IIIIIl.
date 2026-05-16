<script lang="ts">
  import { onDestroy } from "svelte";
  import { api } from "$lib/api/client";
  import { orchestrationUiRoutes } from "$lib/orchestration/routes";
  import GraphViewer from "$lib/components/orchestration/GraphViewer.svelte";
  import StateInspector from "$lib/components/orchestration/StateInspector.svelte";
  import RunEventLog from "$lib/components/orchestration/RunEventLog.svelte";
  import CheckpointTimeline from "$lib/components/orchestration/CheckpointTimeline.svelte";
  import type { RunStreamHandle } from "$lib/api/orchestration";

  type Workflow = {
    id?: string;
    name?: string;
    version?: number;
    nodes?: Record<string, any>;
    edges?: any[];
    state_schema?: any;
    definition?: any;
    created_at?: string;
    updated_at?: string;
    created_at_ms?: number;
    updated_at_ms?: number;
  };

  type Run = {
    id?: string;
    workflow_id?: string;
    workflow_name?: string;
    status?: string;
    created_at?: string;
    started_at?: string;
    completed_at?: string;
    updated_at?: string;
    interrupt_message?: string;
    error_text?: string;
    state?: any;
    input?: any;
    workflow?: any;
    steps?: any[];
  };

  type TrackerTask = {
    task_id?: string;
    task_title?: string;
    pipeline_id?: string;
    agent_role?: string;
    execution?: string;
    current_turn?: number;
    max_turns?: number;
    started_at_ms?: number;
    last_activity_ms?: number;
    state?: string;
  };

  type Worker = {
    id?: string;
    url?: string;
    protocol?: string;
    model?: string | null;
    tags?: any[];
    max_concurrent?: number;
    source?: string;
    status?: string;
    consecutive_failures?: number;
    circuit_open_until_ms?: number;
    last_error_text?: string;
    created_at_ms?: number;
  };

  type LoadRunsOptions = {
    keepSelection?: boolean;
    append?: boolean;
    refreshDetail?: boolean;
  };

  let { component, name, active = false, running = false } = $props<{
    component: string;
    name: string;
    active?: boolean;
    running?: boolean;
  }>();

  const emptyWorkflow = () => ({
    id: "",
    name: "",
    state_schema: {},
    nodes: {},
    edges: [],
  });

  let panelView = $state<"workflows" | "editor" | "runs" | "workers" | "tracker">("workflows");
  let loadKey = $state("");
  let loading = $state(false);
  let actionLoading = $state(false);
  let detailLoading = $state(false);
  let error = $state("");
  let message = $state("");

  let workflows = $state<Workflow[]>([]);
  let selectedWorkflowId = $state("");
  let workflowEditorMode = $state<"edit" | "create">("edit");
  let workflowJson = $state(JSON.stringify(emptyWorkflow(), null, 2));
  let workflowParseError = $state("");
  let parsedWorkflow = $state<any>(emptyWorkflow());
  let workflowInput = $state("{}");
  let validationResult = $state<any>(null);
  let workflowDeleteConfirm = $state("");

  let runs = $state<Run[]>([]);
  let runStatusFilter = $state("");
  let runWorkflowFilter = $state("");
  let runLimit = $state("50");
  let runsHasMore = $state(false);
  let runsNextOffset = $state<number | null>(null);
  let runsQueryKey = $state("");
  let selectedRunId = $state("");
  let selectedRun = $state<Run | null>(null);
  let selectedRunWorkflow = $state<any>({ nodes: {}, edges: [] });
  let runNodeStatus = $state<Record<string, string>>({});
  let previousRunState = $state<any>(null);
  let runEvents = $state<any[]>([]);
  let streamRunId = $state("");
  let resumeUpdates = $state("{}");
  let stateUpdates = $state("{}");
  let stateApplyAfterStep = $state("");
  let checkpoints = $state<any[]>([]);
  let selectedCheckpointId = $state("");
  let selectedCheckpointState = $state<any>(null);
  let checkpointOverrides = $state("{}");
  let checkpointOverridesValid = $state(true);
  let runStream: RunStreamHandle | null = null;
  let runDetailRequestSeq = 0;

  let trackerStatus = $state<any>(null);
  let trackerStats = $state<any>(null);
  let trackerTasks = $state<TrackerTask[]>([]);
  let selectedTrackerTaskId = $state("");

  let workers = $state<Worker[]>([]);
  let selectedWorkerId = $state("");
  let workerDeleteConfirm = $state("");
  let workerIdValue = $state("");
  let workerUrlValue = $state("");
  let workerProtocolValue = $state("webhook");
  let workerTokenValue = $state("");
  let workerModelValue = $state("");
  let workerTagsValue = $state("[]");
  let workerMaxConcurrentValue = $state("1");

  const selectedWorkflow = $derived(
    workflows.find((workflow) => workflowId(workflow) === selectedWorkflowId) || null,
  );
  const selectedTrackerTask = $derived(
    trackerTasks.find((task) => trackerTaskId(task) === selectedTrackerTaskId) || null,
  );
  const selectedWorker = $derived(
    workers.find((worker) => workerId(worker) === selectedWorkerId) || null,
  );
  const workflowGraph = $derived(parsedWorkflow || selectedWorkflow || { nodes: {}, edges: [] });
  const runCounts = $derived.by(() => {
    const counts: Record<string, number> = {};
    for (const run of runs) {
      const status = run.status || "unknown";
      counts[status] = (counts[status] || 0) + 1;
    }
    return counts;
  });

  function workflowId(workflow: Workflow | null | undefined): string {
    return String(workflow?.id || "");
  }

  function workflowName(workflow: Workflow | null | undefined): string {
    return String(workflow?.name || workflow?.id || "workflow");
  }

  function runId(run: Run | null | undefined): string {
    return String(run?.id || "");
  }

  function runTitle(run: Run | null | undefined): string {
    return String(run?.workflow_name || run?.workflow_id || run?.id || "run");
  }

  function trackerTaskId(task: TrackerTask | null | undefined): string {
    return String(task?.task_id || "");
  }

  function workerId(worker: Worker | null | undefined): string {
    return String(worker?.id || "");
  }

  function workerTitle(worker: Worker | null | undefined): string {
    return String(worker?.id || worker?.url || "worker");
  }

  function boilerOptions() {
    return { boilerInstance: name };
  }

  function nodeCount(workflow: Workflow | null | undefined): number {
    return workflow?.nodes ? Object.keys(workflow.nodes).length : 0;
  }

  function edgeCount(workflow: Workflow | null | undefined): number {
    return Array.isArray(workflow?.edges) ? workflow.edges.length : 0;
  }

  function formatTime(value: string | number | undefined | null): string {
    if (!value) return "-";
    const ts = typeof value === "number" ? value : Date.parse(value);
    if (!Number.isFinite(ts)) return "-";
    return new Date(ts).toLocaleString();
  }

  function formatDuration(run: Run | null | undefined): string {
    const startValue = run?.started_at || run?.created_at;
    if (!startValue) return "-";
    const start = Date.parse(startValue);
    if (!Number.isFinite(start)) return "-";
    const end = run.completed_at ? Date.parse(run.completed_at) : Date.now();
    const seconds = Math.max(0, Math.floor((end - start) / 1000));
    if (seconds < 60) return `${seconds}s`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m ${seconds % 60}s`;
    const hours = Math.floor(minutes / 60);
    return `${hours}h ${minutes % 60}m`;
  }

  function jsonPreview(value: any): string {
    if (value === null || value === undefined) return "{}";
    try {
      return JSON.stringify(value, null, 2);
    } catch {
      return String(value);
    }
  }

  function parseJsonField(raw: string, fallback: any): any {
    const trimmed = raw.trim();
    if (!trimmed) return fallback;
    return JSON.parse(trimmed);
  }

  function boundedInt(raw: string, fallback: number, min: number, max: number): number {
    const value = Number.parseInt(raw || String(fallback), 10);
    if (!Number.isFinite(value)) return fallback;
    return Math.min(max, Math.max(min, value));
  }

  function runFiltersKey(): string {
    return JSON.stringify({
      status: runStatusFilter || "",
      workflow: runWorkflowFilter || "",
      limit: boundedInt(runLimit, 50, 1, 250),
    });
  }

  function runQueryParams(offset = 0) {
    return {
      boilerInstance: name,
      status: runStatusFilter || undefined,
      workflow_id: runWorkflowFilter || undefined,
      limit: boundedInt(runLimit, 50, 1, 250),
      offset,
    };
  }

  function editableWorkflowPayload(workflow: any): any {
    const source =
      workflow?.definition && typeof workflow.definition === "object" && !Array.isArray(workflow.definition)
        ? workflow.definition
        : workflow || {};
    const payload = { ...source };
    delete payload.definition;
    delete payload.created_at;
    delete payload.updated_at;
    delete payload.created_at_ms;
    delete payload.updated_at_ms;

    payload.id = workflow?.id ?? payload.id ?? "";
    payload.name = workflow?.name ?? payload.name ?? "";
    if (workflow?.version != null) payload.version = workflow.version;
    if (!payload.nodes && workflow?.nodes) payload.nodes = workflow.nodes;
    if (!payload.edges && workflow?.edges) payload.edges = workflow.edges;
    if (!payload.state_schema && workflow?.state_schema) payload.state_schema = workflow.state_schema;
    return payload;
  }

  function setWorkflowJson(value: string) {
    workflowJson = value;
    try {
      parsedWorkflow = JSON.parse(value || "{}");
      workflowParseError = "";
    } catch (e) {
      workflowParseError = (e as Error).message;
    }
  }

  function handleWorkflowJsonInput(e: Event) {
    setWorkflowJson((e.target as HTMLTextAreaElement).value);
  }

  function handleCheckpointOverridesInput(e: Event) {
    checkpointOverrides = (e.target as HTMLTextAreaElement).value;
    try {
      JSON.parse(checkpointOverrides || "{}");
      checkpointOverridesValid = true;
    } catch {
      checkpointOverridesValid = false;
    }
  }

  function buildNodeStatus(run: Run | null): Record<string, string> {
    const status: Record<string, string> = {};
    for (const step of run?.steps || []) {
      const nodeId = step?.node_id || step?.def_step_id || step?.step;
      if (nodeId) status[String(nodeId)] = String(step?.status || "pending");
    }
    return status;
  }

  function resetRunDetail() {
    runDetailRequestSeq += 1;
    closeRunStream();
    selectedRunId = "";
    selectedRun = null;
    selectedRunWorkflow = { nodes: {}, edges: [] };
    runNodeStatus = {};
    previousRunState = null;
    runEvents = [];
    checkpoints = [];
    selectedCheckpointId = "";
    selectedCheckpointState = null;
    streamRunId = "";
  }

  function closeRunStream() {
    if (runStream) {
      runStream.close();
      runStream = null;
    }
  }

  function connectRunStream(id: string) {
    if (!id || component !== "nullboiler" || !running) return;
    const sameRun = streamRunId === id;
    if (sameRun && runStream && !runStream.closed) return;
    const resetEvents = !sameRun || Boolean(runStream?.closed);
    closeRunStream();
    streamRunId = id;
    if (resetEvents) runEvents = [];
    try {
      runStream = api.streamRun(
        id,
        (event: any) => {
          if (selectedRunId !== id) return;
          runEvents = [...runEvents, { ...event, timestamp: event.timestamp ?? Date.now() / 1000 }];
          if (
            [
              "step_completed",
              "step_failed",
              "run_completed",
              "run_failed",
              "interrupted",
              "state_update",
              "values",
              "updates",
              "task_result",
            ].includes(event.type)
          ) {
            void loadRunDetail(id, false);
          }
        },
        boilerOptions(),
      );
    } catch {
      runStream = null;
    }
  }

  async function refreshAll() {
    if (component !== "nullboiler" || !running) return;
    loading = true;
    error = "";
    try {
      await Promise.all([
        loadWorkflows(),
        loadRuns({ keepSelection: true, refreshDetail: true }),
        loadTracker(),
        loadWorkers(),
      ]);
    } finally {
      loading = false;
    }
  }

  async function loadWorkflows() {
    if (component !== "nullboiler" || !running) return;
    try {
      workflows = (await api.listWorkflows(boilerOptions())) || [];
      if (!selectedWorkflowId || !workflows.some((workflow) => workflowId(workflow) === selectedWorkflowId)) {
        selectedWorkflowId = workflowId(workflows[0] || {});
      }
      if (workflowDeleteConfirm && !workflows.some((workflow) => workflowId(workflow) === workflowDeleteConfirm)) {
        workflowDeleteConfirm = "";
      }
    } catch (e) {
      error = (e as Error).message;
    }
  }

  async function loadWorkflowForEdit(id: string) {
    if (!id || component !== "nullboiler" || !running) return;
    detailLoading = true;
    error = "";
    try {
      const workflow = await api.getWorkflow(id, boilerOptions());
      selectedWorkflowId = workflowId(workflow) || id;
      workflowEditorMode = "edit";
      validationResult = null;
      setWorkflowJson(JSON.stringify(editableWorkflowPayload(workflow), null, 2));
      panelView = "editor";
    } catch (e) {
      error = (e as Error).message;
    } finally {
      detailLoading = false;
    }
  }

  async function openWorkflowEditor() {
    if (panelView === "editor") return;
    if (selectedWorkflowId) {
      await loadWorkflowForEdit(selectedWorkflowId);
    } else {
      newWorkflow();
    }
  }

  function newWorkflow() {
    selectedWorkflowId = "";
    workflowEditorMode = "create";
    validationResult = null;
    workflowDeleteConfirm = "";
    setWorkflowJson(JSON.stringify(emptyWorkflow(), null, 2));
    panelView = "editor";
  }

  async function saveWorkflow() {
    if (workflowParseError || component !== "nullboiler" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const payload = parseJsonField(workflowJson, {});
      if (workflowEditorMode === "create") {
        const result = await api.createWorkflow(payload, boilerOptions());
        const id = String(result?.id || payload?.id || "");
        message = `Workflow ${id || payload?.name || ""} created`.trim();
        await loadWorkflows();
        if (id) await loadWorkflowForEdit(id);
      } else {
        const id = selectedWorkflowId || String(payload?.id || "");
        if (!id) throw new Error("Workflow id is required");
        await api.updateWorkflow(id, payload, boilerOptions());
        message = "Workflow saved";
        await loadWorkflows();
        await loadWorkflowForEdit(id);
      }
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function deleteWorkflow() {
    const id = selectedWorkflowId;
    if (!id || component !== "nullboiler" || !running) return;
    if (workflowDeleteConfirm !== id) {
      workflowDeleteConfirm = id;
      return;
    }

    actionLoading = true;
    error = "";
    message = "";
    try {
      await api.deleteWorkflow(id, boilerOptions());
      message = "Workflow deleted";
      selectedWorkflowId = "";
      workflowDeleteConfirm = "";
      validationResult = null;
      setWorkflowJson(JSON.stringify(emptyWorkflow(), null, 2));
      await loadWorkflows();
      await loadRuns({ keepSelection: false });
      panelView = "workflows";
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function validateWorkflow() {
    if (!selectedWorkflowId || workflowEditorMode === "create" || component !== "nullboiler" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    validationResult = null;
    try {
      validationResult = await api.validateWorkflow(selectedWorkflowId, boilerOptions());
      message = validationResult?.valid ? "Workflow is valid" : "Workflow has validation errors";
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function startWorkflowRun(workflowIdValue: string, inputRaw = workflowInput) {
    const id = workflowIdValue.trim();
    if (!id || component !== "nullboiler" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const input = parseJsonField(inputRaw, {});
      const result = await api.runWorkflow(id, { input }, boilerOptions());
      const runIdValue = String(result?.id || "");
      message = `Run ${runIdValue || ""} started`.trim();
      await loadRuns({ keepSelection: false });
      if (runIdValue) {
        panelView = "runs";
        await loadRunDetail(runIdValue, true);
      }
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function runWorkflow() {
    if (!selectedWorkflowId || workflowEditorMode === "create") return;
    await startWorkflowRun(selectedWorkflowId, workflowInput);
  }

  async function loadRuns(options: LoadRunsOptions = {}) {
    if (component !== "nullboiler" || !running) return;
    const keepSelection = options.keepSelection ?? true;
    const append = options.append ?? false;
    const refreshDetail = options.refreshDetail ?? !append;
    try {
      const queryKey = runFiltersKey();
      const canAppend = append && runsQueryKey === queryKey && runsNextOffset !== null;
      const page = await api.listRunsPage(runQueryParams(canAppend ? runsNextOffset || 0 : 0));
      const nextItems = page?.items || [];
      if (canAppend) {
        const seen = new Set(runs.map(runId));
        runs = [...runs, ...nextItems.filter((run) => !seen.has(runId(run)))];
      } else {
        runs = nextItems;
      }
      runsQueryKey = queryKey;
      runsHasMore = Boolean(page?.hasMore && typeof page?.nextOffset === "number");
      runsNextOffset = runsHasMore ? page.nextOffset || 0 : null;

      const selectedStillVisible = selectedRunId && runs.some((run) => runId(run) === selectedRunId);
      if (keepSelection && selectedStillVisible) {
        if (refreshDetail) await loadRunDetail(selectedRunId, false);
        return;
      }
      if (runs.length > 0) {
        const nextRunId = runId(runs[0]);
        if (nextRunId) await loadRunDetail(nextRunId, false);
      } else if (!append || !keepSelection) {
        resetRunDetail();
      }
    } catch (e) {
      error = (e as Error).message;
    }
  }

  async function loadMoreRuns() {
    if (!runsHasMore || runsNextOffset === null) return;
    await loadRuns({ keepSelection: true, append: true, refreshDetail: false });
  }

  async function loadRunDetail(id: string, openRuns = true) {
    if (!id || component !== "nullboiler" || !running) return;
    const requestSeq = ++runDetailRequestSeq;
    detailLoading = true;
    error = "";
    try {
      const sameRun = selectedRunId === id;
      const previous = sameRun ? selectedRun?.state || null : null;
      const data = await api.getRun(id, boilerOptions());
      if (requestSeq !== runDetailRequestSeq) return;
      selectedRunId = id;
      previousRunState = previous;
      selectedRun = data;
      runNodeStatus = buildNodeStatus(data);
      if (data?.workflow) {
        selectedRunWorkflow = data.workflow;
      } else if (data?.workflow_id) {
        try {
          const workflow = await api.getWorkflow(data.workflow_id, boilerOptions());
          if (requestSeq !== runDetailRequestSeq) return;
          selectedRunWorkflow = workflow;
        } catch {
          if (requestSeq !== runDetailRequestSeq) return;
          selectedRunWorkflow = { nodes: {}, edges: [] };
        }
      } else {
        selectedRunWorkflow = { nodes: {}, edges: [] };
      }
      await loadCheckpoints(id, requestSeq);
      if (requestSeq !== runDetailRequestSeq) return;
      connectRunStream(id);
      if (openRuns) panelView = "runs";
    } catch (e) {
      if (requestSeq === runDetailRequestSeq) error = (e as Error).message;
    } finally {
      if (requestSeq === runDetailRequestSeq) detailLoading = false;
    }
  }

  async function cancelRun() {
    if (!selectedRunId || component !== "nullboiler" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      await api.cancelRun(selectedRunId, boilerOptions());
      message = "Run cancelled";
      await loadRunDetail(selectedRunId, false);
      await loadRuns({ keepSelection: true, refreshDetail: false });
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function retryRun() {
    if (!selectedRunId || component !== "nullboiler" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const result = await api.retryRun(selectedRunId, boilerOptions());
      message = `Retry ${result?.id || selectedRunId} started`;
      await loadRunDetail(String(result?.id || selectedRunId), false);
      await loadRuns({ keepSelection: true, refreshDetail: false });
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function resumeRun() {
    if (!selectedRunId || component !== "nullboiler" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const updates = parseJsonField(resumeUpdates, {});
      await api.resumeRun(selectedRunId, updates, boilerOptions());
      message = "Run resumed";
      resumeUpdates = "{}";
      await loadRunDetail(selectedRunId, false);
      await loadRuns({ keepSelection: true, refreshDetail: false });
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function injectState() {
    if (!selectedRunId || component !== "nullboiler" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const updates = parseJsonField(stateUpdates, {});
      const result = await api.injectState(
        selectedRunId,
        updates,
        stateApplyAfterStep.trim() || undefined,
        boilerOptions(),
      );
      message = result?.pending ? "State injection queued" : "State updated";
      stateUpdates = "{}";
      stateApplyAfterStep = "";
      await loadRunDetail(selectedRunId, false);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  function isCurrentRunRequest(runIdValue: string, requestSeq?: number): boolean {
    return selectedRunId === runIdValue && (requestSeq === undefined || requestSeq === runDetailRequestSeq);
  }

  async function loadCheckpoints(runIdValue = selectedRunId, requestSeq?: number) {
    if (!runIdValue || component !== "nullboiler" || !running) return;
    if (requestSeq !== undefined && requestSeq !== runDetailRequestSeq) return;
    checkpoints = [];
    selectedCheckpointId = "";
    selectedCheckpointState = null;
    try {
      const nextCheckpoints = (await api.listCheckpoints(runIdValue, boilerOptions())) || [];
      if (!isCurrentRunRequest(runIdValue, requestSeq)) return;
      checkpoints = nextCheckpoints;
      const latestCheckpointId = String(nextCheckpoints[nextCheckpoints.length - 1]?.id || "");
      if (latestCheckpointId) {
        await selectCheckpoint(latestCheckpointId, runIdValue, requestSeq);
      }
    } catch {
      if (!isCurrentRunRequest(runIdValue, requestSeq)) return;
      checkpoints = [];
      selectedCheckpointId = "";
      selectedCheckpointState = null;
    }
  }

  async function selectCheckpoint(id: string, runIdValue = selectedRunId, requestSeq?: number) {
    if (!id || !runIdValue || component !== "nullboiler" || !running) return;
    if (!isCurrentRunRequest(runIdValue, requestSeq)) return;
    selectedCheckpointId = id;
    try {
      const checkpoint = await api.getCheckpoint(runIdValue, id, boilerOptions());
      if (!isCurrentRunRequest(runIdValue, requestSeq) || selectedCheckpointId !== id) return;
      selectedCheckpointState = checkpoint?.state || checkpoint;
    } catch (e) {
      if (isCurrentRunRequest(runIdValue, requestSeq) && selectedCheckpointId === id) {
        error = (e as Error).message;
      }
    }
  }

  async function forkRun() {
    if (!selectedCheckpointId || !checkpointOverridesValid || component !== "nullboiler" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const overrides = parseJsonField(checkpointOverrides, {});
      const result = await api.forkRun(
        selectedCheckpointId,
        Object.keys(overrides).length > 0 ? overrides : undefined,
        boilerOptions(),
      );
      const id = String(result?.id || "");
      message = `Fork ${id || ""} started`.trim();
      await loadRuns({ keepSelection: false });
      if (id) await loadRunDetail(id, true);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function replayRun() {
    if (!selectedRunId || !selectedCheckpointId || component !== "nullboiler" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      await api.replayRun(selectedRunId, selectedCheckpointId, boilerOptions());
      message = "Run replay started";
      await loadRunDetail(selectedRunId, false);
      await loadRuns({ keepSelection: true, refreshDetail: false });
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function loadWorkers() {
    if (component !== "nullboiler" || !running) return;
    try {
      workers = (await api.listWorkers(boilerOptions())) || [];
      if (!selectedWorkerId || !workers.some((worker) => workerId(worker) === selectedWorkerId)) {
        selectedWorkerId = workerId(workers[0] || {});
      }
      if (workerDeleteConfirm && !workers.some((worker) => workerId(worker) === workerDeleteConfirm)) {
        workerDeleteConfirm = "";
      }
    } catch (e) {
      if (panelView === "workers") error = (e as Error).message;
    }
  }

  async function registerWorker() {
    if (!workerIdValue.trim() || !workerUrlValue.trim() || component !== "nullboiler" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const payload: Record<string, any> = {
        id: workerIdValue.trim(),
        url: workerUrlValue.trim(),
        protocol: workerProtocolValue.trim() || "webhook",
        token: workerTokenValue,
        tags: parseJsonField(workerTagsValue, []),
        max_concurrent: boundedInt(workerMaxConcurrentValue, 1, 1, 1_000_000),
      };
      if (workerModelValue.trim()) payload.model = workerModelValue.trim();
      const result = await api.registerWorker(payload, boilerOptions());
      const id = String(result?.id || workerIdValue.trim());
      message = `Worker ${id} registered`;
      workerIdValue = "";
      workerUrlValue = "";
      workerTokenValue = "";
      workerModelValue = "";
      workerTagsValue = "[]";
      workerMaxConcurrentValue = "1";
      await loadWorkers();
      selectedWorkerId = id;
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function deleteWorker() {
    if (!selectedWorkerId || component !== "nullboiler" || !running) return;
    if (workerDeleteConfirm !== selectedWorkerId) {
      workerDeleteConfirm = selectedWorkerId;
      return;
    }
    actionLoading = true;
    error = "";
    message = "";
    try {
      await api.deleteWorker(selectedWorkerId, boilerOptions());
      message = "Worker deleted";
      workerDeleteConfirm = "";
      selectedWorkerId = "";
      await loadWorkers();
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function loadTracker() {
    if (component !== "nullboiler" || !running) return;
    try {
      const status = await api.getBoilerTrackerStatus(boilerOptions());
      trackerStatus = status;
      trackerTasks = Array.isArray(status?.running) ? status.running : [];
      try {
        const tasks = await api.getBoilerTrackerTasks(boilerOptions());
        if (Array.isArray(tasks)) trackerTasks = tasks;
      } catch {
        /* keep status.running as fallback */
      }
      try {
        trackerStats = await api.getBoilerTrackerStats(boilerOptions());
      } catch {
        trackerStats = null;
      }
      if (!selectedTrackerTaskId || !trackerTasks.some((task) => trackerTaskId(task) === selectedTrackerTaskId)) {
        selectedTrackerTaskId = trackerTaskId(trackerTasks[0] || {});
      }
      if (panelView === "tracker") error = "";
    } catch (e) {
      trackerStatus = null;
      trackerStats = null;
      trackerTasks = [];
      if (panelView === "tracker") error = (e as Error).message;
    }
  }

  async function refreshTracker() {
    if (component !== "nullboiler" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const result = await api.refreshBoilerTracker(boilerOptions());
      message = result?.message || "Tracker refresh requested";
      await loadTracker();
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  $effect(() => {
    const key = `${component}/${name}/${active}/${running}`;
    if (component !== "nullboiler" || !active) {
      closeRunStream();
      return;
    }
    if (loadKey === key) return;
    loadKey = key;
    error = "";
    message = "";
    validationResult = null;
    workflowDeleteConfirm = "";
    workerDeleteConfirm = "";
    selectedWorkerId = "";
    setWorkflowJson(JSON.stringify(emptyWorkflow(), null, 2));
    resetRunDetail();
    if (!running) return;
    void refreshAll();
  });

  onDestroy(() => {
    closeRunStream();
  });
</script>

<div class="boiler-panel">
  {#if !running}
    <div class="empty-state">Instance is stopped.</div>
  {:else}
    <div class="boiler-header">
      <div class="boiler-tabs" role="tablist" aria-label="NullBoiler views">
        <button class:active={panelView === "workflows"} onclick={() => (panelView = "workflows")}>
          Workflows
        </button>
        <button class:active={panelView === "editor"} onclick={() => { void openWorkflowEditor(); }}>
          Editor
        </button>
        <button class:active={panelView === "runs"} onclick={() => (panelView = "runs")}>
          Runs
        </button>
        <button class:active={panelView === "workers"} onclick={() => (panelView = "workers")}>
          Workers
        </button>
        <button class:active={panelView === "tracker"} onclick={() => (panelView = "tracker")}>
          Tracker
        </button>
      </div>
      <div class="header-actions">
        <button class="btn" onclick={newWorkflow} disabled={actionLoading}>New Workflow</button>
        <button class="btn subtle" onclick={refreshAll} disabled={loading || actionLoading}>
          {loading ? "Refreshing..." : "Refresh"}
        </button>
      </div>
    </div>

    {#if error}
      <div class="error-banner">{error}</div>
    {/if}
    {#if message}
      <div class="message-banner">{message}</div>
    {/if}

    {#if panelView === "workflows"}
      <div class="boiler-grid">
        <section class="boiler-section">
          <div class="section-header">
            <h3>Workflows</h3>
            <span>{workflows.length}</span>
          </div>
          <div class="list">
            {#if workflows.length === 0}
              <div class="empty-row">No workflows</div>
            {:else}
              {#each workflows as workflow}
                <button
                  class="row"
                  class:active={workflowId(workflow) === selectedWorkflowId}
                  onclick={() => (selectedWorkflowId = workflowId(workflow))}
                >
                  <span class="row-title">{workflowName(workflow)}</span>
                  <span class="row-meta">
                    {workflowId(workflow)} / v{workflow.version ?? 1} / {nodeCount(workflow)} nodes
                  </span>
                </button>
              {/each}
            {/if}
          </div>
          <div class="action-row">
            <button class="btn" onclick={() => loadWorkflowForEdit(selectedWorkflowId)} disabled={!selectedWorkflowId || detailLoading}>
              Edit
            </button>
            <button class="btn danger" onclick={deleteWorkflow} disabled={!selectedWorkflowId || actionLoading}>
              {workflowDeleteConfirm === selectedWorkflowId ? "Confirm Delete" : "Delete"}
            </button>
          </div>
          <a class="btn subtle" href={orchestrationUiRoutes.workflows({ boilerInstance: name })}>
            Open Full Page
          </a>
        </section>

        <section class="boiler-section">
          <div class="section-header">
            <h3>Selected Workflow</h3>
          </div>
          {#if selectedWorkflow}
            <div class="detail-stack">
              <div class="detail-title">
                <span>{workflowName(selectedWorkflow)}</span>
                <code>{workflowId(selectedWorkflow)}</code>
              </div>
              <div class="stats-grid">
                <div><span>Nodes</span><strong>{nodeCount(selectedWorkflow)}</strong></div>
                <div><span>Edges</span><strong>{edgeCount(selectedWorkflow)}</strong></div>
                <div><span>Version</span><strong>{selectedWorkflow.version ?? 1}</strong></div>
                <div><span>Updated</span><strong>{formatTime(selectedWorkflow.updated_at || selectedWorkflow.updated_at_ms)}</strong></div>
              </div>
              <div class="graph-panel compact">
                <GraphViewer workflow={selectedWorkflow as any} nodeStatus={{}} />
              </div>
              <div class="action-row">
                <button class="btn" onclick={() => loadWorkflowForEdit(workflowId(selectedWorkflow))}>
                  Edit JSON
                </button>
                <button
                  class="btn run"
                  onclick={() => startWorkflowRun(workflowId(selectedWorkflow), "{}")}
                  disabled={actionLoading}
                >
                  Run
                </button>
              </div>
            </div>
          {:else}
            <div class="empty-row">No workflow selected</div>
          {/if}
        </section>
      </div>
    {:else if panelView === "editor"}
      <div class="editor-grid">
        <section class="boiler-section editor-main">
          <div class="section-header">
            <h3>{workflowEditorMode === "create" ? "Create Workflow" : "Workflow Editor"}</h3>
            {#if workflowParseError}
              <span class="error-text">Invalid JSON</span>
            {:else}
              <span>JSON OK</span>
            {/if}
          </div>
          <textarea
            class="json-editor"
            class:invalid={!!workflowParseError}
            spellcheck="false"
            value={workflowJson}
            oninput={handleWorkflowJsonInput}
          ></textarea>
          {#if workflowParseError}
            <div class="inline-error">{workflowParseError}</div>
          {/if}
        </section>

        <section class="boiler-section">
          <div class="section-header">
            <h3>Preview & Actions</h3>
            <span>{workflowEditorMode}</span>
          </div>
          <div class="graph-panel">
            <GraphViewer workflow={workflowGraph as any} nodeStatus={{}} />
          </div>
          <div class="action-row wrap">
            <button class="btn" onclick={saveWorkflow} disabled={actionLoading || !!workflowParseError}>
              {workflowEditorMode === "create" ? "Create" : "Save"}
            </button>
            <button
              class="btn"
              onclick={validateWorkflow}
              disabled={actionLoading || workflowEditorMode === "create" || !selectedWorkflowId}
            >
              Validate
            </button>
            <button
              class="btn danger"
              onclick={deleteWorkflow}
              disabled={actionLoading || workflowEditorMode === "create" || !selectedWorkflowId}
            >
              {workflowDeleteConfirm === selectedWorkflowId ? "Confirm Delete" : "Delete"}
            </button>
          </div>
          {#if validationResult}
            <div class:validation-valid={validationResult.valid} class:validation-invalid={!validationResult.valid}>
              {validationResult.valid ? "Workflow is valid" : "Workflow has validation errors"}
            </div>
            {#if validationResult.errors?.length}
              <pre>{jsonPreview(validationResult.errors)}</pre>
            {/if}
            {#if validationResult.mermaid}
              <pre>{validationResult.mermaid}</pre>
            {/if}
          {/if}
          <label class="field">
            <span>Run Input JSON</span>
            <textarea bind:value={workflowInput} rows="7"></textarea>
          </label>
          <button
            class="btn run"
            onclick={runWorkflow}
            disabled={actionLoading || workflowEditorMode === "create" || !selectedWorkflowId}
          >
            Run Workflow
          </button>
        </section>
      </div>
    {:else if panelView === "runs"}
      <div class="runs-grid">
        <section class="boiler-section">
          <div class="section-header">
            <h3>Runs</h3>
            <span>{runs.length}</span>
          </div>
          <div class="filter-grid">
            <label class="field">
              <span>Status</span>
              <select bind:value={runStatusFilter}>
                <option value="">All</option>
                <option value="running">Running</option>
                <option value="pending">Pending</option>
                <option value="completed">Completed</option>
                <option value="failed">Failed</option>
                <option value="interrupted">Interrupted</option>
                <option value="cancelled">Cancelled</option>
              </select>
            </label>
            <label class="field">
              <span>Workflow</span>
              <select bind:value={runWorkflowFilter}>
                <option value="">All</option>
                {#each workflows as workflow}
                  <option value={workflowId(workflow)}>{workflowName(workflow)}</option>
                {/each}
              </select>
            </label>
            <label class="field">
              <span>Limit</span>
              <input bind:value={runLimit} inputmode="numeric" />
            </label>
            <button class="btn" onclick={() => loadRuns({ keepSelection: false })} disabled={loading}>Apply</button>
          </div>
          <div class="run-counts">
            <span>running {runCounts.running || 0}</span>
            <span>completed {runCounts.completed || 0}</span>
            <span>failed {runCounts.failed || 0}</span>
            <span>interrupted {runCounts.interrupted || 0}</span>
          </div>
          <div class="list">
            {#if runs.length === 0}
              <div class="empty-row">No runs</div>
            {:else}
              {#each runs as run}
                <button
                  class="row"
                  class:active={runId(run) === selectedRunId}
                  onclick={() => loadRunDetail(runId(run), false)}
                >
                  <span class="row-title">{runTitle(run)}</span>
                  <span class="row-meta">{run.status || "-"} / {formatDuration(run)} / {runId(run)}</span>
                </button>
              {/each}
            {/if}
          </div>
          {#if runsHasMore}
            <button class="btn subtle" onclick={loadMoreRuns} disabled={loading || detailLoading}>
              Load More
            </button>
          {/if}
        </section>

        <section class="boiler-section run-detail">
          <div class="section-header">
            <h3>Run Detail</h3>
            {#if detailLoading}<span>Loading</span>{/if}
          </div>
          {#if selectedRun}
            <div class="detail-stack">
              <div class="detail-title">
                <span>{runTitle(selectedRun)}</span>
                <code>{selectedRun.id}</code>
              </div>
              <div class="stats-grid">
                <div><span>Status</span><strong>{selectedRun.status || "-"}</strong></div>
                <div><span>Duration</span><strong>{formatDuration(selectedRun)}</strong></div>
                <div><span>Created</span><strong>{formatTime(selectedRun.created_at)}</strong></div>
                <div><span>Updated</span><strong>{formatTime(selectedRun.updated_at)}</strong></div>
              </div>
              {#if selectedRun.interrupt_message || selectedRun.error_text}
                <div class="note">{selectedRun.interrupt_message || selectedRun.error_text}</div>
              {/if}
              <div class="action-row wrap">
                <button
                  class="btn"
                  onclick={cancelRun}
                  disabled={actionLoading || !["running", "pending"].includes(selectedRun.status || "")}
                >
                  Cancel
                </button>
                <button class="btn" onclick={retryRun} disabled={actionLoading || selectedRun.status !== "failed"}>
                  Retry
                </button>
                <a class="btn subtle" href={orchestrationUiRoutes.run(runId(selectedRun), { boilerInstance: name })}>
                  Open Full Page
                </a>
              </div>
              <div class="run-inspector-grid">
                <div class="graph-panel run-graph">
                  <GraphViewer workflow={selectedRunWorkflow} nodeStatus={runNodeStatus} />
                </div>
                <div class="state-panel">
                  <StateInspector currentState={selectedRun.state} previousState={previousRunState} />
                </div>
              </div>
              <div class="event-panel">
                <RunEventLog events={runEvents} />
              </div>
            </div>
          {:else}
            <div class="empty-row">No run selected</div>
          {/if}
        </section>

        <section class="boiler-section full">
          <div class="section-header">
            <h3>Run Control</h3>
            {#if selectedRunId}<span>{selectedRunId}</span>{/if}
          </div>
          {#if selectedRun}
            <div class="control-grid">
              <label class="field">
                <span>Resume Updates JSON</span>
                <textarea bind:value={resumeUpdates} rows="6"></textarea>
              </label>
              <button class="btn run" onclick={resumeRun} disabled={actionLoading || selectedRun.status !== "interrupted"}>
                Resume
              </button>
              <label class="field">
                <span>State Updates JSON</span>
                <textarea bind:value={stateUpdates} rows="6"></textarea>
              </label>
              <label class="field">
                <span>Apply After Step</span>
                <input bind:value={stateApplyAfterStep} placeholder="optional step id" />
              </label>
              <button class="btn" onclick={injectState} disabled={actionLoading}>
                Inject State
              </button>
            </div>
            <div class="checkpoint-grid">
              <div class="checkpoint-list">
                <div class="subhead">Checkpoints</div>
                <CheckpointTimeline
                  {checkpoints}
                  selected={selectedCheckpointId}
                  onSelect={selectCheckpoint}
                />
              </div>
              <div class="checkpoint-state">
                <StateInspector currentState={selectedCheckpointState} />
              </div>
              <div class="checkpoint-actions">
                <label class="field">
                  <span>Fork Overrides JSON</span>
                  <textarea
                    class:invalid={!checkpointOverridesValid}
                    value={checkpointOverrides}
                    oninput={handleCheckpointOverridesInput}
                    rows="7"
                  ></textarea>
                </label>
                {#if !checkpointOverridesValid}
                  <div class="inline-error">Invalid JSON</div>
                {/if}
                <div class="action-row wrap">
                  <button
                    class="btn"
                    onclick={forkRun}
                    disabled={actionLoading || !selectedCheckpointId || !checkpointOverridesValid}
                  >
                    Fork
                  </button>
                  <button
                    class="btn"
                    onclick={replayRun}
                    disabled={actionLoading || !selectedCheckpointId}
                  >
                    Replay
                  </button>
                </div>
              </div>
            </div>
          {:else}
            <div class="empty-row">Select a run to control it.</div>
          {/if}
        </section>
      </div>
    {:else if panelView === "workers"}
      <div class="boiler-grid">
        <section class="boiler-section">
          <div class="section-header">
            <h3>Workers</h3>
            <span>{workers.length}</span>
          </div>
          <div class="list">
            {#if workers.length === 0}
              <div class="empty-row">No workers registered</div>
            {:else}
              {#each workers as worker}
                <button
                  class="row"
                  class:active={workerId(worker) === selectedWorkerId}
                  onclick={() => (selectedWorkerId = workerId(worker))}
                >
                  <span class="row-title">{workerTitle(worker)}</span>
                  <span class="row-meta">
                    {worker.protocol || "-"} / {worker.status || "-"} / max {worker.max_concurrent ?? 1}
                  </span>
                </button>
              {/each}
            {/if}
          </div>
          <div class="action-row wrap">
            <button class="btn" onclick={loadWorkers} disabled={actionLoading}>Refresh Workers</button>
            <button class="btn danger" onclick={deleteWorker} disabled={!selectedWorkerId || actionLoading}>
              {workerDeleteConfirm === selectedWorkerId ? "Confirm Delete" : "Delete"}
            </button>
          </div>
        </section>

        <section class="boiler-section">
          <div class="section-header">
            <h3>Worker Detail</h3>
          </div>
          {#if selectedWorker}
            <div class="detail-stack">
              <div class="detail-title">
                <span>{workerTitle(selectedWorker)}</span>
                <code>{selectedWorker.url || "-"}</code>
              </div>
              <div class="stats-grid">
                <div><span>Protocol</span><strong>{selectedWorker.protocol || "-"}</strong></div>
                <div><span>Status</span><strong>{selectedWorker.status || "-"}</strong></div>
                <div><span>Model</span><strong>{selectedWorker.model || "-"}</strong></div>
                <div><span>Failures</span><strong>{selectedWorker.consecutive_failures ?? 0}</strong></div>
              </div>
              {#if selectedWorker.last_error_text}
                <div class="note">{selectedWorker.last_error_text}</div>
              {/if}
              <pre>{jsonPreview(selectedWorker)}</pre>
            </div>
          {:else}
            <div class="empty-row">No worker selected</div>
          {/if}
        </section>

        <section class="boiler-section full">
          <div class="section-header">
            <h3>Register Worker</h3>
          </div>
          <div class="worker-form">
            <label class="field">
              <span>ID</span>
              <input bind:value={workerIdValue} placeholder="worker-id" />
            </label>
            <label class="field">
              <span>URL</span>
              <input bind:value={workerUrlValue} placeholder="http://127.0.0.1:9000/webhook" />
            </label>
            <label class="field">
              <span>Protocol</span>
              <select bind:value={workerProtocolValue}>
                <option value="webhook">webhook</option>
                <option value="api_chat">api_chat</option>
                <option value="openai_chat">openai_chat</option>
                <option value="mqtt">mqtt</option>
                <option value="redis_stream">redis_stream</option>
                <option value="a2a">a2a</option>
              </select>
            </label>
            <label class="field">
              <span>Model</span>
              <input bind:value={workerModelValue} placeholder="optional" />
            </label>
            <label class="field">
              <span>Token</span>
              <input bind:value={workerTokenValue} placeholder="optional" />
            </label>
            <label class="field">
              <span>Max Concurrent</span>
              <input bind:value={workerMaxConcurrentValue} inputmode="numeric" />
            </label>
            <label class="field wide">
              <span>Tags JSON</span>
              <textarea bind:value={workerTagsValue} rows="4"></textarea>
            </label>
            <button
              class="btn"
              onclick={registerWorker}
              disabled={actionLoading || !workerIdValue.trim() || !workerUrlValue.trim()}
            >
              Register Worker
            </button>
          </div>
        </section>
      </div>
    {:else}
      <div class="boiler-grid">
        <section class="boiler-section">
          <div class="section-header">
            <h3>Tracker</h3>
            <span>{trackerTasks.length}</span>
          </div>
          {#if trackerStatus}
            <div class="stats-grid">
              <div><span>Running</span><strong>{trackerStatus.running_count || trackerStats?.running || 0}</strong></div>
              <div><span>Completed</span><strong>{trackerStatus.completed_count || trackerStats?.completed || 0}</strong></div>
              <div><span>Failed</span><strong>{trackerStatus.failed_count || trackerStats?.failed || 0}</strong></div>
              <div><span>Max</span><strong>{trackerStatus.max_concurrent || trackerStats?.max_concurrent || 0}</strong></div>
            </div>
            <button class="btn" onclick={refreshTracker} disabled={actionLoading}>Refresh Tracker</button>
          {:else}
            <div class="empty-row">Tracker is not configured or not reachable.</div>
          {/if}
          <div class="list">
            {#if trackerTasks.length === 0}
              <div class="empty-row">No running tracker tasks</div>
            {:else}
              {#each trackerTasks as task}
                <button
                  class="row"
                  class:active={trackerTaskId(task) === selectedTrackerTaskId}
                  onclick={() => (selectedTrackerTaskId = trackerTaskId(task))}
                >
                  <span class="row-title">{task.task_title || trackerTaskId(task)}</span>
                  <span class="row-meta">{task.pipeline_id || "-"} / turn {task.current_turn ?? 0}</span>
                </button>
              {/each}
            {/if}
          </div>
        </section>

        <section class="boiler-section">
          <div class="section-header">
            <h3>Task Detail</h3>
          </div>
          {#if selectedTrackerTask}
            <div class="detail-stack">
              <div class="detail-title">
                <span>{selectedTrackerTask.task_title || trackerTaskId(selectedTrackerTask)}</span>
                <code>{trackerTaskId(selectedTrackerTask)}</code>
              </div>
              <div class="stats-grid">
                <div><span>Pipeline</span><strong>{selectedTrackerTask.pipeline_id || "-"}</strong></div>
                <div><span>Role</span><strong>{selectedTrackerTask.agent_role || "-"}</strong></div>
                <div><span>State</span><strong>{selectedTrackerTask.state || "-"}</strong></div>
                <div><span>Execution</span><strong>{selectedTrackerTask.execution || "-"}</strong></div>
              </div>
              <pre>{jsonPreview(selectedTrackerTask)}</pre>
            </div>
          {:else}
            <div class="empty-row">No tracker task selected</div>
          {/if}
        </section>
      </div>
    {/if}
  {/if}
</div>

<style>
  .boiler-panel {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }
  .boiler-header,
  .section-header,
  .action-row,
  .header-actions {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }
  .action-row.wrap,
  .header-actions {
    flex-wrap: wrap;
  }
  .boiler-tabs {
    display: inline-flex;
    border: 1px solid var(--border);
    background: var(--bg-surface);
    border-radius: 2px;
    overflow: hidden;
  }
  .boiler-tabs button {
    min-width: 112px;
    padding: 0.65rem 1rem;
    border: 0;
    border-right: 1px solid var(--border);
    background: transparent;
    color: var(--fg-dim);
    cursor: pointer;
    text-transform: uppercase;
    letter-spacing: 0;
    font-weight: 700;
    font-size: 0.75rem;
  }
  .boiler-tabs button:last-child {
    border-right: 0;
  }
  .boiler-tabs button.active {
    color: var(--accent);
    background: color-mix(in srgb, var(--accent) 10%, transparent);
    text-shadow: var(--text-glow);
  }
  .boiler-grid,
  .editor-grid {
    display: grid;
    grid-template-columns: minmax(300px, 0.95fr) minmax(360px, 1.05fr);
    gap: 1rem;
  }
  .runs-grid {
    display: grid;
    grid-template-columns: minmax(280px, 0.6fr) minmax(520px, 1.4fr);
    gap: 1rem;
  }
  .boiler-section {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    min-width: 0;
    padding: 1rem;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: var(--bg-surface);
  }
  .boiler-section.full {
    grid-column: 1 / -1;
  }
  .boiler-section.editor-main {
    min-height: 720px;
  }
  .section-header h3 {
    margin: 0;
    color: var(--accent);
    font-size: 0.9rem;
    text-transform: uppercase;
    letter-spacing: 0;
  }
  .section-header span,
  .error-text {
    color: var(--fg-dim);
    font-size: 0.75rem;
    font-family: var(--font-mono);
  }
  .error-text {
    color: var(--error);
  }
  .list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    max-height: 560px;
    overflow: auto;
  }
  .row {
    display: grid;
    width: 100%;
    gap: 0.25rem;
    padding: 0.75rem;
    border: 1px solid color-mix(in srgb, var(--border) 80%, transparent);
    border-radius: 2px;
    background: color-mix(in srgb, var(--bg) 70%, transparent);
    color: var(--fg);
    text-align: left;
    cursor: pointer;
  }
  .row.active {
    border-color: var(--accent);
    background: color-mix(in srgb, var(--accent) 10%, transparent);
  }
  .row-title {
    color: var(--fg);
    font-weight: 700;
    overflow-wrap: anywhere;
  }
  .row-meta,
  .note {
    color: var(--fg-dim);
    font-size: 0.75rem;
    font-family: var(--font-mono);
    overflow-wrap: anywhere;
  }
  .detail-stack {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    min-width: 0;
  }
  .detail-title {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }
  .detail-title span {
    color: var(--fg);
    font-weight: 700;
    overflow-wrap: anywhere;
  }
  code {
    color: var(--accent);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    overflow-wrap: anywhere;
  }
  .stats-grid,
  .filter-grid,
  .control-grid,
  .worker-form {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
    gap: 0.5rem;
  }
  .control-grid,
  .worker-form {
    align-items: end;
  }
  .stats-grid div {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    padding: 0.65rem;
    border: 1px solid color-mix(in srgb, var(--border) 70%, transparent);
    border-radius: 2px;
  }
  .stats-grid span,
  .field span,
  .subhead {
    color: var(--accent-dim);
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0;
    font-weight: 700;
  }
  .stats-grid strong {
    color: var(--accent);
    font-family: var(--font-mono);
    font-size: 0.85rem;
    overflow-wrap: anywhere;
  }
  .field {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }
  .field.wide {
    grid-column: 1 / -1;
  }
  .field input,
  .field select,
  .field textarea,
  .json-editor {
    padding: 0.6rem 0.7rem;
    border: 1px solid var(--border);
    border-radius: 2px;
    background: var(--bg);
    color: var(--fg);
    font-family: var(--font-mono);
    font-size: 0.8rem;
  }
  .field textarea {
    resize: vertical;
    min-height: 96px;
  }
  .field input:focus,
  .field select:focus,
  .field textarea:focus,
  .json-editor:focus {
    outline: none;
    border-color: var(--accent);
  }
  .json-editor {
    flex: 1;
    width: 100%;
    min-height: 620px;
    resize: vertical;
    line-height: 1.5;
    tab-size: 2;
  }
  .json-editor.invalid,
  textarea.invalid {
    border-color: var(--error);
  }
  .graph-panel {
    min-height: 320px;
    overflow: hidden;
  }
  .graph-panel.compact {
    min-height: 280px;
  }
  .run-inspector-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1rem;
    min-height: 360px;
  }
  .run-graph,
  .state-panel {
    min-height: 360px;
    min-width: 0;
  }
  .event-panel {
    height: 260px;
    min-height: 260px;
  }
  .checkpoint-grid {
    display: grid;
    grid-template-columns: minmax(220px, 0.6fr) minmax(320px, 1fr) minmax(260px, 0.8fr);
    gap: 1rem;
    min-height: 360px;
  }
  .checkpoint-list,
  .checkpoint-state,
  .checkpoint-actions {
    min-width: 0;
    min-height: 0;
  }
  .checkpoint-list {
    border: 1px solid var(--border);
    border-radius: 2px;
    overflow: auto;
  }
  .checkpoint-list .subhead {
    display: block;
    padding: 0.65rem 0.75rem;
    border-bottom: 1px solid var(--border);
  }
  .checkpoint-actions {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }
  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-height: 38px;
    padding: 0.5rem 0.85rem;
    border: 1px solid var(--accent-dim);
    border-radius: 2px;
    background: var(--bg-surface);
    color: var(--accent);
    font-size: 0.75rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0;
    cursor: pointer;
    text-decoration: none;
  }
  .btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .btn:hover:not(:disabled) {
    border-color: var(--accent);
    background: var(--bg-hover);
    text-decoration: none;
  }
  .btn.subtle {
    color: var(--fg);
    border-color: var(--border);
  }
  .btn.run {
    color: var(--success);
    border-color: color-mix(in srgb, var(--success) 50%, transparent);
  }
  .btn.danger {
    color: var(--error);
    border-color: color-mix(in srgb, var(--error) 50%, transparent);
  }
  .run-counts {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  .run-counts span {
    padding: 0.35rem 0.5rem;
    border: 1px solid var(--border);
    border-radius: 2px;
    color: var(--fg-dim);
    font-family: var(--font-mono);
    font-size: 0.75rem;
  }
  pre {
    max-height: 320px;
    overflow: auto;
    margin: 0;
    padding: 0.85rem;
    border: 1px solid var(--border);
    border-radius: 2px;
    background: var(--bg);
    color: var(--fg);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .empty-row,
  .empty-state,
  .error-banner,
  .message-banner,
  .inline-error,
  .validation-valid,
  .validation-invalid {
    padding: 0.85rem;
    border: 1px solid var(--border);
    border-radius: 2px;
    background: var(--bg-surface);
    color: var(--fg-dim);
  }
  .error-banner,
  .inline-error,
  .validation-invalid {
    color: var(--error);
    border-color: color-mix(in srgb, var(--error) 50%, transparent);
  }
  .message-banner,
  .validation-valid {
    color: var(--accent);
    border-color: color-mix(in srgb, var(--accent) 50%, transparent);
  }
  @media (max-width: 1100px) {
    .boiler-grid,
    .editor-grid,
    .runs-grid,
    .run-inspector-grid,
    .checkpoint-grid {
      grid-template-columns: 1fr;
    }
  }
  @media (max-width: 900px) {
    .boiler-tabs,
    .header-actions {
      width: 100%;
    }
    .boiler-tabs button,
    .header-actions .btn {
      flex: 1;
      min-width: 0;
    }
    .boiler-header,
    .action-row,
    .header-actions {
      align-items: stretch;
      flex-direction: column;
    }
  }
</style>
