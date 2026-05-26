<script lang="ts">
  import { page } from "$app/stores";
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";
  import { nullboilerUiRoutes } from "$lib/nullboiler/routes";
  import { nullticketsUiRoutes } from "$lib/nulltickets/routes";
  import { routePath } from "$lib/nullstack/path";
  import {
    BOILER_INSTANCE_CHANGE_EVENT,
    TICKETS_INSTANCE_CHANGE_EVENT,
  } from "$lib/nullstack/backendSelection";

  let instances = $state<Record<string, any>>({});
  let installedComponents = $state<Record<string, any>>({});
  let currentPath = $derived($page.url.pathname);
  let showNullBoiler = $derived(Boolean(installedComponents["nullboiler"]?.installed));
  let showNullTickets = $derived(Boolean(installedComponents["nulltickets"]?.installed));
  let showNullWatch = $derived(Boolean(installedComponents["nullwatch"]?.installed));
  let boilerSelectionVersion = $state(0);
  let ticketsSelectionVersion = $state(0);
  let nullclawHref = $derived.by(() => componentEntryHref("nullclaw"));
  let nullboilerDashboardHref = $derived.by(() => {
    boilerSelectionVersion;
    return showNullBoiler ? nullboilerUiRoutes.dashboard() : "/install/nullboiler";
  });
  let nullboilerWorkflowsHref = $derived.by(() => {
    boilerSelectionVersion;
    return nullboilerUiRoutes.workflows();
  });
  let nullboilerRunsHref = $derived.by(() => {
    boilerSelectionVersion;
    return nullboilerUiRoutes.runs();
  });
  let nullticketsHref = $derived.by(() => {
    ticketsSelectionVersion;
    return showNullTickets ? nullticketsUiRoutes.store() : "/install/nulltickets";
  });
  let nullwatchHref = $derived(showNullWatch ? "/nullwatch" : "/install/nullwatch");

  function componentEntryHref(component: string): string {
    const names = Object.keys(instances[component] || {}).sort();
    return names[0] ? `/instances/${component}/${encodeURIComponent(names[0])}` : `/install/${component}`;
  }

  async function loadSidebarState() {
    const [statusResult, componentsResult] = await Promise.allSettled([
      api.getStatus(),
      api.getComponents(),
    ]);

    if (statusResult.status === "fulfilled") {
      instances = statusResult.value.instances || {};
    }

    if (componentsResult.status === "fulfilled") {
      installedComponents = Object.fromEntries(
        (componentsResult.value.components || []).map((component: any) => [component.name, component]),
      );
    }
  }

  onMount(() => {
    void loadSidebarState();
    const interval = setInterval(loadSidebarState, 5000);
    const refreshBoilerLinks = () => {
      boilerSelectionVersion += 1;
    };
    const refreshTicketsLinks = () => {
      ticketsSelectionVersion += 1;
    };
    globalThis.addEventListener?.(BOILER_INSTANCE_CHANGE_EVENT, refreshBoilerLinks);
    globalThis.addEventListener?.(TICKETS_INSTANCE_CHANGE_EVENT, refreshTicketsLinks);
    return () => {
      clearInterval(interval);
      globalThis.removeEventListener?.(BOILER_INSTANCE_CHANGE_EVENT, refreshBoilerLinks);
      globalThis.removeEventListener?.(TICKETS_INSTANCE_CHANGE_EVENT, refreshTicketsLinks);
    };
  });
</script>

<nav class="sidebar">
  <a href="/" class="logo" aria-label="Go to NullHub home">
    <h2>NullHub</h2>
  </a>

  <div class="nav-section">
    <a href="/" class:active={currentPath === "/"}>System Status</a>
    <a href="/dashboard" class:active={currentPath === "/dashboard"}>Dashboard</a>
    <a href="/install" class:active={currentPath === "/install"}
      >Install Component</a
    >
  </div>

  <div class="nav-section">
    <h3>Stack</h3>
    <a href={nullclawHref} class:active={currentPath.startsWith("/instances/nullclaw/") || currentPath === "/install/nullclaw"}>NullClaw</a>
    <a href={nullboilerDashboardHref} class:active={currentPath.startsWith("/nullboiler") || currentPath === "/install/nullboiler"}>NullBoiler</a>
    {#if showNullBoiler}
      <a href={nullboilerWorkflowsHref} class:active={currentPath.startsWith(routePath(nullboilerWorkflowsHref))}>Workflows</a>
      <a href={nullboilerRunsHref} class:active={currentPath.startsWith(routePath(nullboilerRunsHref))}>Runs</a>
    {/if}
    <a href={nullticketsHref} class:active={currentPath.startsWith("/nulltickets") || currentPath === "/install/nulltickets"}>NullTickets</a>
    <a href={nullwatchHref} class:active={currentPath.startsWith("/nullwatch") || currentPath === "/install/nullwatch"}>NullWatch</a>
  </div>

  <div class="nav-section">
    <h3>Instances</h3>
    {#each Object.entries(instances) as [component, items]}
      <div class="component-group">
        <span class="component-name">{component}</span>
        {#each Object.entries(items as Record<string, any>) as [name, info]}
          <a
            href="/instances/{component}/{name}"
            class:active={currentPath === `/instances/${component}/${name}`}
          >
            <span class="status-dot" class:running={info.status === "running"}
            ></span>
            {name}
          </a>
        {/each}
      </div>
    {/each}
  </div>

  <div class="nav-section">
    <a href="/providers" class:active={currentPath === "/providers"}>Providers</a>
  </div>

  <div class="nav-section">
    <a href="/channels" class:active={currentPath === "/channels"}>Channels</a>
  </div>

  <div class="nav-section">
    <a href="/mission-control" class:active={currentPath.startsWith("/mission-control")}>Mission Control</a>
  </div>

  <div class="nav-bottom">
    <a href="/report" class:active={currentPath === "/report"}>Report Issue</a>
    <a href="/settings" class:active={currentPath === "/settings"}>Settings</a>
  </div>
</nav>

<style>
  .sidebar {
    width: 250px;
    min-width: 250px;
    height: 100vh;
    background: var(--bg-surface);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    overflow-y: auto;
    backdrop-filter: blur(4px);
    z-index: 20;
  }

  .logo {
    display: block;
    padding: 1.5rem 1.25rem;
    border-bottom: 1px solid var(--border);
    text-align: center;
    color: inherit;
    transition: background 0.2s ease, box-shadow 0.2s ease;
  }

  .logo:hover,
  .logo:focus-visible {
    text-decoration: none;
    background: var(--bg-hover);
    box-shadow: inset 0 -1px 0 var(--accent-dim);
  }

  .logo h2 {
    font-size: 1.5rem;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 2px;
    text-shadow: var(--text-glow);
    text-transform: uppercase;
  }

  .nav-section {
    padding: 1rem 0;
    border-bottom: 1px solid var(--border);
  }

  .nav-section h3 {
    font-size: 0.75rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 2px;
    color: var(--accent-dim);
    padding: 0.5rem 1.25rem;
    text-shadow: 0 0 2px var(--accent-dim);
  }

  .nav-section a {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.625rem 1.25rem;
    color: var(--fg-dim);
    font-size: 0.875rem;
    text-transform: uppercase;
    letter-spacing: 1px;
    transition: background-color 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease, color 0.2s ease, transform 0.2s ease, text-shadow 0.2s ease;
    border-left: 3px solid transparent;
  }

  .nav-section a:hover {
    text-decoration: none;
    background: var(--bg-hover);
    color: var(--fg);
    border-left-color: var(--accent-dim);
    text-shadow: var(--text-glow);
  }

  .nav-section a.active {
    background: color-mix(in srgb, var(--accent) 15%, transparent);
    color: var(--accent);
    border-left: 3px solid var(--accent);
    text-shadow: var(--text-glow);
    box-shadow: inset 20px 0 20px -20px var(--accent);
  }

  .component-group {
    margin-bottom: 0.5rem;
  }

  .component-name {
    display: block;
    font-size: 0.75rem;
    font-weight: 700;
    color: var(--fg-dim);
    padding: 0.375rem 1.25rem 0.125rem;
    text-transform: uppercase;
    letter-spacing: 1px;
    opacity: 0.7;
  }

  .component-group a {
    padding-left: 1.75rem;
    font-size: 0.8rem;
  }

  .status-dot {
    display: inline-block;
    width: 6px;
    height: 6px;
    border-radius: var(--radius);
    background: var(--error);
    box-shadow: 0 0 5px var(--error);
    flex-shrink: 0;
  }

  .status-dot.running {
    background: var(--success);
    box-shadow: 0 0 10px var(--success);
  }

  .nav-bottom {
    margin-top: auto;
    padding: 1rem 0;
    border-top: 1px solid var(--border);
  }

  .nav-bottom a {
    display: block;
    padding: 0.75rem 1.25rem;
    color: var(--fg-dim);
    font-size: 0.875rem;
    text-transform: uppercase;
    letter-spacing: 1px;
    transition: background-color 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease, color 0.2s ease, transform 0.2s ease, text-shadow 0.2s ease;
    border-left: 3px solid transparent;
  }

  .nav-bottom a:hover {
    text-decoration: none;
    background: var(--bg-hover);
    color: var(--fg);
    border-left-color: var(--accent-dim);
    text-shadow: var(--text-glow);
  }

  .nav-bottom a.active {
    background: color-mix(in srgb, var(--accent) 15%, transparent);
    color: var(--accent);
    border-left: 3px solid var(--accent);
    text-shadow: var(--text-glow);
    box-shadow: inset 20px 0 20px -20px var(--accent);
  }
</style>
