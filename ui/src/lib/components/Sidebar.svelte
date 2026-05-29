<script lang="ts">
  import { page } from "$app/stores";
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";
  import { componentInstancesRoute, instanceRoute } from "$lib/nullstack/path";

  let instances = $state<Record<string, any>>({});
  let currentPath = $derived($page.url.pathname);

  function componentHeaderHref(component: string): string {
    return componentInstancesRoute(component);
  }

  function componentHeaderActive(component: string): boolean {
    const root = componentInstancesRoute(component);
    if (currentPath === root || currentPath.startsWith(`${root}/`)) return true;
    if (component === "nullboiler") return currentPath.startsWith("/nullboiler");
    if (component === "nulltickets") return currentPath.startsWith("/nulltickets");
    if (component === "nullwatch") return currentPath.startsWith("/nullwatch");
    return false;
  }

  async function loadSidebarState() {
    try {
      const status = await api.getStatus();
      instances = status.instances || {};
    } catch (e) {
      console.error(e);
    }
  }

  onMount(() => {
    void loadSidebarState();
    const interval = setInterval(loadSidebarState, 5000);
    return () => {
      clearInterval(interval);
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
    <h3>Instances</h3>
    {#each Object.entries(instances) as [component, items]}
      <div class="component-group">
        <a
          class="component-name"
          href={componentHeaderHref(component)}
          class:active={componentHeaderActive(component)}
        >{component}</a>
        {#each Object.entries(items as Record<string, any>) as [name, info]}
          <a
            class="instance-link"
            href={instanceRoute(component, name)}
            class:active={currentPath === instanceRoute(component, name)}
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

  .component-group .component-name {
    display: flex;
    align-items: center;
    font-size: 0.75rem;
    font-weight: 700;
    color: var(--fg-dim);
    padding: 0.5rem 1.25rem 0.35rem;
    text-transform: uppercase;
    letter-spacing: 1px;
  }

  .component-group a {
    padding-left: 1.75rem;
    font-size: 0.8rem;
  }

  .component-group a.component-name {
    padding-left: 1.25rem;
    font-size: 0.75rem;
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
