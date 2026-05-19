<script lang="ts">
  import { page } from "$app/stores";
  import { goto } from "$app/navigation";
  import { onMount } from "svelte";
  import StatusBadge from "$lib/components/StatusBadge.svelte";
  import LogViewer from "$lib/components/LogViewer.svelte";
  import ConfigEditor from "$lib/components/ConfigEditor.svelte";
  import ChatPanel from "$lib/components/ChatPanel.svelte";
  import InstanceHistoryPanel from "$lib/components/InstanceHistoryPanel.svelte";
  import InstanceMemoryPanel from "$lib/components/InstanceMemoryPanel.svelte";
  import InstanceSkillsPanel from "$lib/components/InstanceSkillsPanel.svelte";
  import NullBoilerPanel from "$lib/components/NullBoilerPanel.svelte";
  import NullTicketsPanel from "$lib/components/NullTicketsPanel.svelte";
  import { api, type ApiRequestError } from "$lib/api/client";
  import {
    orchestrationUiRoutes,
    withBoilerInstance,
    withTicketsInstance,
  } from "$lib/orchestration/routes";
  import {
    getSelectedBoilerInstance,
    getSelectedTicketsInstance,
    setSelectedBoilerInstance,
    setSelectedTicketsInstance,
  } from "$lib/orchestration/backendSelection";

  let component = $derived($page.params.component);
  let name = $derived($page.params.name);
  let instance = $state<any>(null);
  let config = $state<any>(null);
  let uiModules = $state<Record<string, string>>({});
  let activeTab = $state("overview");
  let bootstrapChatAutoOpenedFor = $state("");
  let loading = $state(false);
  let providerHealth = $state<any>(null);
  let providerHealthLoading = $state(false);
  let onboardingStatus = $state<any>(null);
  let lastUsageRefreshAt = $state(0);
  type UsageWindow = "24h" | "7d" | "30d" | "all";
  let usageWindow = $state<UsageWindow>("24h");
  let usageData = $state<any>(null);
  let usageLoading = $state(false);
  let standaloneCopyState = $state<"idle" | "copied" | "error">("idle");
  let standaloneCopyTimer: ReturnType<typeof setTimeout> | null = null;
  let integration = $state<any>(null);
  let integrationLoading = $state(false);
  let integrationError = $state<string | null>(null);
  let linkingIntegration = $state(false);
  let selectedWatch = $state("");
  let selectedClaw = $state("");
  let selectedTracker = $state("");
  let selectedPipeline = $state("");
  let trackerClaimRole = $state("coder");
  let trackerSuccessTrigger = $state("complete");
  let trackerConcurrency = $state("1");
  let ticketsPipelines = $state([] as any[]);
  let ticketsTasks = $state([] as any[]);
  let ticketsDataLoading = $state(false);
  let ticketsDataError = $state("");
  let ticketsActionMessage = $state("");
  let ticketsActionError = $state("");
  let ticketTaskPipeline = $state("");
  let ticketTaskTitle = $state("");
  let ticketTaskDescription = $state("");
  let ticketTaskPriority = $state("0");
  let ticketClaimAgent = $state("nullhub");
  let ticketClaimRole = $state("coder");
  let ticketClaimTtl = $state("300000");
  let claimedTicket = $state<any>(null);
  let lastTicketsRefreshAt = $state(0);

  let modelName = $derived(extractModel(config));
  let webPort = $derived(extractWebPort(config));
  let providerStatus = $derived(extractProviderStatus(config));
  let providerHealthCurrent = $derived(
    providerHealth &&
      providerHealth.provider === providerStatus.provider &&
      providerHealth.model === providerStatus.model
      ? providerHealth
      : null,
  );
  let providerDotOk = $derived(
    Boolean(providerStatus.provider) &&
      (providerHealthCurrent ? Boolean(providerHealthCurrent.live_ok) : providerStatus.configured),
  );
  let providerCardWarn = $derived(
    instance?.status === "running"
      ? (providerHealthCurrent ? !providerDotOk : !providerStatus.configured)
      : !providerStatus.configured,
  );
  let providerHintText = $derived(
    buildProviderHint(
      providerStatus,
      // Only surface live-probe errors when the instance is actually running —
      // otherwise the result is stale/irrelevant (probe ran while starting).
      instance?.status === "running" ? providerHealthCurrent : null,
      providerHealthLoading,
    ),
  );
  let chatModuleName = $derived(
    uiModules["nullclaw-chat-ui"] ? "nullclaw-chat-ui" : "",
  );
  let chatModuleVersion = $derived(uiModules["nullclaw-chat-ui"] || "");
  let chatReady = $derived(
    instance?.status === "running" &&
      chatModuleName !== "" &&
      webPort != null &&
      providerStatus.configured,
  );
  let onboardingPending = $derived(
    Boolean(onboardingStatus?.supported && onboardingStatus?.pending),
  );
  let onboardingStarterMessage = $derived(
    typeof onboardingStatus?.starter_message === "string" &&
      onboardingStatus.starter_message.length > 0
      ? onboardingStatus.starter_message
      : "Wake up, my friend!",
  );
  let onboardingMarker = $derived(
    typeof onboardingStatus?.bootstrap_seeded_at === "string" &&
      onboardingStatus.bootstrap_seeded_at.length > 0
      ? onboardingStatus.bootstrap_seeded_at
      : "",
  );
  let supportsIntegration = $derived(
    component === "nullclaw" ||
      component === "nullwatch" ||
      component === "nullboiler" ||
      component === "nulltickets",
  );
  let supportsAgentData = $derived(component === "nullclaw");
  let supportsBoilerUi = $derived(component === "nullboiler");
  let supportsTicketsUi = $derived(component === "nulltickets");
  let supportsChat = $derived(component === "nullclaw");
  let supportsUsage = $derived(component === "nullclaw");
  let supportsVerboseStartup = $derived(component === "nullclaw");
  let instanceRouteKey = $derived(`${component}/${name}`);
  let initializedRouteKey = $state("");
  let queueSummary = $derived(summarizeQueue(integration?.queue));
  let linkedBoilers = $derived(integration?.linked_boilers || []);
  let trackerOptions = $derived(integration?.available_trackers || []);
  let watchOptions = $derived(integration?.available_watches || []);
  let linkedWatch = $derived(integration?.linked_watch || null);
  let currentTelemetryLink = $derived(integration?.current_link || null);
  let clawOptions = $derived(integration?.available_claws || []);
  let linkedClaws = $derived(clawOptions.filter((claw: any) => claw?.linked));
  let selectedTrackerOption = $derived(
    trackerOptions.find((tracker: any) => tracker?.name === selectedTracker) || null,
  );
  let selectedTrackerPipelines = $derived(
    Array.isArray(selectedTrackerOption?.pipelines) ? selectedTrackerOption.pipelines : [],
  );
  let selectedPipelineOption = $derived(
    selectedTrackerPipelines.find((pipeline: any) => pipeline?.id === selectedPipeline) || null,
  );
  let selectedPipelineRoles = $derived(
    Array.isArray(selectedPipelineOption?.roles) ? selectedPipelineOption.roles : [],
  );
  let selectedPipelineTriggers = $derived(
    Array.isArray(selectedPipelineOption?.triggers) ? selectedPipelineOption.triggers : [],
  );
  let standaloneHomeEnv = $derived(componentHomeEnv(component));
  let standaloneHomePath = $derived(`$NULLHUB_HOME/instances/${component}/${name}`);
  let standaloneConfigPath = $derived(`${standaloneHomePath}/config.json`);
  let hasStandaloneBinary = $derived(Boolean(instance?.version && instance.version !== "standalone"));
  let standaloneBinaryName = $derived(
    hasStandaloneBinary ? managedBinaryName(component, instance.version) : "",
  );
  let standaloneBinaryPath = $derived(
    standaloneBinaryName ? `$NULLHUB_HOME/bin/${standaloneBinaryName}` : "",
  );
  let standaloneLaunchScript = $derived(
    hasStandaloneBinary
      ? buildStandaloneLaunchScript(
          component,
          name,
          instance?.version,
          instance?.launch_mode,
          instance?.verbose,
          standaloneHomeEnv,
        )
      : "",
  );

  function extractModel(cfg: any): string | null {
    if (!cfg) return null;
    try {
      if (cfg.channels?.gateway?.model) return cfg.channels.gateway.model;
      if (cfg.model) return cfg.model;
      if (cfg.channels?.web?.model) return cfg.channels.web.model;
    } catch {
      /* ignore */
    }
    return null;
  }

  function isLocalEndpoint(url: string): boolean {
    return (
      url.startsWith("http://localhost") ||
      url.startsWith("https://localhost") ||
      url.startsWith("http://127.") ||
      url.startsWith("https://127.") ||
      url.startsWith("http://0.0.0.0") ||
      url.startsWith("https://0.0.0.0") ||
      url.startsWith("http://[::1]") ||
      url.startsWith("https://[::1]")
    );
  }

  function knownCompatibleProviderUrl(provider: string): string | null {
    if (provider === "lmstudio" || provider === "lm-studio") return "http://localhost:1234/v1";
    if (provider === "vllm") return "http://localhost:8000/v1";
    if (provider === "llamacpp" || provider === "llama.cpp") return "http://localhost:8080/v1";
    if (provider === "sglang") return "http://localhost:30000/v1";
    if (provider === "osaurus") return "http://localhost:1337/v1";
    if (provider === "litellm") return "http://localhost:4000";
    return null;
  }

  function providerRequiresApiKey(provider: string, providerEntry: any): boolean {
    if (
      provider === "ollama" ||
      provider === "claude-cli" ||
      provider === "codex-cli" ||
      provider === "openai-codex"
    ) {
      return false;
    }

    const configuredBaseUrl = providerEntry?.base_url || providerEntry?.api_url || "";
    if (configuredBaseUrl) return !isLocalEndpoint(configuredBaseUrl);

    if (provider.startsWith("custom:")) return !isLocalEndpoint(provider.slice("custom:".length));

    const knownUrl = knownCompatibleProviderUrl(provider);
    if (knownUrl) return !isLocalEndpoint(knownUrl);

    return true;
  }

  function extractProviderStatus(cfg: any): {
    provider: string;
    model: string;
    configured: boolean;
  } {
    const none = { provider: "", model: "", configured: false };
    if (!cfg) return none;
    try {
      const primary = cfg.agents?.defaults?.model?.primary || "";
      if (!primary) return none;
      const parts = primary.split("/");
      const provider = parts.length > 1 ? parts[0] : primary;
      const model = parts.length > 1 ? parts.slice(1).join("/") : primary;
      const providers = cfg.models?.providers || {};
      const providerEntry = providers[provider] || {};
      const hasApiKey = Boolean(providerEntry?.api_key);
      const configured = !providerRequiresApiKey(provider, providerEntry) || hasApiKey;
      return { provider, model, configured };
    } catch {
      return none;
    }
  }

  function extractWebPort(cfg: any): number | null {
    if (!cfg) return null;
    try {
      if (cfg.channels?.web?.accounts?.default?.port)
        return cfg.channels.web.accounts.default.port;
      if (cfg.channels?.web?.port) return cfg.channels.web.port;
      if (cfg.web_port) return cfg.web_port;
    } catch {
      /* ignore */
    }
    return null;
  }

  function formatUptime(seconds: number | undefined): string {
    if (!seconds && seconds !== 0) return "-";
    if (seconds < 60) return `${seconds}s`;
    const m = Math.floor(seconds / 60);
    if (m < 60) return `${m}m ${seconds % 60}s`;
    const h = Math.floor(m / 60);
    if (h < 24) return `${h}h ${m % 60}m`;
    const d = Math.floor(h / 24);
    return `${d}d ${h % 24}h`;
  }

  function formatTokens(value: number | undefined): string {
    const v = value ?? 0;
    return v.toLocaleString();
  }

  function formatLastUsed(ts: number | undefined): string {
    if (!ts) return "-";
    try {
      return new Date(ts * 1000).toLocaleString();
    } catch {
      return "-";
    }
  }

  function setStandaloneCopyState(state: "idle" | "copied" | "error") {
    standaloneCopyState = state;
    if (standaloneCopyTimer) clearTimeout(standaloneCopyTimer);
    if (state !== "idle") {
      standaloneCopyTimer = setTimeout(() => {
        standaloneCopyState = "idle";
        standaloneCopyTimer = null;
      }, 1600);
    } else {
      standaloneCopyTimer = null;
    }
  }

  function componentHomeEnv(componentName: string): string {
    if (componentName === "nullclaw") return "NULLCLAW_HOME";
    if (componentName === "nullboiler") return "NULLBOILER_HOME";
    if (componentName === "nulltickets") return "NULLTICKETS_HOME";
    if (componentName === "nullwatch") return "NULLWATCH_HOME";
    return "COMPONENT_HOME";
  }

  function componentPortLabel(componentName: string): string {
    if (componentName === "nullclaw") return "Gateway";
    return "API";
  }

  function formatLaunchMode(launchMode: string | undefined): string {
    const mode = launchMode || (component === "nullclaw" ? "gateway" : "server");
    if (mode === "agent") return "Agent";
    if (mode === "gateway") return "Gateway";
    if (mode === "server" || mode === "serve") return "Server";
    return mode;
  }

  function shellQuote(value: string): string {
    if (value === "") return "''";
    return `'${value.replaceAll("'", `'\"'\"'`)}'`;
  }

  function tokenizeLaunchMode(launchMode: string): string[] {
    if (launchMode === "server") return [];
    return launchMode
      .split(/\s+/)
      .map((token) => token.trim())
      .filter(Boolean);
  }

  function defaultLaunchMode(componentName: string): string {
    if (componentName === "nullboiler" || componentName === "nulltickets") return "server";
    if (componentName === "nullwatch") return "serve";
    return "gateway";
  }

  function managedBinaryName(componentName: string, version: string | undefined): string {
    if (!version) return "";
    if (version === "dev-local") return componentName;
    return `${componentName}-${version}`;
  }

  function normalizedLaunchArgs(componentName: string, launchMode: string | undefined): string[] {
    const args = tokenizeLaunchMode(launchMode || defaultLaunchMode(componentName));
    const fallback = defaultLaunchMode(componentName);
    if (args.length === 0 && fallback !== "server") args.push(fallback);
    if (componentName === "nullwatch" && args[0] === "nullwatch") {
      args[0] = "serve";
    }
    return args;
  }

  function displayLaunchMode(launchMode: string | undefined): string {
    const tokens = normalizedLaunchArgs(component, launchMode);
    const primary = tokens[0] || defaultLaunchMode(component);
    if (primary === "agent") return "Agent";
    if (primary === "gateway") return "Gateway";
    if (primary === "serve") return "Serve";
    if (primary === "server") return "Server";
    return primary;
  }

  function buildStandaloneLaunchScript(
    componentName: string,
    instanceName: string,
    version: string | undefined,
    launchMode: string | undefined,
    verbose: boolean | undefined,
    homeEnv: string,
  ): string {
    if (!version) return "";

    const args = normalizedLaunchArgs(componentName, launchMode);
    if (verbose) args.push("--verbose");

    const command = [
      `"$NULLHUB_HOME/bin/${managedBinaryName(componentName, version)}"`,
      ...args.map(shellQuote),
    ].join(" ");

    return [
      'export NULLHUB_HOME="${NULLHUB_HOME:-$HOME/.nullhub}"',
      `export ${homeEnv}="$NULLHUB_HOME/instances/${componentName}/${instanceName}"`,
      command,
    ].join("\n");
  }

  async function copyStandaloneLaunchScript() {
    if (!standaloneLaunchScript) return;
    try {
      await navigator.clipboard.writeText(standaloneLaunchScript);
      setStandaloneCopyState("copied");
    } catch {
      setStandaloneCopyState("error");
    }
  }

  function handleStandaloneLaunchKeydown(event: KeyboardEvent) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      void copyStandaloneLaunchScript();
    }
  }

  function buildProviderHint(
    status: { provider: string; configured: boolean },
    probe: any,
    probeLoading: boolean,
  ): string {
    if (!status.provider) return "";
    if (probeLoading) return "Checking live auth...";
    if (!probe) return "";
    if (probe.live_ok) {
      return "";
    }
    const code = probe.status_code ? ` (HTTP ${probe.status_code})` : "";
    switch (probe.reason) {
      case "invalid_api_key":
        return "Invalid API key (401)";
      case "missing_api_key":
        return "No API key";
      case "instance_not_running":
        return "Instance is not running";
      case "rate_limited":
        return "Rate limited (429)";
      case "forbidden":
        return "Forbidden (403)";
      case "provider_unavailable":
        return `Provider unavailable${code}`;
      case "network_error":
        return "Network error during auth check";
      case "provider_rejected":
        return "Provider rejected probe (check credentials/model)";
      case "probe_exec_failed":
      case "probe_request_failed":
        return "Probe request failed";
      case "config_load_failed":
        return "Probe could not load config";
      case "component_binary_missing":
        return "Component binary missing for probe";
      case "probe_home_path_failed":
        return "Probe home path failed";
      case "invalid_probe_response":
        return "Probe returned invalid response";
      default:
        return `Auth check failed${code}`;
    }
  }

  function summarizeQueue(queue: any): {
    roles: any[];
    claimable: number;
    failed: number;
    stuck: number;
    nearExpiry: number;
  } {
    const roles = Array.isArray(queue?.roles) ? queue.roles : [];
    let claimable = 0;
    let failed = 0;
    let stuck = 0;
    let nearExpiry = 0;
    for (const role of roles) {
      claimable += Number(role?.claimable_count || 0);
      failed += Number(role?.failed_count || 0);
      stuck += Number(role?.stuck_count || 0);
      nearExpiry += Number(role?.near_expiry_leases || 0);
    }
    return { roles, claimable, failed, stuck, nearExpiry };
  }

  function normalizeCollectionResult(result: any): any[] {
    if (Array.isArray(result)) return result;
    if (Array.isArray(result?.items)) return result.items;
    if (Array.isArray(result?.tasks)) return result.tasks;
    if (Array.isArray(result?.pipelines)) return result.pipelines;
    return [];
  }

  function pipelineId(pipeline: any): string {
    return String(pipeline?.id || pipeline?.name || "");
  }

  function pipelineName(pipeline: any): string {
    return String(pipeline?.name || pipeline?.id || "pipeline");
  }

  function taskTitle(task: any): string {
    return String(task?.title || task?.id || "task");
  }

  function firstQueueRole(): string {
    const role = queueSummary.roles.find((item: any) => Number(item?.claimable_count || 0) > 0)?.role ||
      queueSummary.roles[0]?.role;
    return typeof role === "string" && role.length > 0 ? role : "coder";
  }

  async function refreshTicketsData(force = false) {
    if (component !== "nulltickets") return;
    if (integration?.instance?.running !== true && instance?.status !== "running") {
      ticketsPipelines = [];
      ticketsTasks = [];
      ticketsDataError = "";
      return;
    }

    const now = Date.now();
    if (!force && now - lastTicketsRefreshAt < 5_000) return;
    lastTicketsRefreshAt = now;
    ticketsDataLoading = true;
    try {
      const [pipelinesResult, tasksResult] = await Promise.all([
        api.nullTicketsPipelines(component, name),
        api.nullTicketsTasks(component, name, { limit: 8 }),
      ]);
      ticketsPipelines = normalizeCollectionResult(pipelinesResult);
      ticketsTasks = normalizeCollectionResult(tasksResult);
      if (!ticketTaskPipeline || !ticketsPipelines.some((pipeline) => pipelineId(pipeline) === ticketTaskPipeline)) {
        ticketTaskPipeline = pipelineId(ticketsPipelines[0] || {});
      }
      if (!ticketClaimRole) ticketClaimRole = firstQueueRole();
      ticketsDataError = "";
    } catch (e) {
      ticketsDataError = (e as Error).message;
    } finally {
      ticketsDataLoading = false;
    }
  }

  async function refreshIntegration() {
    if (!supportsIntegration) {
      integration = null;
      integrationError = null;
      return;
    }

    integrationLoading = true;
    try {
      integration = await api.getIntegration(component, name);
      integrationError = null;
      if (component === "nullboiler") {
        const currentLink = integration?.current_link;
        const availableTrackers = Array.isArray(integration?.available_trackers)
          ? integration.available_trackers
          : [];
        const selectedStillAvailable = availableTrackers.some(
          (tracker: any) => tracker?.name === selectedTracker,
        );
        selectedTracker =
          integration?.linked_tracker?.name ||
          (selectedStillAvailable ? selectedTracker : availableTrackers[0]?.name) ||
          "";
        selectedPipeline =
          currentLink?.pipeline_id || (selectedStillAvailable ? selectedPipeline : "") || "";
        trackerClaimRole = currentLink?.claim_role || trackerClaimRole || "coder";
        trackerSuccessTrigger =
          currentLink?.success_trigger || trackerSuccessTrigger || "complete";
        trackerConcurrency =
          String(currentLink?.max_concurrent_tasks || trackerConcurrency || "1");
      } else if (component === "nulltickets") {
        if (!ticketClaimRole) ticketClaimRole = firstQueueRole();
        await refreshTicketsData();
      } else if (component === "nullclaw") {
        selectedWatch =
          integration?.linked_watch?.name ||
          selectedWatch ||
          integration?.available_watches?.[0]?.name ||
          "";
      } else if (component === "nullwatch") {
        const unlinked = integration?.available_claws?.find((claw: any) => !claw?.linked);
        selectedClaw =
          selectedClaw ||
          unlinked?.name ||
          integration?.available_claws?.[0]?.name ||
          "";
      }
    } catch (e) {
      integration = null;
      integrationError = (e as Error).message;
    } finally {
      integrationLoading = false;
    }
  }

  async function linkTracker() {
    if (component !== "nullboiler" || !selectedTracker || !selectedPipeline.trim()) return;

    linkingIntegration = true;
    try {
      const payload: Record<string, any> = {
        tracker_instance: selectedTracker,
        pipeline_id: selectedPipeline.trim(),
        claim_role: trackerClaimRole || "coder",
        success_trigger: trackerSuccessTrigger.trim() || "complete",
        max_concurrent_tasks: Math.max(1, Number(trackerConcurrency || "1") || 1),
      };
      await api.linkIntegration(component, name, payload);
      await refresh();
      integrationError = null;
    } catch (e) {
      integrationError = (e as Error).message;
    } finally {
      linkingIntegration = false;
    }
  }

  async function openBoilerRoute(route: string) {
    if (component !== "nullboiler") return;
    setSelectedBoilerInstance(name);
    await goto(withBoilerInstance(route, name));
  }

  async function openTicketsStore() {
    if (component !== "nulltickets") return;
    setSelectedTicketsInstance(name);
    await goto(withTicketsInstance(orchestrationUiRoutes.store(), name));
  }

  async function createTicketTask() {
    if (component !== "nulltickets") return;
    const pipeline_id = ticketTaskPipeline.trim();
    const title = ticketTaskTitle.trim();
    if (!pipeline_id || !title) return;

    ticketsDataLoading = true;
    ticketsActionError = "";
    ticketsActionMessage = "";
    try {
      const priority = Number.parseInt(ticketTaskPriority || "0", 10);
      const result = await api.nullTicketsCreateTask(component, name, {
        pipeline_id,
        title,
        description: ticketTaskDescription.trim(),
        priority: Number.isFinite(priority) ? priority : 0,
        metadata: { source: "nullhub-ui" },
        assigned_by: "nullhub",
      });
      ticketTaskTitle = "";
      ticketTaskDescription = "";
      claimedTicket = null;
      ticketsActionMessage = `Task ${result?.id || ""} created`.trim();
      await refreshIntegration();
      await refreshTicketsData(true);
    } catch (e) {
      ticketsActionError = (e as Error).message;
    } finally {
      ticketsDataLoading = false;
    }
  }

  async function claimTicketTask() {
    if (component !== "nulltickets") return;
    const agent_id = ticketClaimAgent.trim() || "nullhub";
    const agent_role = ticketClaimRole.trim() || "coder";
    const lease_ttl_ms = Math.max(1000, Number.parseInt(ticketClaimTtl || "300000", 10) || 300000);

    ticketsDataLoading = true;
    ticketsActionError = "";
    ticketsActionMessage = "";
    try {
      const result = await api.nullTicketsClaimTask(component, name, {
        agent_id,
        agent_role,
        lease_ttl_ms,
      });
      if (result?.task) {
        claimedTicket = result;
        ticketsActionMessage = `Claimed ${result.task.id || "task"}`;
      } else {
        claimedTicket = null;
        ticketsActionMessage = "No claimable task";
      }
      await refreshIntegration();
      await refreshTicketsData(true);
    } catch (e) {
      ticketsActionError = (e as Error).message;
    } finally {
      ticketsDataLoading = false;
    }
  }

  async function linkNullWatch() {
    if (component !== "nullclaw" || !selectedWatch) return;

    linkingIntegration = true;
    try {
      await api.linkIntegration(component, name, { watch_instance: selectedWatch });
      await refresh();
    } finally {
      linkingIntegration = false;
    }
  }

  async function linkNullClawToWatch() {
    if (component !== "nullwatch" || !selectedClaw) return;

    linkingIntegration = true;
    try {
      await api.linkIntegration(component, name, { claw_instance: selectedClaw });
      await refresh();
    } finally {
      linkingIntegration = false;
    }
  }

  async function refreshProviderHealth(cfgOverride: any = config) {
    const status = extractProviderStatus(cfgOverride);
    if (!status.provider) {
      providerHealthLoading = false;
      providerHealth = null;
      return;
    }

    providerHealthLoading = true;
    try {
      providerHealth = await api.getProviderHealth(component, name);
    } catch {
      providerHealth = {
        provider: status.provider,
        configured: status.configured,
        running: instance?.status === "running",
        live_ok: false,
        status: "error",
        reason: "probe_request_failed",
      };
    } finally {
      providerHealthLoading = false;
    }
  }

  async function refreshUsage(force = false) {
    if (!supportsUsage) {
      usageData = null;
      usageLoading = false;
      return;
    }
    const now = Date.now();
    if (!force && now - lastUsageRefreshAt < 15_000) return;
    lastUsageRefreshAt = now;
    usageLoading = true;
    try {
      usageData = await api.getUsage(component, name, usageWindow);
    } catch {
      usageData = {
        window: usageWindow,
        rows: [],
        totals: {
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          requests: 0,
        },
      };
    } finally {
      usageLoading = false;
    }
  }

  async function refresh(loadProviderHealth = false, forceUsage = false) {
    const prevStatus = instance?.status;
    try {
      const status = await api.getStatus();
      const instances = status.instances || {};
      if (instances[component] && instances[component][name]) {
        instance = instances[component][name];
      }
    } catch (e) {
      console.error(e);
    }
    // Re-fetch provider health when the instance just became running (stale probe from boot)
    const justBecameRunning = instance?.status === "running" && prevStatus !== "running";
    // Fetch config (best-effort)
    let loadedConfig: any = null;
    try {
      loadedConfig = await api.getConfig(component, name);
      config = loadedConfig;
    } catch {
      config = null;
      providerHealth = null;
    }
    if (component === "nullclaw") {
      try {
        onboardingStatus = await api.getOnboarding(component, name);
      } catch {
        onboardingStatus = null;
      }
    } else {
      onboardingStatus = null;
    }
    if (loadProviderHealth || justBecameRunning) {
      await refreshProviderHealth(loadedConfig);
    }
    await refreshUsage(forceUsage);
    await refreshIntegration();
    // Fetch installed UI modules (best-effort)
    try {
      const res = await api.getUiModules();
      uiModules = res.modules || {};
    } catch {
      /* ignore */
    }
  }

  $effect(() => {
    usageWindow;
    if (!supportsUsage) return;
    if (!component || !name) return;
    void refreshUsage(true);
  });

  $effect(() => {
    if (component !== "nullboiler" || !selectedTracker) return;
    if (selectedTrackerPipelines.length === 0) return;
    if (!selectedPipeline || !selectedTrackerPipelines.some((pipeline: any) => pipeline?.id === selectedPipeline)) {
      selectedPipeline = selectedTrackerPipelines[0]?.id || "";
    }
  });

  $effect(() => {
    if (component !== "nullboiler") return;
    if (selectedPipelineRoles.length > 0 && !selectedPipelineRoles.includes(trackerClaimRole)) {
      trackerClaimRole = selectedPipelineRoles[0];
    }
    if (selectedPipelineTriggers.length > 0 && !selectedPipelineTriggers.includes(trackerSuccessTrigger)) {
      trackerSuccessTrigger = selectedPipelineTriggers[0];
    }
  });

  $effect(() => {
    component;
    name;
    if (activeTab === "chat" && !supportsChat) {
      activeTab = "overview";
    }
    if ((activeTab === "history" || activeTab === "memory" || activeTab === "skills") && !supportsAgentData) {
      activeTab = "overview";
    }
    if (activeTab === "tickets" && !supportsTicketsUi) {
      activeTab = "overview";
    }
    if (activeTab === "boiler" && !supportsBoilerUi) {
      activeTab = "overview";
    }
  });

  $effect(() => {
    const marker = onboardingPending
      ? `${instanceRouteKey}:${onboardingMarker || "bootstrap"}`
      : "";
    if (!marker || !chatReady) return;
    if (activeTab !== "overview") return;
    if (bootstrapChatAutoOpenedFor === marker) return;

    bootstrapChatAutoOpenedFor = marker;
    activeTab = "chat";
  });

  $effect(() => {
    if (!component || !name) return;
    if (initializedRouteKey === instanceRouteKey) return;
    initializedRouteKey = instanceRouteKey;
    instance = null;
    config = null;
    providerHealth = null;
    usageData = null;
    integration = null;
    integrationError = null;
    linkingIntegration = false;
    selectedWatch = "";
    selectedClaw = "";
    selectedTracker = "";
    selectedPipeline = "";
    trackerClaimRole = "coder";
    trackerSuccessTrigger = "complete";
    trackerConcurrency = "1";
    ticketsPipelines = [];
    ticketsTasks = [];
    ticketsDataError = "";
    ticketsActionError = "";
    ticketsActionMessage = "";
    ticketTaskPipeline = "";
    ticketTaskTitle = "";
    ticketTaskDescription = "";
    ticketTaskPriority = "0";
    ticketClaimAgent = "nullhub";
    ticketClaimRole = "coder";
    ticketClaimTtl = "300000";
    claimedTicket = null;
    lastTicketsRefreshAt = 0;
    onboardingStatus = null;
    bootstrapChatAutoOpenedFor = "";
    lastUsageRefreshAt = 0;
    void refresh(true, true);
  });

  onMount(() => {
    const interval = setInterval(refresh, 3000);
    return () => clearInterval(interval);
  });

  async function start() {
    loading = true;
    instance = { ...instance, status: "starting" };
    try {
      await api.startInstance(component, name, { verbose: Boolean(instance?.verbose) });
      await refresh();
    } catch {
      instance = { ...instance, status: "stopped" };
    } finally {
      loading = false;
    }
  }
  async function startAgent() {
    loading = true;
    instance = { ...instance, status: "starting" };
    try {
      await api.startInstance(component, name, {
        launch_mode: "agent",
        verbose: Boolean(instance?.verbose),
      });
      await refresh();
    } catch {
      instance = { ...instance, status: "stopped" };
    } finally {
      loading = false;
    }
  }
  async function stop() {
    loading = true;
    instance = { ...instance, status: "stopping" };
    try {
      await api.stopInstance(component, name);
      await refresh();
    } catch {
      instance = { ...instance, status: "running" };
    } finally {
      loading = false;
    }
  }
  async function restart() {
    loading = true;
    instance = { ...instance, status: "restarting" };
    try {
      await api.restartInstance(component, name, { verbose: Boolean(instance?.verbose) });
      await refresh();
    } catch {
    } finally {
      loading = false;
    }
  }
  function clearDeletedInstanceSelection() {
    if (component === "nullboiler" && getSelectedBoilerInstance() === name) {
      setSelectedBoilerInstance("");
    }
    if (component === "nulltickets" && getSelectedTicketsInstance() === name) {
      setSelectedTicketsInstance("");
    }
  }
  async function deleteInstanceAndLeave(force = false) {
    await api.deleteInstance(component, name, force ? { force: true } : undefined);
    clearDeletedInstanceSelection();
    await goto("/");
  }
  function formatDeleteDependents(body: any): string {
    const dependents = Array.isArray(body?.dependents) ? body.dependents : [];
    if (dependents.length === 0) return "linked instances";
    return dependents
      .map((dep: any) => {
        const id = `${dep?.component || "instance"}/${dep?.name || "unknown"}`;
        return dep?.relation ? `${id} (${dep.relation})` : id;
      })
      .join(", ");
  }
  async function remove() {
    if (confirm("Are you sure you want to delete this instance?")) {
      loading = true;
      try {
        await deleteInstanceAndLeave();
      } catch (e) {
        const error = e as ApiRequestError;
        if (error.status === 409 && error.body?.force_required) {
          const dependents = formatDeleteDependents(error.body);
          if (
            confirm(
              `This instance is linked by ${dependents}. Delete it anyway and unlink those references?`,
            )
          ) {
            try {
              await deleteInstanceAndLeave(true);
            } catch (forceError) {
              console.error(forceError);
            }
          }
          return;
        }
        console.error(e);
      } finally {
        loading = false;
      }
    }
  }
  async function setMode(mode: string) {
    await api.patchInstance(component, name, { launch_mode: mode });
    await refresh();
  }
  async function toggleAutoStart() {
    await api.patchInstance(component, name, {
      auto_start: !instance?.auto_start,
    });
    await refresh();
  }
  async function toggleVerbose() {
    await api.patchInstance(component, name, {
      verbose: !instance?.verbose,
    });
    await refresh();
  }
</script>

<div class="instance-detail">
  <div class="detail-header">
    <div>
      <h1>{name}</h1>
      <span class="component-tag">{component}</span>
    </div>
    <div class="actions">
      <button class="btn" onclick={start} disabled={loading}>Start</button>
      {#if supportsAgentData}
        <button class="btn" onclick={startAgent} disabled={loading}>Agent</button>
      {/if}
      <button class="btn" onclick={stop} disabled={loading}>Stop</button>
      <button class="btn" onclick={restart} disabled={loading}>Restart</button>
      {#if component === "nullwatch"}
        <a class="btn" href={`/observability?watch=${encodeURIComponent(name)}`}>Observability</a>
      {/if}
      <button class="btn danger" onclick={remove} disabled={loading}
        >Delete</button
      >
    </div>
  </div>

  <div class="tabs">
    <button
      class:active={activeTab === "overview"}
      onclick={() => (activeTab = "overview")}>Overview</button
    >
    {#if supportsChat}
      <button
        class:active={activeTab === "chat"}
        class:disabled-tab={!chatReady}
        onclick={() => (activeTab = "chat")}
        >Chat{#if !providerStatus.configured}<span class="tab-warn">!</span
          >{/if}</button
      >
    {/if}
    {#if supportsAgentData}
      <button
        class:active={activeTab === "history"}
        onclick={() => (activeTab = "history")}>History</button
      >
      <button
        class:active={activeTab === "memory"}
        onclick={() => (activeTab = "memory")}>Memory</button
      >
      <button
        class:active={activeTab === "skills"}
        onclick={() => (activeTab = "skills")}>Skills</button
      >
    {/if}
    {#if supportsTicketsUi}
      <button
        class:active={activeTab === "tickets"}
        onclick={() => (activeTab = "tickets")}>Tickets</button
      >
    {/if}
    {#if supportsBoilerUi}
      <button
        class:active={activeTab === "boiler"}
        onclick={() => (activeTab = "boiler")}>Boiler</button
      >
    {/if}
    <button
      class:active={activeTab === "config"}
      onclick={() => (activeTab = "config")}>Config</button
    >
    <button
      class:active={activeTab === "logs"}
      onclick={() => (activeTab = "logs")}>Logs</button
    >
    <button
      class:active={activeTab === "advanced"}
      onclick={() => (activeTab = "advanced")}>Advanced</button
    >
  </div>

  <div class="tab-content">
    {#if activeTab === "overview"}
      <div class="overview-grid">
        <div class="info-card">
          <span class="label">Status</span>
          <StatusBadge status={instance?.status || "stopped"} />
        </div>
        <div class="info-card">
          <span class="label">Version</span>
          <span>{instance?.version || "-"}</span>
        </div>
        <div class="info-card">
          <span class="label">Launch Mode</span>
          <span class="mode-value">{displayLaunchMode(instance?.launch_mode)}</span>
        </div>
        <div class="info-card">
          <span class="label">Auto Start</span>
          <button
            class="toggle-btn"
            class:on={instance?.auto_start}
            onclick={toggleAutoStart}
          >
            <span class="toggle-track"><span class="toggle-thumb"></span></span>
            {instance?.auto_start ? "On" : "Off"}
          </button>
        </div>
        {#if supportsVerboseStartup}
          <div class="info-card">
            <span class="label">Verbose</span>
            <button
              class="toggle-btn"
              class:on={instance?.verbose}
              onclick={toggleVerbose}
            >
              <span class="toggle-track"><span class="toggle-thumb"></span></span>
              {instance?.verbose ? "On" : "Off"}
            </button>
          </div>
        {/if}
        {#if instance?.pid}
          <div class="info-card">
            <span class="label">PID</span>
            <span class="mono">{instance.pid}</span>
          </div>
        {/if}
        {#if instance?.status === "running" && instance?.uptime_seconds != null}
          <div class="info-card">
            <span class="label">Uptime</span>
            <span>{formatUptime(instance.uptime_seconds)}</span>
          </div>
        {/if}
        {#if instance?.port}
          <div class="info-card">
            <span class="label">{componentPortLabel(component)} Port</span>
            <span class="mono">{instance.port}</span>
          </div>
        {/if}
        {#if instance?.restart_count}
          <div class="info-card">
            <span class="label">Restart Count</span>
            <span>{instance.restart_count}</span>
          </div>
        {/if}
        {#if providerStatus.provider}
          <div class="info-card" class:card-warn={providerCardWarn}>
            <span class="label">Provider</span>
            <div class="provider-status">
              <span
                class="status-dot"
                class:ok={providerDotOk}
                class:err={!providerDotOk}
              ></span>
              <span>{providerStatus.provider}</span>
            </div>
            {#if providerHintText}
              <span class="provider-hint">{providerHintText}</span>
            {/if}
          </div>
        {/if}
        {#if providerStatus.model}
          <div class="info-card">
            <span class="label">Model</span>
            <span>{providerStatus.model}</span>
          </div>
        {/if}
        {#if webPort}
          <div class="info-card">
            <span class="label">Web Channel Port</span>
            <span class="mono">{webPort}</span>
          </div>
        {/if}
        {#if supportsIntegration}
          <div class="info-card integration-card">
            <div class="integration-header">
              <span class="label"
                >{component === "nullclaw"
                  ? "NullWatch Telemetry"
                  : component === "nullwatch"
                    ? "Observed NullClaws"
                  : component === "nullboiler"
                    ? "NullTickets Link"
                    : "Linked NullBoilers"}</span
              >
              {#if (component === "nullboiler" && integration?.linked_tracker) || (component === "nullclaw" && linkedWatch) || (component === "nullwatch" && linkedClaws.length > 0) || (component === "nulltickets" && linkedBoilers.length > 0)}
                <span class="integration-badge">Linked</span>
              {/if}
            </div>

            {#if integrationLoading && !integration}
              <span class="integration-muted">Loading integration status...</span>
            {:else if integrationError}
              <span class="integration-error">{integrationError}</span>
            {:else if component === "nullclaw"}
              <div class="integration-block">
                <span class="integration-title">Observer</span>
                {#if linkedWatch}
                  <span class="mono">{linkedWatch.name}:{linkedWatch.port}</span>
                {:else if currentTelemetryLink}
                  <span class="integration-muted mono">{currentTelemetryLink.endpoint}</span>
                {:else}
                  <span class="integration-muted">No NullWatch linked yet.</span>
                {/if}
              </div>

              {#if currentTelemetryLink}
                <div class="integration-block">
                  <span class="integration-title">OTLP</span>
                  <div class="integration-stats compact">
                    <div>
                      <span class="stat-label">Endpoint</span>
                      <span class="mono">{currentTelemetryLink.endpoint}</span>
                    </div>
                    <div>
                      <span class="stat-label">Service</span>
                      <span class="mono">{currentTelemetryLink.service_name || "-"}</span>
                    </div>
                    <div>
                      <span class="stat-label">Auth</span>
                      <span>{currentTelemetryLink.auth_header ? "Bearer" : "None"}</span>
                    </div>
                    <div>
                      <span class="stat-label">Source Header</span>
                      <span>{currentTelemetryLink.source_header ? "On" : "Off"}</span>
                    </div>
                  </div>
                </div>
              {/if}

              {#if watchOptions.length > 0}
                <div class="integration-form">
                  <label class="integration-field">
                    <span>Local observer</span>
                    <select bind:value={selectedWatch} disabled={linkingIntegration}>
                      <option value="">Select NullWatch</option>
                      {#each watchOptions as watch}
                        <option value={watch.name}>
                          {watch.name} ({watch.port}){watch.running ? "" : " - stopped"}
                        </option>
                      {/each}
                    </select>
                  </label>
                  <button
                    class="btn integration-btn"
                    onclick={linkNullWatch}
                    disabled={linkingIntegration || !selectedWatch}
                  >
                    {linkingIntegration
                      ? "Linking..."
                      : linkedWatch
                        ? "Relink NullWatch"
                        : "Link NullWatch"}
                  </button>
                  {#if linkedWatch}
                    <a
                      class="btn integration-btn"
                      href={`/observability?watch=${encodeURIComponent(linkedWatch.name)}`}
                      >Open Observability</a
                    >
                  {/if}
                </div>
              {:else}
                <span class="integration-muted">Install NullWatch to link telemetry.</span>
              {/if}
            {:else if component === "nullwatch"}
              <div class="integration-block">
                <span class="integration-title">Linked NullClaws</span>
                {#if linkedClaws.length > 0}
                  <div class="integration-list">
                    {#each linkedClaws as claw}
                      <div class="integration-list-item">
                        <div>
                          <span class="integration-title">{claw.name}</span>
                          <span class="integration-muted"
                            >{claw.running ? "running" : "stopped"}</span
                          >
                        </div>
                        <a class="btn integration-btn" href={`/instances/nullclaw/${encodeURIComponent(claw.name)}`}
                          >Open</a
                        >
                      </div>
                    {/each}
                  </div>
                {:else}
                  <span class="integration-muted">No NullClaw instances linked yet.</span>
                {/if}
              </div>

              {#if clawOptions.length > 0}
                <div class="integration-form">
                  <label class="integration-field">
                    <span>Local NullClaw</span>
                    <select bind:value={selectedClaw} disabled={linkingIntegration}>
                      <option value="">Select NullClaw</option>
                      {#each clawOptions as claw}
                        <option value={claw.name}>
                          {claw.name}{claw.linked ? " - linked" : ""}{claw.running ? "" : " - stopped"}
                        </option>
                      {/each}
                    </select>
                  </label>
                  <button
                    class="btn integration-btn"
                    onclick={linkNullClawToWatch}
                    disabled={linkingIntegration || !selectedClaw}
                  >
                    {linkingIntegration ? "Linking..." : "Link NullClaw"}
                  </button>
                  <a
                    class="btn integration-btn"
                    href={`/observability?watch=${encodeURIComponent(name)}`}
                    >Open Observability</a
                  >
                </div>
              {:else}
                <span class="integration-muted">Install NullClaw to send telemetry here.</span>
              {/if}
            {:else if component === "nullboiler"}
              <div class="integration-block">
                <span class="integration-title">NullBoiler</span>
                <span class="mono">
                  {integration?.instance?.name || name}:{integration?.instance?.port || instance?.port || "-"}
                </span>
                {#if integration?.instance?.running === true}
                  <span class="integration-badge">Running</span>
                {:else if integration?.instance?.running === false}
                  <span class="integration-muted">Stopped</span>
                {/if}
              </div>

              <div class="integration-block">
                <span class="integration-title">Tracker</span>
                {#if integration?.linked_tracker}
                  <span class="mono"
                    >{integration.linked_tracker.name}:{integration.linked_tracker.port}</span
                  >
                {:else if integration?.configured_tracker?.url}
                  <span class="mono">{integration.configured_tracker.url}</span>
                  <span class="integration-muted">No matching local NullTickets instance.</span>
                {:else if integration?.configured}
                  <span class="integration-muted">Tracker config exists without a target URL.</span>
                {:else}
                  <span class="integration-muted">No tracker linked yet.</span>
                {/if}
              </div>

              {#if integration?.tracker}
                <div class="integration-stats">
                  <div>
                    <span class="stat-label">Running</span>
                    <span>{integration.tracker.running_count || 0}</span>
                  </div>
                  <div>
                    <span class="stat-label">Completed</span>
                    <span>{integration.tracker.completed_count || 0}</span>
                  </div>
                  <div>
                    <span class="stat-label">Failed</span>
                    <span>{integration.tracker.failed_count || 0}</span>
                  </div>
                  <div>
                    <span class="stat-label">Max Concurrent</span>
                    <span>{integration.tracker.max_concurrent || 0}</span>
                  </div>
                </div>
              {/if}

              {#if integration?.current_link}
                <div class="integration-block">
                  <span class="integration-title">Workflow</span>
                  <div class="integration-stats compact">
                    <div>
                      <span class="stat-label">Pipeline</span>
                      <span class="mono">{integration.current_link.pipeline_id}</span>
                    </div>
                    <div>
                      <span class="stat-label">Claim Role</span>
                      <span class="mono">{integration.current_link.claim_role}</span>
                    </div>
                    <div>
                      <span class="stat-label">Trigger</span>
                      <span class="mono">{integration.current_link.success_trigger}</span>
                    </div>
                    <div>
                      <span class="stat-label">Workflow File</span>
                      <span class="mono">{integration.current_link.workflow_file || "-"}</span>
                    </div>
                  </div>
                </div>
              {/if}

              {#if queueSummary.roles.length > 0}
                <div class="integration-block">
                  <span class="integration-title">Queue</span>
                  <div class="integration-stats compact">
                    <div>
                      <span class="stat-label">Claimable</span>
                      <span>{queueSummary.claimable}</span>
                    </div>
                    <div>
                      <span class="stat-label">Failed</span>
                      <span>{queueSummary.failed}</span>
                    </div>
                    <div>
                      <span class="stat-label">Stuck</span>
                      <span>{queueSummary.stuck}</span>
                    </div>
                    <div>
                      <span class="stat-label">Lease Risk</span>
                      <span>{queueSummary.nearExpiry}</span>
                    </div>
                  </div>
                </div>
              {/if}

              <div class="integration-actions">
                <button
                  class="btn integration-btn"
                  onclick={() => openBoilerRoute(orchestrationUiRoutes.workflows())}
                >
                  Workflows
                </button>
                <button
                  class="btn integration-btn"
                  onclick={() => openBoilerRoute(orchestrationUiRoutes.runs())}
                >
                  Runs
                </button>
              </div>

              <div class="integration-form">
                <label class="integration-field">
                  <span>Local tracker</span>
                  <select bind:value={selectedTracker} disabled={linkingIntegration}>
                    <option value="">Select tracker</option>
                    {#each trackerOptions as tracker}
                      <option value={tracker.name}>
                        {tracker.name} ({tracker.port}){tracker.running ? "" : " - stopped"}
                      </option>
                    {/each}
                  </select>
                </label>
                <label class="integration-field">
                  <span>Pipeline</span>
                  {#if selectedTrackerPipelines.length > 0}
                    <select bind:value={selectedPipeline} disabled={linkingIntegration}>
                      <option value="">Select pipeline</option>
                      {#each selectedTrackerPipelines as pipeline}
                        <option value={pipeline.id}>
                          {pipeline.name || pipeline.id} ({pipeline.id})
                        </option>
                      {/each}
                    </select>
                  {:else}
                    <input bind:value={selectedPipeline} placeholder="pipeline-id" />
                  {/if}
                </label>
                <label class="integration-field">
                  <span>Claim role</span>
                  {#if selectedPipelineRoles.length > 0}
                    <select bind:value={trackerClaimRole} disabled={linkingIntegration}>
                      {#each selectedPipelineRoles as role}
                        <option value={role}>{role}</option>
                      {/each}
                    </select>
                  {:else}
                    <input bind:value={trackerClaimRole} placeholder="coder" />
                  {/if}
                </label>
                <label class="integration-field">
                  <span>Success trigger</span>
                  {#if selectedPipelineTriggers.length > 0}
                    <select bind:value={trackerSuccessTrigger} disabled={linkingIntegration}>
                      {#each selectedPipelineTriggers as trigger}
                        <option value={trigger}>{trigger}</option>
                      {/each}
                    </select>
                  {:else}
                    <input bind:value={trackerSuccessTrigger} placeholder="complete" />
                  {/if}
                </label>
                <label class="integration-field">
                  <span>Concurrency</span>
                  <input bind:value={trackerConcurrency} inputmode="numeric" />
                </label>
                <button
                  class="btn integration-btn"
                  onclick={linkTracker}
                  disabled={linkingIntegration || !selectedTracker || !selectedPipeline.trim()}
                >
                  {linkingIntegration ? "Linking..." : "Link Tracker"}
                </button>
              </div>
            {:else}
              <div class="integration-block">
                <span class="integration-title">Tracker</span>
                <span class="mono">
                  {integration?.instance?.name || name}:{integration?.instance?.port || instance?.port || "-"}
                </span>
                {#if integration?.instance?.running === true}
                  <span class="integration-badge">Running</span>
                {:else if integration?.instance?.running === false}
                  <span class="integration-muted">Stopped</span>
                {/if}
              </div>

              <div class="integration-block">
                <span class="integration-title">Queue</span>
                {#if queueSummary.roles.length > 0}
                  <div class="integration-stats compact">
                    <div>
                      <span class="stat-label">Claimable</span>
                      <span>{queueSummary.claimable}</span>
                    </div>
                    <div>
                      <span class="stat-label">Failed</span>
                      <span>{queueSummary.failed}</span>
                    </div>
                    <div>
                      <span class="stat-label">Stuck</span>
                      <span>{queueSummary.stuck}</span>
                    </div>
                    <div>
                      <span class="stat-label">Lease Risk</span>
                      <span>{queueSummary.nearExpiry}</span>
                    </div>
                  </div>
                {:else}
                  <span class="integration-muted">Queue stats appear when the tracker is running.</span>
                {/if}
              </div>

              <div class="integration-actions">
                <button class="btn integration-btn" onclick={openTicketsStore}>
                  Store
                </button>
                <button
                  class="btn integration-btn"
                  onclick={() => refreshTicketsData(true)}
                  disabled={ticketsDataLoading || integration?.instance?.running !== true}
                >
                  {ticketsDataLoading ? "Refreshing..." : "Refresh"}
                </button>
              </div>

              {#if ticketsDataError}
                <span class="integration-error">{ticketsDataError}</span>
              {/if}
              {#if ticketsActionError}
                <span class="integration-error">{ticketsActionError}</span>
              {:else if ticketsActionMessage}
                <span class="integration-muted">{ticketsActionMessage}</span>
              {/if}

              <div class="integration-block">
                <span class="integration-title">Task Actions</span>
                <div class="integration-form">
                  <label class="integration-field">
                    <span>Pipeline</span>
                    {#if ticketsPipelines.length > 0}
                      <select bind:value={ticketTaskPipeline} disabled={ticketsDataLoading}>
                        {#each ticketsPipelines as pipeline}
                          <option value={pipelineId(pipeline)}>
                            {pipelineName(pipeline)} ({pipelineId(pipeline)})
                          </option>
                        {/each}
                      </select>
                    {:else}
                      <input bind:value={ticketTaskPipeline} placeholder="pipeline-id" />
                    {/if}
                  </label>
                  <label class="integration-field">
                    <span>Title</span>
                    <input bind:value={ticketTaskTitle} placeholder="Task title" />
                  </label>
                  <label class="integration-field">
                    <span>Priority</span>
                    <input bind:value={ticketTaskPriority} inputmode="numeric" />
                  </label>
                  <label class="integration-field wide">
                    <span>Description</span>
                    <textarea bind:value={ticketTaskDescription} rows="3"></textarea>
                  </label>
                  <button
                    class="btn integration-btn"
                    onclick={createTicketTask}
                    disabled={ticketsDataLoading || integration?.instance?.running !== true || !ticketTaskPipeline.trim() || !ticketTaskTitle.trim()}
                  >
                    Create Task
                  </button>
                </div>
              </div>

              <div class="integration-block">
                <span class="integration-title">Claim Next</span>
                <div class="integration-form">
                  <label class="integration-field">
                    <span>Agent</span>
                    <input bind:value={ticketClaimAgent} placeholder="nullhub" />
                  </label>
                  <label class="integration-field">
                    <span>Role</span>
                    {#if queueSummary.roles.length > 0}
                      <select bind:value={ticketClaimRole} disabled={ticketsDataLoading}>
                        {#each queueSummary.roles as role}
                          <option value={role.role}>
                            {role.role} ({role.claimable_count || 0})
                          </option>
                        {/each}
                      </select>
                    {:else}
                      <input bind:value={ticketClaimRole} placeholder="coder" />
                    {/if}
                  </label>
                  <label class="integration-field">
                    <span>Lease TTL ms</span>
                    <input bind:value={ticketClaimTtl} inputmode="numeric" />
                  </label>
                  <button
                    class="btn integration-btn"
                    onclick={claimTicketTask}
                    disabled={ticketsDataLoading || integration?.instance?.running !== true || !ticketClaimRole.trim()}
                  >
                    Claim Task
                  </button>
                </div>
                {#if claimedTicket?.task}
                  <span class="integration-muted">
                    {taskTitle(claimedTicket.task)} - <span class="mono">{claimedTicket.lease_id}</span>
                  </span>
                {/if}
              </div>

              {#if ticketsTasks.length > 0}
                <div class="integration-block">
                  <span class="integration-title">Recent Tasks</span>
                  <div class="integration-list">
                    {#each ticketsTasks.slice(0, 6) as task}
                      <div class="integration-list-item">
                        <div>
                          <span class="integration-title">{taskTitle(task)}</span>
                          <span class="integration-muted mono"> {task.id || ""}</span>
                        </div>
                        <span class="integration-muted"
                          >{task.stage || "-"} / {task.pipeline_id || "-"}</span
                        >
                      </div>
                    {/each}
                  </div>
                </div>
              {/if}

              {#if linkedBoilers.length > 0}
                <div class="integration-list">
                  {#each linkedBoilers as boiler}
                    <div class="integration-list-item">
                      <div>
                        <span class="integration-title">{boiler.name}</span>
                        <span class="integration-muted mono">:{boiler.port}</span>
                      </div>
                      {#if boiler.tracker}
                        <span class="integration-muted"
                          >{boiler.tracker.running_count || 0} running / {boiler.tracker.failed_count || 0} failed</span
                        >
                      {/if}
                    </div>
                  {/each}
                </div>
              {:else}
                <span class="integration-muted">No linked NullBoiler instances detected.</span>
              {/if}
            {/if}
          </div>
        {/if}
        {#if supportsUsage}
          <div class="info-card usage-card">
            <div class="usage-header">
              <span class="label">LLM Usage</span>
              <select class="usage-window" bind:value={usageWindow}>
                <option value="24h">24h</option>
                <option value="7d">7d</option>
                <option value="30d">30d</option>
                <option value="all">All</option>
              </select>
            </div>
            {#if usageLoading}
              <span class="usage-empty">Loading usage...</span>
            {:else if !usageData?.rows || usageData.rows.length === 0}
              <span class="usage-empty">No usage data for selected window.</span>
            {:else}
              <div class="usage-table-wrap">
                <table class="usage-table">
                  <thead>
                    <tr>
                      <th>Provider</th>
                      <th>Model</th>
                      <th>To provider (prompt)</th>
                      <th>From provider (completion)</th>
                      <th>Total</th>
                      <th>Requests</th>
                      <th>Last used</th>
                    </tr>
                  </thead>
                  <tbody>
                    {#each [...usageData.rows].sort((a, b) => (b.total_tokens || 0) - (a.total_tokens || 0)) as row}
                      <tr>
                        <td>{row.provider}</td>
                        <td class="mono">{row.model}</td>
                        <td>{formatTokens(row.prompt_tokens)}</td>
                        <td>{formatTokens(row.completion_tokens)}</td>
                        <td>{formatTokens(row.total_tokens)}</td>
                        <td>{row.requests || 0}</td>
                        <td>{formatLastUsed(row.last_used)}</td>
                      </tr>
                    {/each}
                  </tbody>
                </table>
              </div>
            {/if}
            {#if usageData?.totals}
              <div class="usage-total">
                Total: {formatTokens(usageData.totals.total_tokens)} tokens in {usageData.totals.requests || 0} request(s)
              </div>
            {/if}
          </div>
        {/if}
      </div>
    {:else if activeTab === "history"}
      {#key instanceRouteKey}
        <InstanceHistoryPanel {component} {name} active={activeTab === "history"} />
      {/key}
    {:else if activeTab === "memory"}
      {#key instanceRouteKey}
        <InstanceMemoryPanel {component} {name} active={activeTab === "memory"} />
      {/key}
    {:else if activeTab === "skills"}
      {#key instanceRouteKey}
        <InstanceSkillsPanel {component} {name} active={activeTab === "skills"} />
      {/key}
    {:else if activeTab === "tickets"}
      {#key instanceRouteKey}
        <NullTicketsPanel
          {component}
          {name}
          active={activeTab === "tickets"}
          running={integration?.instance?.running === true || instance?.status === "running"}
        />
      {/key}
    {:else if activeTab === "boiler"}
      {#key instanceRouteKey}
        <NullBoilerPanel
          {component}
          {name}
          active={activeTab === "boiler"}
          running={integration?.instance?.running === true || instance?.status === "running"}
        />
      {/key}
    {:else if activeTab === "config"}
      {#key instanceRouteKey}
        <ConfigEditor {component} {name} onAction={refresh} />
      {/key}
    {:else if activeTab === "logs"}
      {#key instanceRouteKey}
        <LogViewer {component} {name} />
      {/key}
    {:else if activeTab === "advanced"}
      <div class="advanced-panel">
        <div class="advanced-card">
          <h3>Standalone Launch</h3>
          {#if standaloneBinaryPath}
            <p>
              Run this instance without <code>nullhub</code>, reusing the same
              config, auth, data, and logs directory.
            </p>
            <div class="advanced-copy-row">
              <span class="advanced-copy-hint">
                {#if standaloneCopyState === "copied"}
                  Copied
                {:else if standaloneCopyState === "error"}
                  Copy failed
                {:else}
                  Click to copy
                {/if}
              </span>
            </div>
            <button
              type="button"
              class="advanced-code advanced-code-copy"
              onclick={() => void copyStandaloneLaunchScript()}
              onkeydown={handleStandaloneLaunchKeydown}
              aria-label="Copy standalone launch command"
            ><code>{standaloneLaunchScript}</code></button>
            <div class="advanced-meta">
              <div>
                <span class="advanced-label">Config</span>
                <code>{standaloneConfigPath}</code>
              </div>
              <div>
                <span class="advanced-label">Instance Home</span>
                <code>{standaloneHomePath}</code>
              </div>
              <div>
                <span class="advanced-label">Binary</span>
                <code>{standaloneBinaryPath}</code>
              </div>
            </div>
            <p class="advanced-note">
              If your `nullhub` root is custom, export <code>NULLHUB_HOME</code>
              before running the command.
            </p>
          {:else}
            <p>
              Standalone launch instructions are available after this instance has a versioned binary.
            </p>
          {/if}
        </div>
      </div>
    {:else if activeTab === "chat"}
      {#if !providerStatus.configured}
        <div class="chat-blocked">
          <div class="chat-blocked-icon">!</div>
          <div class="chat-blocked-title">LLM Provider Not Configured</div>
          <div class="chat-blocked-desc">
            No API key found for provider <code
              >{providerStatus.provider || "unknown"}</code
            >. Set up a provider API key in the
            <button class="link-btn" onclick={() => (activeTab = "config")}
              >Config</button
            > tab to use chat.
          </div>
          {#if providerStatus.model}
            <div class="chat-blocked-model">
              Model: <code
                >{providerStatus.provider}/{providerStatus.model}</code
              >
            </div>
          {/if}
        </div>
      {:else if !webPort}
        <div class="chat-unavailable">
          Web channel not configured for this instance.
        </div>
      {:else}
        <div class="chat-stack">
          {#if onboardingPending}
            <div class="chat-onboarding">
              <div class="chat-onboarding-title">Bootstrap In Progress</div>
              <div class="chat-onboarding-desc">
                This is the defining chat that makes the agent itself instead of a blank instance.
              </div>
              <div class="chat-onboarding-note">
                This chat auto-starts with <code>{onboardingStarterMessage}</code>. Then help it
                figure out its name, nature, vibe, emoji, and how it should address you.
              </div>
            </div>
          {/if}
          {#key instanceRouteKey}
            <ChatPanel
              port={webPort}
              moduleName={chatModuleName}
              moduleVersion={chatModuleVersion}
              instanceKey={instanceRouteKey}
              onboardingPending={onboardingPending}
              starterMessage={onboardingStarterMessage}
              onboardingMarker={onboardingMarker}
            />
          {/key}
        </div>
      {/if}
    {/if}
  </div>
</div>

<style>
  .instance-detail {
    padding: 2rem;
    max-width: 1200px;
    margin: 0 auto;
  }
  .detail-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    margin-bottom: 2rem;
    border-bottom: 1px solid color-mix(in srgb, var(--border) 50%, transparent);
    padding-bottom: 1rem;
  }
  .detail-header h1 {
    font-size: 2rem;
    font-weight: 700;
    margin-bottom: 0.5rem;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 2px;
    text-shadow: var(--text-glow);
  }
  .component-tag {
    padding: 0.25rem 0.5rem;
    background: color-mix(in srgb, var(--border) 20%, transparent);
    border: 1px solid var(--border);
    border-radius: 2px;
    font-family: var(--font-mono);
    font-size: 0.8125rem;
    color: var(--fg-dim);
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .actions {
    display: flex;
    gap: 0.75rem;
  }
  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    padding: 0.5rem 1rem;
    border: 1px solid var(--accent-dim);
    border-radius: 2px;
    background: var(--bg-surface);
    color: var(--accent);
    font-size: 0.8125rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1px;
    cursor: pointer;
    transition: all 0.2s ease;
    text-shadow: var(--text-glow);
    text-decoration: none;
  }
  .btn:hover {
    background: var(--bg-hover);
    border-color: var(--accent);
    box-shadow: 0 0 10px var(--border-glow);
    text-shadow: 0 0 8px var(--accent);
  }
  .btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    box-shadow: none;
    text-shadow: none;
  }
  .btn.danger {
    color: var(--error);
    border-color: color-mix(in srgb, var(--error) 50%, transparent);
    text-shadow: 0 0 5px var(--error);
  }
  .btn.danger:hover {
    background: color-mix(in srgb, var(--error) 15%, transparent);
    border-color: var(--error);
    box-shadow: 0 0 10px color-mix(in srgb, var(--error) 50%, transparent);
  }
  .tabs {
    display: flex;
    gap: 0;
    border-bottom: 1px solid var(--border);
    margin-bottom: 1.5rem;
  }
  .tabs button {
    padding: 0.75rem 1.5rem;
    background: none;
    border: none;
    border-bottom: 2px solid transparent;
    color: var(--fg-dim);
    font-size: 0.875rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1px;
    cursor: pointer;
    transition: all 0.2s ease;
  }
  .tabs button:hover {
    color: var(--accent);
    background: color-mix(in srgb, var(--accent) 5%, transparent);
  }
  .tabs button.active {
    color: var(--accent);
    border-bottom-color: var(--accent);
    background: color-mix(in srgb, var(--accent) 10%, transparent);
    text-shadow: var(--text-glow);
  }
  .tab-content {
    min-height: 400px;
  }
  .overview-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
    gap: 1.5rem;
  }
  .info-card {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    padding: 1.5rem;
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: 4px;
    backdrop-filter: blur(4px);
    transition: all 0.2s ease;
  }
  .info-card:hover {
    border-color: color-mix(in srgb, var(--accent) 50%, transparent);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
  }
  .usage-card {
    grid-column: 1 / -1;
  }
  .integration-card {
    grid-column: 1 / -1;
    gap: 1rem;
  }
  .integration-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }
  .integration-badge {
    padding: 0.2rem 0.5rem;
    border: 1px solid color-mix(in srgb, var(--success, #22c55e) 50%, transparent);
    color: var(--success, #22c55e);
    background: color-mix(in srgb, var(--success, #22c55e) 12%, transparent);
    border-radius: 2px;
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 1px;
    font-weight: 700;
  }
  .integration-block {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }
  .integration-title {
    font-size: 0.8125rem;
    color: var(--fg);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .integration-muted {
    color: var(--fg-dim);
    font-size: 0.8125rem;
  }
  .integration-error {
    color: var(--error);
    font-size: 0.8125rem;
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .integration-stats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
    gap: 0.75rem;
  }
  .integration-stats.compact {
    grid-template-columns: repeat(auto-fit, minmax(110px, 1fr));
  }
  .integration-stats div {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    padding: 0.75rem;
    border: 1px solid color-mix(in srgb, var(--border) 70%, transparent);
    background: color-mix(in srgb, var(--bg-surface) 80%, transparent);
    border-radius: 2px;
  }
  .stat-label {
    color: var(--accent-dim);
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .integration-form {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 0.75rem;
    align-items: end;
  }
  .integration-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75rem;
  }
  .integration-field {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
  }
  .integration-field.wide {
    grid-column: 1 / -1;
  }
  .integration-field span {
    color: var(--accent-dim);
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .integration-field select,
  .integration-field input,
  .integration-field textarea {
    padding: 0.6rem 0.7rem;
    border: 1px solid var(--border);
    border-radius: 2px;
    background: var(--bg-surface);
    color: var(--fg);
    font-family: var(--font-mono);
    font-size: 0.8rem;
  }
  .integration-field select:focus,
  .integration-field input:focus,
  .integration-field textarea:focus {
    outline: none;
    border-color: var(--accent);
  }
  .integration-field textarea {
    min-height: 84px;
    resize: vertical;
  }
  .integration-btn {
    min-height: 42px;
  }
  .integration-list {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }
  .integration-list-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
    padding: 0.85rem 1rem;
    border: 1px solid color-mix(in srgb, var(--border) 70%, transparent);
    background: color-mix(in srgb, var(--bg-surface) 80%, transparent);
    border-radius: 2px;
  }
  .usage-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }
  .usage-window {
    min-width: 90px;
    padding: 0.25rem 0.5rem;
    background: var(--bg-surface);
    color: var(--fg);
    border: 1px solid var(--border);
    border-radius: 2px;
    font-family: var(--font-mono);
    font-size: 0.75rem;
  }
  .usage-window:focus {
    outline: none;
    border-color: var(--accent);
  }
  .usage-table-wrap {
    overflow-x: auto;
  }
  .usage-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.8125rem;
  }
  .usage-table th,
  .usage-table td {
    text-align: left;
    padding: 0.5rem 0.625rem;
    border-bottom: 1px solid color-mix(in srgb, var(--border) 70%, transparent);
    white-space: nowrap;
  }
  .usage-table th {
    color: var(--accent-dim);
    text-transform: uppercase;
    letter-spacing: 1px;
    font-size: 0.6875rem;
  }
  .usage-table td {
    color: var(--fg);
  }
  .usage-empty {
    color: var(--fg-dim);
    font-size: 0.8125rem;
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .usage-total {
    margin-top: 0.5rem;
    color: var(--fg-dim);
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .label {
    font-size: 0.75rem;
    color: var(--accent-dim);
    text-transform: uppercase;
    letter-spacing: 1px;
    font-weight: 700;
  }
  .mode-value {
    text-transform: uppercase;
    letter-spacing: 1px;
    font-weight: 700;
    font-size: 0.85rem;
    color: var(--accent);
    text-shadow: var(--text-glow);
  }
  .toggle-btn {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    background: none;
    border: none;
    color: var(--fg);
    font-size: 0.875rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1px;
    cursor: pointer;
    padding: 0;
  }
  .toggle-btn:hover:not(:disabled) {
    background: none;
    border-color: transparent;
    box-shadow: none;
    text-shadow: none;
  }
  .toggle-track {
    position: relative;
    width: 36px;
    height: 20px;
    background: var(--bg-surface);
    border: none;
    border-radius: 2px;
    transition: all 0.2s ease;
    box-shadow: inset 0 2px 4px rgba(0, 0, 0, 0.5);
  }
  .toggle-thumb {
    position: absolute;
    top: 2px;
    left: 2px;
    width: 14px;
    height: 14px;
    background: var(--fg-dim);
    border-radius: 2px;
    transition: all 0.2s ease;
  }
  .toggle-btn.on .toggle-track {
    background: color-mix(in srgb, var(--accent) 20%, transparent);
    box-shadow: inset 0 0 8px color-mix(in srgb, var(--accent) 30%, transparent);
  }
  .toggle-btn.on .toggle-thumb {
    transform: translateX(16px);
    background: var(--accent);
    box-shadow: 0 0 5px var(--border-glow);
  }
  .mono {
    font-family: var(--font-mono);
    color: var(--accent);
    text-shadow: var(--text-glow);
    font-size: 0.875rem;
  }
  .chat-unavailable {
    color: var(--fg-dim);
    text-align: center;
    padding: 4rem;
    font-size: 1rem;
    text-transform: uppercase;
    letter-spacing: 1px;
    border: 1px dashed var(--border);
    background: var(--bg-surface);
    border-radius: 4px;
  }
  .tab-warn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 16px;
    height: 16px;
    border-radius: 2px;
    background: color-mix(in srgb, var(--warning, #f59e0b) 20%, transparent);
    color: var(--warning, #f59e0b);
    border: 1px solid var(--warning, #f59e0b);
    font-size: 0.7rem;
    font-weight: 700;
    margin-left: 0.5rem;
    vertical-align: middle;
    box-shadow: 0 0 5px var(--warning, #f59e0b);
  }
  .disabled-tab {
    opacity: 0.5;
  }
  .advanced-panel {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }
  .advanced-card {
    padding: 1.25rem;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    background: color-mix(in srgb, var(--bg-surface) 88%, transparent);
  }
  .advanced-card h3 {
    margin: 0 0 0.75rem;
    color: var(--accent);
    font-size: 1rem;
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .advanced-card p {
    margin: 0;
    color: var(--fg-dim);
    line-height: 1.6;
  }
  .advanced-code {
    margin: 1rem 0;
    padding: 1rem;
    border: 1px solid color-mix(in srgb, var(--border) 80%, transparent);
    border-radius: var(--radius);
    background: color-mix(in srgb, var(--bg) 55%, var(--bg-surface) 45%);
    overflow-x: auto;
  }
  .advanced-copy-row {
    display: flex;
    justify-content: flex-end;
    margin-top: 1rem;
    margin-bottom: -0.5rem;
  }
  .advanced-copy-hint {
    color: var(--accent-dim);
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 1px;
    font-weight: 700;
  }
  .advanced-code-copy {
    display: block;
    width: 100%;
    text-align: left;
    cursor: copy;
    transition: border-color 0.2s ease, box-shadow 0.2s ease, background 0.2s ease;
  }
  .advanced-code-copy:hover,
  .advanced-code-copy:focus {
    border-color: var(--accent);
    box-shadow: 0 0 10px var(--border-glow);
    background: color-mix(in srgb, var(--bg) 48%, var(--bg-surface) 52%);
  }
  .advanced-code code {
    font-family: var(--font-mono);
    font-size: 0.9rem;
    color: var(--fg);
    white-space: pre;
  }
  .advanced-meta {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: 0.75rem;
  }
  .advanced-meta div {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    padding: 0.85rem 0.9rem;
    border: 1px solid color-mix(in srgb, var(--border) 70%, transparent);
    border-radius: var(--radius);
    background: color-mix(in srgb, var(--bg-surface) 82%, transparent);
  }
  .advanced-label {
    color: var(--accent-dim);
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 1px;
    font-weight: 700;
  }
  .advanced-note {
    margin-top: 0.9rem !important;
    font-size: 0.82rem;
  }
  .chat-blocked {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 4rem 2rem;
    gap: 1rem;
    text-align: center;
    border: 1px dashed var(--warning, #f59e0b);
    background: color-mix(in srgb, var(--warning, #f59e0b) 5%, transparent);
    border-radius: 4px;
  }
  .chat-blocked-icon {
    width: 64px;
    height: 64px;
    border-radius: 4px;
    background: color-mix(in srgb, var(--warning, #f59e0b) 15%, transparent);
    border: 1px solid var(--warning, #f59e0b);
    color: var(--warning, #f59e0b);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 2rem;
    font-weight: 700;
    text-shadow: 0 0 8px var(--warning, #f59e0b);
    box-shadow: 0 0 15px
      color-mix(in srgb, var(--warning, #f59e0b) 30%, transparent);
  }
  .chat-blocked-title {
    font-size: 1.25rem;
    font-weight: 700;
    color: var(--warning, #f59e0b);
    text-transform: uppercase;
    letter-spacing: 1px;
    text-shadow: 0 0 5px var(--warning, #f59e0b);
  }
  .chat-blocked-desc {
    color: var(--fg);
    font-size: 0.9rem;
    max-width: 450px;
    line-height: 1.6;
  }
  .chat-blocked-desc code {
    padding: 0.125rem 0.375rem;
    background: color-mix(in srgb, var(--warning, #f59e0b) 10%, transparent);
    border: 1px solid
      color-mix(in srgb, var(--warning, #f59e0b) 30%, transparent);
    border-radius: 2px;
    font-family: var(--font-mono);
    font-size: 0.8125rem;
    color: var(--warning, #f59e0b);
  }
  .chat-blocked-model {
    color: var(--fg-dim);
    font-size: 0.8125rem;
    margin-top: 0.5rem;
  }
  .chat-blocked-model code {
    padding: 0.125rem 0.375rem;
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: 2px;
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--accent);
  }
  .chat-stack {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }
  .chat-onboarding {
    border: 1px solid color-mix(in srgb, var(--accent) 50%, transparent);
    background:
      linear-gradient(
        135deg,
        color-mix(in srgb, var(--accent) 8%, transparent),
        transparent 55%
      ),
      var(--bg-surface);
    padding: 1rem 1.125rem;
    border-radius: 4px;
    box-shadow: inset 0 0 16px color-mix(in srgb, var(--accent) 8%, transparent);
  }
  .chat-onboarding-title {
    font-size: 0.85rem;
    font-weight: 700;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: var(--accent);
    margin-bottom: 0.35rem;
  }
  .chat-onboarding-desc,
  .chat-onboarding-note {
    color: var(--fg-dim);
    font-family: var(--font-mono);
    font-size: 0.85rem;
    line-height: 1.6;
  }
  .chat-onboarding-note {
    margin-top: 0.55rem;
  }
  .chat-onboarding code {
    color: var(--accent);
  }
  .link-btn {
    background: none;
    border: none;
    color: var(--warning, #f59e0b);
    cursor: pointer;
    font-size: inherit;
    text-decoration: underline;
    font-weight: 700;
    padding: 0;
  }
  .link-btn:hover {
    text-shadow: 0 0 5px var(--warning, #f59e0b);
  }
  .card-warn {
    border-color: color-mix(in srgb, var(--warning, #f59e0b) 40%, transparent);
    background: color-mix(in srgb, var(--warning, #f59e0b) 5%, transparent);
  }
  .provider-status {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-family: var(--font-mono);
    font-size: 0.875rem;
  }
  .status-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
  }
  .status-dot.ok {
    background: var(--success, #22c55e);
    box-shadow: 0 0 8px var(--success, #22c55e);
  }
  .status-dot.err {
    background: var(--warning, #f59e0b);
    box-shadow: 0 0 8px var(--warning, #f59e0b);
  }
  .provider-hint {
    font-size: 0.75rem;
    color: var(--warning, #f59e0b);
    text-transform: uppercase;
    letter-spacing: 1px;
    font-weight: 700;
    margin-top: 0.25rem;
  }
  @media (max-width: 700px) {
    .integration-list-item {
      flex-direction: column;
      align-items: flex-start;
    }
    .integration-form {
      grid-template-columns: 1fr;
    }
  }
</style>
