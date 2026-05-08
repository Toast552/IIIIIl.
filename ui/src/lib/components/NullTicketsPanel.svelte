<script lang="ts">
  import { api } from "$lib/api/client";

  type Pipeline = {
    id?: string;
    name?: string;
    definition?: any;
    created_at_ms?: number;
  };

  type Task = {
    id?: string;
    pipeline_id?: string;
    stage?: string;
    title?: string;
    description?: string;
    priority?: number;
    metadata?: any;
    task_version?: number;
    created_at_ms?: number;
    updated_at_ms?: number;
    dependencies?: any[];
    assignments?: any[];
    available_transitions?: any[];
    latest_run?: any;
  };

  type Run = {
    id?: string;
    task_id?: string;
    attempt?: number;
    status?: string;
    agent_id?: string | null;
    agent_role?: string | null;
    started_at_ms?: number | null;
    ended_at_ms?: number | null;
  };

  type RunEvent = {
    id?: number;
    run_id?: string;
    ts_ms?: number;
    kind?: string;
    data?: any;
  };

  type Artifact = {
    id?: string;
    task_id?: string | null;
    run_id?: string | null;
    created_at_ms?: number;
    kind?: string;
    uri?: string;
    sha256?: string | null;
    size_bytes?: number | null;
    meta?: any;
  };

  type QueueRole = {
    role?: string;
    claimable_count?: number;
    failed_count?: number;
    stuck_count?: number;
    near_expiry_leases?: number;
    oldest_claimable_age_ms?: number | null;
  };

  let { component, name, active = false, running = false } = $props<{
    component: string;
    name: string;
    active?: boolean;
    running?: boolean;
  }>();

  const defaultPipelineDefinition = JSON.stringify(
    {
      initial: "todo",
      states: {
        todo: {
          agent_role: "coder",
          description: "Ready",
        },
        done: {
          terminal: true,
        },
      },
      transitions: [
        {
          from: "todo",
          to: "done",
          trigger: "complete",
        },
      ],
    },
    null,
    2,
  );

  let panelView = $state<"tasks" | "pipelines" | "queue" | "runs" | "artifacts">("tasks");
  let loadKey = $state("");
  let loading = $state(false);
  let actionLoading = $state(false);
  let error = $state("");
  let message = $state("");

  let pipelines = $state<Pipeline[]>([]);
  let selectedPipelineId = $state("");
  let createPipelineName = $state("");
  let createPipelineDefinition = $state(defaultPipelineDefinition);

  let tasks = $state<Task[]>([]);
  let nextCursor = $state<string | null>(null);
  let filterPipeline = $state("");
  let filterStage = $state("");
  let taskLimit = $state("25");
  let selectedTaskId = $state("");
  let selectedTask = $state<Task | null>(null);
  let selectedTaskLoading = $state(false);

  let createTaskPipeline = $state("");
  let createTaskTitle = $state("");
  let createTaskDescription = $state("");
  let createTaskPriority = $state("0");
  let createTaskMetadata = $state("{}");
  let createTaskDependencies = $state("");
  let createTaskAssignedAgent = $state("");
  let bulkTasksJson = $state("[\n]");

  let assignAgent = $state("");
  let dependencyTaskId = $state("");

  let queueRoles = $state<QueueRole[]>([]);
  let claimAgent = $state("nullhub");
  let claimRole = $state("coder");
  let claimTtl = $state("300000");
  let claimed = $state<any>(null);

  let selectedRunId = $state("");
  let runEvents = $state<RunEvent[]>([]);
  let runEventsCursor = $state<string | null>(null);
  let runEventsLimit = $state("50");
  let runLeaseId = $state("");
  let runLeaseToken = $state("");
  let leaseRunId = $state("");
  let heartbeatExpiresAt = $state<number | null>(null);
  let eventKind = $state("note");
  let eventData = $state("{}");
  let transitionTrigger = $state("");
  let transitionInstructions = $state("");
  let transitionUsage = $state("{}");
  let failReason = $state("");
  let failUsage = $state("{}");

  let artifacts = $state<Artifact[]>([]);
  let artifactsCursor = $state<string | null>(null);
  let artifactsScopeKey = $state("");
  let artifactLimit = $state("25");
  let artifactScope = $state<"selected" | "custom" | "all">("selected");
  let artifactTaskFilter = $state("");
  let artifactRunFilter = $state("");
  let artifactKind = $state("file");
  let artifactUri = $state("");
  let artifactSha256 = $state("");
  let artifactSize = $state("");
  let artifactMeta = $state("{}");

  const selectedPipeline = $derived(
    pipelines.find((pipeline) => pipelineId(pipeline) === selectedPipelineId) || null,
  );
  const activeTaskAssignments = $derived(
    Array.isArray(selectedTask?.assignments)
      ? selectedTask.assignments.filter((assignment: any) => assignment?.active !== false)
      : [],
  );
  const taskDependencies = $derived(
    Array.isArray(selectedTask?.dependencies) ? selectedTask.dependencies : [],
  );
  const taskTransitions = $derived(
    Array.isArray(selectedTask?.available_transitions) ? selectedTask.available_transitions : [],
  );
  const selectedRun = $derived<Run | null>(
    selectedTask?.latest_run && (!selectedRunId || selectedTask.latest_run.id === selectedRunId)
      ? selectedTask.latest_run
      : selectedRunId
        ? { id: selectedRunId, task_id: selectedTaskId }
        : null,
  );

  function pipelineId(pipeline: Pipeline | null | undefined): string {
    return String(pipeline?.id || pipeline?.name || "");
  }

  function pipelineName(pipeline: Pipeline | null | undefined): string {
    return String(pipeline?.name || pipeline?.id || "pipeline");
  }

  function taskId(task: Task | null | undefined): string {
    return String(task?.id || "");
  }

  function taskTitle(task: Task | null | undefined): string {
    return String(task?.title || task?.id || "task");
  }

  function runId(run: Run | null | undefined): string {
    return String(run?.id || "");
  }

  function normalizeList(result: any): any[] {
    if (Array.isArray(result)) return result;
    if (Array.isArray(result?.items)) return result.items;
    if (Array.isArray(result?.tasks)) return result.tasks;
    if (Array.isArray(result?.pipelines)) return result.pipelines;
    return [];
  }

  function formatTime(ms: number | undefined | null): string {
    if (!ms) return "-";
    try {
      return new Date(ms).toLocaleString();
    } catch {
      return "-";
    }
  }

  function formatDuration(ms: number | undefined | null): string {
    if (ms == null) return "-";
    if (ms < 1000) return `${ms}ms`;
    const seconds = Math.floor(ms / 1000);
    if (seconds < 60) return `${seconds}s`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `${minutes}m`;
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
    const parsed = Number.parseInt(raw || String(fallback), 10);
    const value = Number.isFinite(parsed) ? parsed : fallback;
    return Math.max(min, Math.min(max, value));
  }

  function firstClaimableRole(): string {
    const role =
      queueRoles.find((item) => Number(item?.claimable_count || 0) > 0)?.role ||
      queueRoles[0]?.role;
    return typeof role === "string" && role.length > 0 ? role : "coder";
  }

  function clearRunContext(clearLease = true) {
    selectedRunId = "";
    runEvents = [];
    runEventsCursor = null;
    if (clearLease) {
      runLeaseId = "";
      runLeaseToken = "";
      leaseRunId = "";
      heartbeatExpiresAt = null;
    }
  }

  function artifactScopeParams(): { taskId?: string; runId?: string } {
    if (artifactScope === "all") return {};
    if (artifactScope === "custom") {
      return {
        taskId: artifactTaskFilter.trim() || undefined,
        runId: artifactRunFilter.trim() || undefined,
      };
    }
    return {
      taskId: selectedTaskId || undefined,
      runId: selectedRunId || undefined,
    };
  }

  function artifactScopeLabel(): string {
    const scope = artifactScopeParams();
    if (scope.taskId && scope.runId) return `task ${scope.taskId} / run ${scope.runId}`;
    if (scope.taskId) return `task ${scope.taskId}`;
    if (scope.runId) return `run ${scope.runId}`;
    return "unlinked";
  }

  function artifactScopeCacheKey(scope: { taskId?: string; runId?: string }): string {
    return `${artifactScope}:${scope.taskId || ""}:${scope.runId || ""}`;
  }

  function setArtifactScope(scope: "selected" | "custom" | "all") {
    artifactScope = scope;
    artifactsCursor = null;
    artifactsScopeKey = "";
    void loadArtifacts(false);
  }

  function openSelectedArtifacts() {
    artifactScope = "selected";
    panelView = "artifacts";
    void loadArtifacts(false);
  }

  function syncLeaseToSelectedRun() {
    if (leaseRunId && selectedRunId && leaseRunId === selectedRunId) return;
    runLeaseId = "";
    runLeaseToken = "";
    leaseRunId = "";
    heartbeatExpiresAt = null;
  }

  async function refreshAll() {
    if (component !== "nulltickets" || !running) return;
    loading = true;
    error = "";
    try {
      const [pipelineResult, queueResult] = await Promise.all([
        api.nullTicketsPipelines(component, name),
        api.nullTicketsAction(component, name, { method: "GET", path: "/ops/queue" }),
      ]);
      pipelines = normalizeList(pipelineResult);
      queueRoles = normalizeList(queueResult?.roles ? { items: queueResult.roles } : queueResult);
      if (!selectedPipelineId || !pipelines.some((pipeline) => pipelineId(pipeline) === selectedPipelineId)) {
        selectedPipelineId = pipelineId(pipelines[0] || {});
      }
      if (!createTaskPipeline && selectedPipelineId) createTaskPipeline = selectedPipelineId;
      if (!claimRole) claimRole = firstClaimableRole();
      await loadTasks(false);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      loading = false;
    }
  }

  async function loadTasks(append: boolean) {
    if (component !== "nulltickets" || !running) return;
    const limit = boundedInt(taskLimit, 25, 1, 1000);
    loading = true;
    error = "";
    try {
      const result = await api.nullTicketsTasks(component, name, {
        pipelineId: filterPipeline || undefined,
        stage: filterStage || undefined,
        limit,
        cursor: append ? nextCursor || undefined : undefined,
      });
      const items = normalizeList(result);
      tasks = append ? [...tasks, ...items] : items;
      nextCursor = typeof result?.next_cursor === "string" ? result.next_cursor : null;
      if (!selectedTaskId && items.length > 0) {
        await selectTask(taskId(items[0]));
      } else if (!append && selectedTaskId) {
        await selectTask(selectedTaskId);
      }
    } catch (e) {
      error = (e as Error).message;
    } finally {
      loading = false;
    }
  }

  async function selectTask(id: string) {
    if (!id || component !== "nulltickets" || !running) return;
    selectedTaskId = id;
    selectedTaskLoading = true;
    error = "";
    try {
      selectedTask = await api.nullTicketsGetTask(component, name, id);
      await loadSelectedTaskContext();
    } catch (e) {
      error = (e as Error).message;
    } finally {
      selectedTaskLoading = false;
    }
  }

  async function loadSelectedTaskContext() {
    const task = selectedTask;
    if (!task) {
      selectedRunId = "";
      runEvents = [];
      artifacts = [];
      artifactsCursor = null;
      artifactsScopeKey = "";
      syncLeaseToSelectedRun();
      return;
    }

    const latestRunId = runId(task.latest_run);
    if (latestRunId) {
      selectedRunId = latestRunId;
    } else {
      try {
        const runState = await api.nullTicketsGetRunState(component, name, taskId(task));
        selectedRunId = String(runState?.run_id || "");
      } catch {
        selectedRunId = "";
      }
    }
    syncLeaseToSelectedRun();

    if (selectedRunId) {
      await loadRunEvents(false);
    } else {
      runEvents = [];
      runEventsCursor = null;
    }
    await loadArtifacts(false);
  }

  async function createPipeline() {
    const nameValue = createPipelineName.trim();
    if (!nameValue || component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const definition = parseJsonField(createPipelineDefinition, {});
      const result = await api.nullTicketsCreatePipeline(component, name, {
        name: nameValue,
        definition,
      });
      createPipelineName = "";
      createPipelineDefinition = defaultPipelineDefinition;
      message = `Pipeline ${result?.id || nameValue} created`;
      await refreshAll();
      selectedPipelineId = result?.id || result?.name || nameValue || selectedPipelineId;
      filterPipeline = selectedPipelineId;
      createTaskPipeline = selectedPipelineId;
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function createTask() {
    const pipelineIdValue = createTaskPipeline.trim() || filterPipeline.trim() || selectedPipelineId.trim();
    const title = createTaskTitle.trim();
    if (!pipelineIdValue || !title || component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const priority = Number.parseInt(createTaskPriority || "0", 10);
      const dependencies = createTaskDependencies
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean);
      const payload: Record<string, any> = {
        pipeline_id: pipelineIdValue,
        title,
        description: createTaskDescription.trim(),
        priority: Number.isFinite(priority) ? priority : 0,
        metadata: parseJsonField(createTaskMetadata, {}),
      };
      if (dependencies.length > 0) payload.dependencies = dependencies;
      if (createTaskAssignedAgent.trim()) {
        payload.assigned_agent_id = createTaskAssignedAgent.trim();
        payload.assigned_by = "nullhub";
      }
      const result = await api.nullTicketsCreateTask(component, name, payload);
      createTaskTitle = "";
      createTaskDescription = "";
      createTaskDependencies = "";
      createTaskAssignedAgent = "";
      message = `Task ${result?.id || ""} created`.trim();
      await loadTasks(false);
      if (result?.id) await selectTask(result.id);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function bulkCreateTasks() {
    if (component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const parsed = parseJsonField(bulkTasksJson, []);
      const tasksToCreate = Array.isArray(parsed) ? parsed : Array.isArray(parsed?.tasks) ? parsed.tasks : [];
      if (tasksToCreate.length === 0) {
        throw new Error("Bulk JSON must be an array or { tasks: [...] }");
      }
      const result = await api.nullTicketsBulkCreateTasks(component, name, tasksToCreate);
      message = `Created ${(result?.ids || []).length || tasksToCreate.length} tasks`;
      bulkTasksJson = "[\n]";
      await loadTasks(false);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function assignTask() {
    if (!selectedTaskId || !assignAgent.trim() || component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      await api.nullTicketsAssignTask(component, name, selectedTaskId, {
        agent_id: assignAgent.trim(),
        assigned_by: "nullhub",
      });
      message = "Task assigned";
      assignAgent = "";
      await selectTask(selectedTaskId);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function unassignTask(agentId: string) {
    if (!selectedTaskId || !agentId || component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      await api.nullTicketsUnassignTask(component, name, selectedTaskId, agentId);
      message = "Task unassigned";
      await selectTask(selectedTaskId);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function addDependency() {
    if (!selectedTaskId || !dependencyTaskId.trim() || component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      await api.nullTicketsAddDependency(component, name, selectedTaskId, {
        depends_on_task_id: dependencyTaskId.trim(),
      });
      message = "Dependency added";
      dependencyTaskId = "";
      await selectTask(selectedTaskId);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function claimNext() {
    if (component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    let claimedTaskId = "";
    try {
      const leaseTtl = boundedInt(claimTtl, 300000, 1000, Number.MAX_SAFE_INTEGER);
      const result = await api.nullTicketsClaimTask(component, name, {
        agent_id: claimAgent.trim() || "nullhub",
        agent_role: claimRole.trim() || "coder",
        lease_ttl_ms: leaseTtl,
      });
      if (result?.task) {
        claimed = result;
        claimedTaskId = String(result.task.id || "");
        if (claimedTaskId) selectedTaskId = claimedTaskId;
        selectedTask = result.task;
        runLeaseId = String(result.lease_id || "");
        runLeaseToken = String(result.lease_token || "");
        leaseRunId = String(result.run?.id || "");
        heartbeatExpiresAt = typeof result.expires_at_ms === "number" ? result.expires_at_ms : null;
        selectedRunId = leaseRunId;
        message = `Claimed ${result.task.id || "task"}`;
      } else {
        claimed = null;
        message = "No claimable task";
      }
      await refreshAll();
      if (claimedTaskId) await selectTask(claimedTaskId);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function heartbeatLease() {
    if (!runLeaseId.trim() || !runLeaseToken.trim() || component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const result = await api.nullTicketsHeartbeatLease(component, name, runLeaseId.trim(), runLeaseToken.trim());
      heartbeatExpiresAt = typeof result?.expires_at_ms === "number" ? result.expires_at_ms : null;
      message = "Lease heartbeat accepted";
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function loadRunEvents(append: boolean) {
    if (!selectedRunId || component !== "nulltickets" || !running) return;
    const limit = boundedInt(runEventsLimit, 50, 1, 1000);
    loading = true;
    error = "";
    try {
      const result = await api.nullTicketsRunEvents(component, name, selectedRunId, {
        limit,
        cursor: append ? runEventsCursor || undefined : undefined,
      });
      const items = normalizeList(result);
      runEvents = append ? [...runEvents, ...items] : items;
      runEventsCursor = typeof result?.next_cursor === "string" ? result.next_cursor : null;
    } catch (e) {
      error = (e as Error).message;
    } finally {
      loading = false;
    }
  }

  async function addRunEvent() {
    if (!selectedRunId || !eventKind.trim() || !runLeaseToken.trim() || component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const result = await api.nullTicketsAddRunEvent(
        component,
        name,
        selectedRunId,
        {
          kind: eventKind.trim(),
          data: parseJsonField(eventData, {}),
        },
        runLeaseToken.trim(),
      );
      message = `Event ${result?.id || ""} added`.trim();
      eventData = "{}";
      await loadRunEvents(false);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function transitionRun(triggerOverride = "") {
    const trigger = (triggerOverride || transitionTrigger).trim();
    if (!selectedRunId || !trigger || !runLeaseToken.trim() || component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const payload: Record<string, any> = {
        trigger,
        expected_stage: selectedTask?.stage || undefined,
        expected_task_version: selectedTask?.task_version,
        usage: parseJsonField(transitionUsage, {}),
      };
      if (transitionInstructions.trim()) payload.instructions = transitionInstructions.trim();
      const result = await api.nullTicketsTransitionRun(component, name, selectedRunId, payload, runLeaseToken.trim());
      message = `Transitioned ${result?.previous_stage || ""} -> ${result?.new_stage || ""}`.trim();
      transitionTrigger = "";
      transitionInstructions = "";
      await selectTask(selectedTaskId);
      await loadRunEvents(false);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function failRun() {
    if (!selectedRunId || !failReason.trim() || !runLeaseToken.trim() || component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      await api.nullTicketsFailRun(
        component,
        name,
        selectedRunId,
        {
          error: failReason.trim(),
          usage: parseJsonField(failUsage, {}),
        },
        runLeaseToken.trim(),
      );
      message = "Run marked failed";
      failReason = "";
      await selectTask(selectedTaskId);
      await loadRunEvents(false);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  async function loadArtifacts(append: boolean) {
    if (component !== "nulltickets" || !running) return;
    const limit = boundedInt(artifactLimit, 25, 1, 1000);
    const scope = artifactScopeParams();
    const scopeKey = artifactScopeCacheKey(scope);
    const shouldAppend = append && artifactsScopeKey === scopeKey;
    loading = true;
    error = "";
    try {
      const result = await api.nullTicketsArtifacts(component, name, {
        ...scope,
        limit,
        cursor: shouldAppend ? artifactsCursor || undefined : undefined,
      });
      const items = normalizeList(result);
      artifacts = shouldAppend ? [...artifacts, ...items] : items;
      artifactsCursor = typeof result?.next_cursor === "string" ? result.next_cursor : null;
      artifactsScopeKey = scopeKey;
    } catch (e) {
      error = (e as Error).message;
    } finally {
      loading = false;
    }
  }

  async function createArtifact() {
    if (!artifactKind.trim() || !artifactUri.trim() || component !== "nulltickets" || !running) return;
    actionLoading = true;
    error = "";
    message = "";
    try {
      const size = artifactSize.trim() ? Number.parseInt(artifactSize.trim(), 10) : null;
      const scope = artifactScopeParams();
      const payload: Record<string, any> = {
        task_id: scope.taskId || null,
        run_id: scope.runId || null,
        kind: artifactKind.trim(),
        uri: artifactUri.trim(),
        sha256: artifactSha256.trim() || null,
        size_bytes: Number.isFinite(size) ? size : null,
        meta: parseJsonField(artifactMeta, {}),
      };
      const result = await api.nullTicketsCreateArtifact(component, name, payload);
      message = `Artifact ${result?.id || ""} created`.trim();
      artifactUri = "";
      artifactSha256 = "";
      artifactSize = "";
      artifactMeta = "{}";
      await loadArtifacts(false);
    } catch (e) {
      error = (e as Error).message;
    } finally {
      actionLoading = false;
    }
  }

  $effect(() => {
    const key = `${component}/${name}/${active}/${running}`;
    if (!active || component !== "nulltickets") return;
    if (loadKey === key) return;
    loadKey = key;
    message = "";
    error = "";
    selectedTask = null;
    selectedTaskId = "";
    clearRunContext();
    artifacts = [];
    artifactsCursor = null;
    artifactsScopeKey = "";
    artifactScope = "selected";
    artifactTaskFilter = "";
    artifactRunFilter = "";
    claimed = null;
    if (running) {
      void refreshAll();
    }
  });
</script>

<div class="tickets-panel">
  {#if !running}
    <div class="empty-state">Instance is stopped.</div>
  {:else}
    <div class="tickets-header">
      <div class="tickets-tabs" role="tablist" aria-label="NullTickets views">
        <button class:active={panelView === "tasks"} onclick={() => (panelView = "tasks")}>
          Tasks
        </button>
        <button class:active={panelView === "pipelines"} onclick={() => (panelView = "pipelines")}>
          Pipelines
        </button>
        <button class:active={panelView === "queue"} onclick={() => (panelView = "queue")}>
          Queue
        </button>
        <button class:active={panelView === "runs"} onclick={() => (panelView = "runs")}>
          Runs
        </button>
        <button class:active={panelView === "artifacts"} onclick={() => (panelView = "artifacts")}>
          Artifacts
        </button>
      </div>
      <button class="btn" onclick={refreshAll} disabled={loading || actionLoading}>
        {loading ? "Refreshing..." : "Refresh"}
      </button>
    </div>

    {#if error}
      <div class="error-banner">{error}</div>
    {/if}
    {#if message}
      <div class="message-banner">{message}</div>
    {/if}

    {#if panelView === "tasks"}
      <div class="tickets-grid">
        <section class="tickets-section">
          <div class="section-header">
            <h3>Tasks</h3>
            <span>{tasks.length}</span>
          </div>
          <div class="filter-grid">
            <label class="field">
              <span>Pipeline</span>
              <select bind:value={filterPipeline}>
                <option value="">All</option>
                {#each pipelines as pipeline}
                  <option value={pipelineId(pipeline)}>{pipelineName(pipeline)}</option>
                {/each}
              </select>
            </label>
            <label class="field">
              <span>Stage</span>
              <input bind:value={filterStage} placeholder="todo" />
            </label>
            <label class="field small">
              <span>Limit</span>
              <input bind:value={taskLimit} inputmode="numeric" />
            </label>
            <button class="btn" onclick={() => loadTasks(false)} disabled={loading}>Apply</button>
          </div>

          <div class="task-list">
            {#if tasks.length === 0}
              <div class="empty-row">No tasks</div>
            {:else}
              {#each tasks as task}
                <button
                  class="task-row"
                  class:active={taskId(task) === selectedTaskId}
                  onclick={() => selectTask(taskId(task))}
                >
                  <span class="task-title">{taskTitle(task)}</span>
                  <span class="task-meta">
                    {task.stage || "-"} / {task.pipeline_id || "-"} / p{task.priority ?? 0}
                  </span>
                </button>
              {/each}
            {/if}
          </div>
          {#if nextCursor}
            <button class="btn subtle" onclick={() => loadTasks(true)} disabled={loading}>
              Load More
            </button>
          {/if}
        </section>

        <section class="tickets-section">
          <div class="section-header">
            <h3>Task Detail</h3>
            {#if selectedTaskLoading}<span>Loading</span>{/if}
          </div>
          {#if selectedTask}
            <div class="detail-stack">
              <div class="detail-title">
                <span>{taskTitle(selectedTask)}</span>
                <code>{selectedTask.id}</code>
              </div>
              <div class="stats-grid">
                <div><span>Stage</span><strong>{selectedTask.stage || "-"}</strong></div>
                <div><span>Pipeline</span><strong>{selectedTask.pipeline_id || "-"}</strong></div>
                <div><span>Priority</span><strong>{selectedTask.priority ?? 0}</strong></div>
                <div><span>Version</span><strong>{selectedTask.task_version ?? "-"}</strong></div>
              </div>
              {#if selectedRun}
                <div class="stats-grid">
                  <div><span>Run</span><strong>{runId(selectedRun)}</strong></div>
                  <div><span>Status</span><strong>{selectedRun.status || "-"}</strong></div>
                  <div><span>Agent</span><strong>{selectedRun.agent_id || "-"}</strong></div>
                  <div><span>Attempt</span><strong>{selectedRun.attempt ?? "-"}</strong></div>
                </div>
              {/if}
              {#if selectedTask.description}
                <p class="description">{selectedTask.description}</p>
              {/if}
              <div class="detail-columns">
                <div>
                  <span class="subhead">Assignments</span>
                  {#if activeTaskAssignments.length > 0}
                    <div class="pill-list">
                      {#each activeTaskAssignments as assignment}
                        <button
                          class="pill"
                          onclick={() => unassignTask(String(assignment.agent_id || ""))}
                          disabled={actionLoading}
                        >
                          {assignment.agent_id}
                        </button>
                      {/each}
                    </div>
                  {:else}
                    <span class="muted">None</span>
                  {/if}
                </div>
                <div>
                  <span class="subhead">Dependencies</span>
                  {#if taskDependencies.length > 0}
                    <div class="pill-list">
                      {#each taskDependencies as dep}
                        <span class="pill static">
                          {dep.depends_on_task_id || dep.task_id || dep}
                        </span>
                      {/each}
                    </div>
                  {:else}
                    <span class="muted">None</span>
                  {/if}
                </div>
              </div>
              {#if taskTransitions.length > 0}
                <div>
                  <span class="subhead">Transitions</span>
                  <div class="pill-list">
                    {#each taskTransitions as transition}
                      <span class="pill static">
                        {transition.trigger || "-"} -> {transition.to || transition.new_stage || "-"}
                      </span>
                    {/each}
                  </div>
                </div>
              {/if}
              <pre>{jsonPreview(selectedTask.metadata)}</pre>
              <div class="action-grid">
                <label class="field">
                  <span>Assign Agent</span>
                  <input bind:value={assignAgent} placeholder="agent-id" />
                </label>
                <button class="btn" onclick={assignTask} disabled={actionLoading || !assignAgent.trim()}>
                  Assign
                </button>
                <label class="field">
                  <span>Dependency</span>
                  <input bind:value={dependencyTaskId} placeholder="task-id" />
                </label>
                <button class="btn" onclick={addDependency} disabled={actionLoading || !dependencyTaskId.trim()}>
                  Add
                </button>
                <button class="btn subtle" onclick={() => (panelView = "runs")} disabled={!selectedRunId}>
                  Run Controls
                </button>
                <button class="btn subtle" onclick={openSelectedArtifacts}>
                  Artifacts
                </button>
              </div>
            </div>
          {:else}
            <div class="empty-row">No task selected</div>
          {/if}
        </section>

        <section class="tickets-section full">
          <div class="section-header">
            <h3>Create Task</h3>
          </div>
          <div class="create-grid">
            <label class="field">
              <span>Pipeline</span>
              <select bind:value={createTaskPipeline}>
                <option value="">Select</option>
                {#each pipelines as pipeline}
                  <option value={pipelineId(pipeline)}>{pipelineName(pipeline)}</option>
                {/each}
              </select>
            </label>
            <label class="field">
              <span>Title</span>
              <input bind:value={createTaskTitle} placeholder="Task title" />
            </label>
            <label class="field small">
              <span>Priority</span>
              <input bind:value={createTaskPriority} inputmode="numeric" />
            </label>
            <label class="field">
              <span>Assigned Agent</span>
              <input bind:value={createTaskAssignedAgent} placeholder="optional" />
            </label>
            <label class="field wide">
              <span>Description</span>
              <textarea bind:value={createTaskDescription} rows="3"></textarea>
            </label>
            <label class="field wide">
              <span>Dependencies</span>
              <input bind:value={createTaskDependencies} placeholder="task-a, task-b" />
            </label>
            <label class="field wide">
              <span>Metadata JSON</span>
              <textarea bind:value={createTaskMetadata} rows="4"></textarea>
            </label>
            <button
              class="btn"
              onclick={createTask}
              disabled={actionLoading ||
                !createTaskTitle.trim() ||
                !(createTaskPipeline.trim() || filterPipeline.trim() || selectedPipelineId.trim())}
            >
              Create Task
            </button>
          </div>
          <div class="bulk-block">
            <label class="field wide">
              <span>Bulk Tasks JSON</span>
              <textarea bind:value={bulkTasksJson} rows="8"></textarea>
            </label>
            <button class="btn subtle" onclick={bulkCreateTasks} disabled={actionLoading}>
              Bulk Create
            </button>
          </div>
        </section>
      </div>
    {:else if panelView === "pipelines"}
      <div class="tickets-grid">
        <section class="tickets-section">
          <div class="section-header">
            <h3>Pipelines</h3>
            <span>{pipelines.length}</span>
          </div>
          <div class="task-list">
            {#each pipelines as pipeline}
              <button
                class="task-row"
                class:active={pipelineId(pipeline) === selectedPipelineId}
                onclick={() => (selectedPipelineId = pipelineId(pipeline))}
              >
                <span class="task-title">{pipelineName(pipeline)}</span>
                <span class="task-meta">{pipelineId(pipeline)} / {formatTime(pipeline.created_at_ms)}</span>
              </button>
            {/each}
          </div>
        </section>

        <section class="tickets-section">
          <div class="section-header">
            <h3>Definition</h3>
          </div>
          {#if selectedPipeline}
            <div class="detail-stack">
              <div class="detail-title">
                <span>{pipelineName(selectedPipeline)}</span>
                <code>{pipelineId(selectedPipeline)}</code>
              </div>
              <pre>{jsonPreview(selectedPipeline.definition)}</pre>
            </div>
          {:else}
            <div class="empty-row">No pipeline selected</div>
          {/if}
        </section>

        <section class="tickets-section full">
          <div class="section-header">
            <h3>Create Pipeline</h3>
          </div>
          <div class="create-grid">
            <label class="field">
              <span>Name</span>
              <input bind:value={createPipelineName} placeholder="pipeline name" />
            </label>
            <label class="field wide">
              <span>Definition JSON</span>
              <textarea bind:value={createPipelineDefinition} rows="12"></textarea>
            </label>
            <button class="btn" onclick={createPipeline} disabled={actionLoading || !createPipelineName.trim()}>
              Create Pipeline
            </button>
          </div>
        </section>
      </div>
    {:else if panelView === "queue"}
      <div class="tickets-grid">
        <section class="tickets-section">
          <div class="section-header">
            <h3>Queue</h3>
            <span>{queueRoles.length}</span>
          </div>
          <div class="queue-table">
            <div class="queue-head">
              <span>Role</span>
              <span>Claimable</span>
              <span>Failed</span>
              <span>Stuck</span>
              <span>Oldest</span>
            </div>
            {#if queueRoles.length === 0}
              <div class="empty-row">No queue stats</div>
            {:else}
              {#each queueRoles as role}
                <button
                  class="queue-row"
                  onclick={() => (claimRole = String(role.role || "coder"))}
                >
                  <span>{role.role || "-"}</span>
                  <span>{role.claimable_count || 0}</span>
                  <span>{role.failed_count || 0}</span>
                  <span>{role.stuck_count || 0}</span>
                  <span>{formatDuration(role.oldest_claimable_age_ms)}</span>
                </button>
              {/each}
            {/if}
          </div>
        </section>

        <section class="tickets-section">
          <div class="section-header">
            <h3>Claim</h3>
          </div>
          <div class="create-grid">
            <label class="field">
              <span>Agent</span>
              <input bind:value={claimAgent} placeholder="nullhub" />
            </label>
            <label class="field">
              <span>Role</span>
              <select bind:value={claimRole}>
                {#if queueRoles.length === 0}
                  <option value="coder">coder</option>
                {:else}
                  {#each queueRoles as role}
                    <option value={role.role || "coder"}>{role.role || "coder"}</option>
                  {/each}
                {/if}
              </select>
            </label>
            <label class="field">
              <span>Lease TTL ms</span>
              <input bind:value={claimTtl} inputmode="numeric" />
            </label>
            <button class="btn" onclick={claimNext} disabled={actionLoading || !claimRole.trim()}>
              Claim Next
            </button>
          </div>
          {#if claimed?.task}
            <div class="claimed-box">
              <span>{taskTitle(claimed.task)}</span>
              <code>{claimed.lease_id}</code>
            </div>
          {/if}
        </section>
      </div>
    {:else if panelView === "runs"}
      <div class="tickets-grid">
        <section class="tickets-section">
          <div class="section-header">
            <h3>Run</h3>
            {#if selectedRunId}<span>{selectedRunId}</span>{/if}
          </div>
          {#if selectedRun}
            <div class="detail-stack">
              <div class="stats-grid">
                <div><span>Status</span><strong>{selectedRun.status || "-"}</strong></div>
                <div><span>Task</span><strong>{selectedRun.task_id || selectedTaskId || "-"}</strong></div>
                <div><span>Agent</span><strong>{selectedRun.agent_id || "-"}</strong></div>
                <div><span>Role</span><strong>{selectedRun.agent_role || "-"}</strong></div>
                <div><span>Started</span><strong>{formatTime(selectedRun.started_at_ms)}</strong></div>
                <div><span>Ended</span><strong>{formatTime(selectedRun.ended_at_ms)}</strong></div>
              </div>
              <div class="create-grid">
                <label class="field">
                  <span>Lease ID</span>
                  <input bind:value={runLeaseId} placeholder="lease id from claim" />
                </label>
                <label class="field">
                  <span>Lease Token</span>
                  <input bind:value={runLeaseToken} placeholder="token from claim" />
                </label>
                <button class="btn" onclick={heartbeatLease} disabled={actionLoading || !runLeaseId.trim() || !runLeaseToken.trim()}>
                  Heartbeat
                </button>
              </div>
              {#if heartbeatExpiresAt}
                <span class="muted">Lease expires {formatTime(heartbeatExpiresAt)}</span>
              {/if}
              {#if taskTransitions.length > 0}
                <div>
                  <span class="subhead">Available Transitions</span>
                  <div class="pill-list">
                    {#each taskTransitions as transition}
                      <button
                        class="pill"
                        onclick={() => transitionRun(String(transition.trigger || ""))}
                        disabled={actionLoading || !runLeaseToken.trim()}
                      >
                        {transition.trigger || "-"} -> {transition.to || "-"}
                      </button>
                    {/each}
                  </div>
                </div>
              {/if}
              <div class="create-grid">
                <label class="field">
                  <span>Trigger</span>
                  <input bind:value={transitionTrigger} placeholder="complete" />
                </label>
                <label class="field wide">
                  <span>Instructions</span>
                  <textarea bind:value={transitionInstructions} rows="3"></textarea>
                </label>
                <label class="field wide">
                  <span>Usage JSON</span>
                  <textarea bind:value={transitionUsage} rows="4"></textarea>
                </label>
                <button class="btn" onclick={() => transitionRun()} disabled={actionLoading || !transitionTrigger.trim() || !runLeaseToken.trim()}>
                  Transition
                </button>
              </div>
              <div class="create-grid">
                <label class="field wide">
                  <span>Fail Reason</span>
                  <textarea bind:value={failReason} rows="3"></textarea>
                </label>
                <label class="field wide">
                  <span>Fail Usage JSON</span>
                  <textarea bind:value={failUsage} rows="4"></textarea>
                </label>
                <button class="btn danger" onclick={failRun} disabled={actionLoading || !failReason.trim() || !runLeaseToken.trim()}>
                  Fail Run
                </button>
              </div>
            </div>
          {:else}
            <div class="empty-row">Select or claim a task with a run.</div>
          {/if}
        </section>

        <section class="tickets-section">
          <div class="section-header">
            <h3>Events</h3>
            <span>{runEvents.length}</span>
          </div>
          <div class="filter-grid">
            <label class="field small">
              <span>Limit</span>
              <input bind:value={runEventsLimit} inputmode="numeric" />
            </label>
            <button class="btn" onclick={() => loadRunEvents(false)} disabled={loading || !selectedRunId}>
              Load Events
            </button>
          </div>
          <div class="event-list">
            {#if runEvents.length === 0}
              <div class="empty-row">No events</div>
            {:else}
              {#each runEvents as event}
                <div class="event-row">
                  <div>
                    <span class="task-title">{event.kind || "event"}</span>
                    <span class="task-meta">#{event.id ?? "-"} / {formatTime(event.ts_ms)}</span>
                  </div>
                  <pre>{jsonPreview(event.data)}</pre>
                </div>
              {/each}
            {/if}
          </div>
          {#if runEventsCursor}
            <button class="btn subtle" onclick={() => loadRunEvents(true)} disabled={loading}>
              Load More
            </button>
          {/if}
          <div class="create-grid">
            <label class="field">
              <span>Kind</span>
              <input bind:value={eventKind} placeholder="note" />
            </label>
            <label class="field wide">
              <span>Data JSON</span>
              <textarea bind:value={eventData} rows="5"></textarea>
            </label>
            <button class="btn" onclick={addRunEvent} disabled={actionLoading || !selectedRunId || !eventKind.trim() || !runLeaseToken.trim()}>
              Add Event
            </button>
          </div>
        </section>
      </div>
    {:else}
      <div class="tickets-grid">
        <section class="tickets-section">
          <div class="section-header">
            <h3>Artifacts</h3>
            <span>{artifacts.length}</span>
          </div>
          <div class="filter-grid">
            <div class="field wide">
              <span>Scope</span>
              <div class="scope-buttons">
                <button
                  class:active={artifactScope === "selected"}
                  onclick={() => setArtifactScope("selected")}
                  disabled={loading}
                >
                  Selected
                </button>
                <button
                  class:active={artifactScope === "custom"}
                  onclick={() => setArtifactScope("custom")}
                  disabled={loading}
                >
                  Custom
                </button>
                <button
                  class:active={artifactScope === "all"}
                  onclick={() => setArtifactScope("all")}
                  disabled={loading}
                >
                  All
                </button>
              </div>
            </div>
            {#if artifactScope === "custom"}
              <label class="field">
                <span>Task ID</span>
                <input bind:value={artifactTaskFilter} placeholder="optional" />
              </label>
              <label class="field">
                <span>Run ID</span>
                <input bind:value={artifactRunFilter} placeholder="optional" />
              </label>
            {/if}
            <label class="field small">
              <span>Limit</span>
              <input bind:value={artifactLimit} inputmode="numeric" />
            </label>
            <button class="btn" onclick={() => loadArtifacts(false)} disabled={loading}>
              Load Artifacts
            </button>
          </div>
          <div class="task-list">
            {#if artifacts.length === 0}
              <div class="empty-row">No artifacts</div>
            {:else}
              {#each artifacts as artifact}
                <div class="artifact-row">
                  <div>
                    <span class="task-title">{artifact.kind || "artifact"}</span>
                    <span class="task-meta">{artifact.id || "-"} / {formatTime(artifact.created_at_ms)}</span>
                  </div>
                  <code>{artifact.uri || "-"}</code>
                  <span class="task-meta">
                    task {artifact.task_id || "-"} / run {artifact.run_id || "-"} / {artifact.size_bytes ?? "-"} bytes
                  </span>
                  <pre>{jsonPreview(artifact.meta)}</pre>
                </div>
              {/each}
            {/if}
          </div>
          {#if artifactsCursor}
            <button class="btn subtle" onclick={() => loadArtifacts(true)} disabled={loading}>
              Load More
            </button>
          {/if}
        </section>

        <section class="tickets-section">
          <div class="section-header">
            <h3>Create Artifact</h3>
            <span>{artifactScopeLabel()}</span>
          </div>
          <div class="create-grid">
            <label class="field">
              <span>Kind</span>
              <input bind:value={artifactKind} placeholder="file" />
            </label>
            <label class="field wide">
              <span>URI</span>
              <input bind:value={artifactUri} placeholder="file:///tmp/result.txt" />
            </label>
            <label class="field">
              <span>SHA-256</span>
              <input bind:value={artifactSha256} placeholder="optional" />
            </label>
            <label class="field">
              <span>Size Bytes</span>
              <input bind:value={artifactSize} inputmode="numeric" />
            </label>
            <label class="field wide">
              <span>Meta JSON</span>
              <textarea bind:value={artifactMeta} rows="6"></textarea>
            </label>
            <button class="btn" onclick={createArtifact} disabled={actionLoading || !artifactKind.trim() || !artifactUri.trim()}>
              Create Artifact
            </button>
          </div>
        </section>
      </div>
    {/if}
  {/if}
</div>

<style>
  .tickets-panel {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }
  .tickets-header,
  .section-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }
  .tickets-tabs {
    display: inline-flex;
    border: 1px solid var(--border);
    background: var(--bg-surface);
    border-radius: 2px;
    overflow: hidden;
  }
  .tickets-tabs button {
    min-width: 120px;
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
  .tickets-tabs button:last-child {
    border-right: 0;
  }
  .tickets-tabs button.active {
    color: var(--accent);
    background: color-mix(in srgb, var(--accent) 10%, transparent);
    text-shadow: var(--text-glow);
  }
  .tickets-grid {
    display: grid;
    grid-template-columns: minmax(280px, 0.9fr) minmax(320px, 1.1fr);
    gap: 1rem;
  }
  .tickets-section {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    min-width: 0;
    padding: 1rem;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: var(--bg-surface);
  }
  .tickets-section.full {
    grid-column: 1 / -1;
  }
  .section-header h3 {
    margin: 0;
    color: var(--accent);
    font-size: 0.9rem;
    text-transform: uppercase;
    letter-spacing: 0;
  }
  .section-header span {
    color: var(--fg-dim);
    font-size: 0.75rem;
    font-family: var(--font-mono);
    overflow-wrap: anywhere;
  }
  .filter-grid,
  .action-grid,
  .create-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 0.75rem;
    align-items: end;
  }
  .field {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }
  .field.small {
    min-width: 80px;
  }
  .field.wide {
    grid-column: 1 / -1;
  }
  .field span,
  .subhead {
    color: var(--accent-dim);
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0;
    font-weight: 700;
  }
  .field input,
  .field select,
  .field textarea {
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
    min-height: 84px;
  }
  .scope-buttons {
    display: inline-flex;
    width: fit-content;
    max-width: 100%;
    border: 1px solid var(--border);
    border-radius: 2px;
    overflow: hidden;
  }
  .scope-buttons button {
    min-width: 92px;
    padding: 0.55rem 0.75rem;
    border: 0;
    border-right: 1px solid var(--border);
    background: var(--bg);
    color: var(--fg-dim);
    cursor: pointer;
    font-size: 0.75rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0;
  }
  .scope-buttons button:last-child {
    border-right: 0;
  }
  .scope-buttons button.active {
    color: var(--accent);
    background: color-mix(in srgb, var(--accent) 10%, transparent);
  }
  .scope-buttons button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .field input:focus,
  .field select:focus,
  .field textarea:focus {
    outline: none;
    border-color: var(--accent);
  }
  .btn {
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
  }
  .btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  .btn:hover:not(:disabled) {
    border-color: var(--accent);
    background: var(--bg-hover);
  }
  .btn.subtle {
    color: var(--fg);
    border-color: var(--border);
  }
  .btn.danger {
    color: var(--error);
    border-color: color-mix(in srgb, var(--error) 50%, transparent);
  }
  .bulk-block {
    display: grid;
    grid-template-columns: 1fr;
    gap: 0.75rem;
    margin-top: 1rem;
    padding-top: 1rem;
    border-top: 1px solid var(--border);
  }
  .task-list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    max-height: 520px;
    overflow: auto;
  }
  .task-row,
  .queue-row {
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
  .task-row.active {
    border-color: var(--accent);
    background: color-mix(in srgb, var(--accent) 10%, transparent);
  }
  .artifact-row,
  .event-row {
    display: grid;
    gap: 0.5rem;
    padding: 0.75rem;
    border: 1px solid color-mix(in srgb, var(--border) 80%, transparent);
    border-radius: 2px;
    background: color-mix(in srgb, var(--bg) 70%, transparent);
  }
  .event-list {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    max-height: 520px;
    overflow: auto;
  }
  .task-title {
    color: var(--fg);
    font-weight: 700;
    overflow-wrap: anywhere;
  }
  .task-meta,
  .muted {
    color: var(--fg-dim);
    font-size: 0.75rem;
    font-family: var(--font-mono);
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
  .stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(110px, 1fr));
    gap: 0.5rem;
  }
  .stats-grid div {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    padding: 0.65rem;
    border: 1px solid color-mix(in srgb, var(--border) 70%, transparent);
    border-radius: 2px;
  }
  .stats-grid span {
    color: var(--fg-dim);
    font-size: 0.68rem;
    text-transform: uppercase;
    letter-spacing: 0;
  }
  .stats-grid strong {
    color: var(--accent);
    font-family: var(--font-mono);
    font-size: 0.85rem;
  }
  .description {
    margin: 0;
    color: var(--fg);
    white-space: pre-wrap;
  }
  .detail-columns {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 1rem;
  }
  .pill-list {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-top: 0.5rem;
  }
  .pill {
    padding: 0.35rem 0.5rem;
    border: 1px solid var(--border);
    border-radius: 2px;
    background: var(--bg);
    color: var(--fg);
    font-family: var(--font-mono);
    font-size: 0.75rem;
  }
  button.pill {
    cursor: pointer;
  }
  .pill.static {
    cursor: default;
  }
  pre {
    max-height: 280px;
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
  .queue-table {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }
  .queue-head,
  .queue-row {
    display: grid;
    grid-template-columns: 1.2fr 0.8fr 0.8fr 0.8fr 0.8fr;
    gap: 0.75rem;
    align-items: center;
  }
  .queue-head {
    color: var(--accent-dim);
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0;
    font-weight: 700;
    padding: 0 0.75rem;
  }
  .claimed-box,
  .empty-row,
  .empty-state,
  .error-banner,
  .message-banner {
    padding: 0.85rem;
    border: 1px solid var(--border);
    border-radius: 2px;
    background: var(--bg-surface);
    color: var(--fg-dim);
  }
  .error-banner {
    color: var(--error);
    border-color: color-mix(in srgb, var(--error) 50%, transparent);
  }
  .message-banner {
    color: var(--accent);
    border-color: color-mix(in srgb, var(--accent) 50%, transparent);
  }
  .claimed-box {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    color: var(--fg);
  }
  @media (max-width: 900px) {
    .tickets-grid {
      grid-template-columns: 1fr;
    }
    .tickets-tabs {
      width: 100%;
    }
    .tickets-tabs button {
      flex: 1;
      min-width: 0;
    }
    .queue-head,
    .queue-row {
      grid-template-columns: 1fr 0.7fr 0.7fr;
    }
    .queue-head span:nth-child(4),
    .queue-head span:nth-child(5),
    .queue-row span:nth-child(4),
    .queue-row span:nth-child(5) {
      display: none;
    }
  }
</style>
