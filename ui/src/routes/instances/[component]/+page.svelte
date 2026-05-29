<script lang="ts">
  import { page } from "$app/stores";
  import { onDestroy, onMount } from "svelte";
  import InstanceCard from "$lib/components/InstanceCard.svelte";
  import { api } from "$lib/api/client";
  import { nullboilerUiRoutes } from "$lib/nullboiler/routes";
  import { nullticketsUiRoutes } from "$lib/nulltickets/routes";
  import { encodePathSegment } from "$lib/nullstack/path";

  type ComponentAction = {
    label: string;
    href: string;
  };

  let component = $derived($page.params.component);
  let status = $state<any>(null);
  let error = $state<string | null>(null);
  let interval: ReturnType<typeof setInterval>;

  let componentInstances = $derived((status?.instances?.[component] || {}) as Record<string, any>);
  let instanceEntries = $derived(
    Object.entries(componentInstances).sort(([a], [b]) => a.localeCompare(b)),
  );
  let displayName = $derived(displayNameForComponent(component));
  let installHref = $derived(`/install/${encodePathSegment(component)}`);
  let runningCount = $derived(
    instanceEntries.filter(([, info]) => info?.status === "running").length,
  );
  let stoppedCount = $derived(Math.max(instanceEntries.length - runningCount, 0));
  let actions = $derived(componentActions(component));

  async function refresh() {
    try {
      status = await api.getStatus();
      error = null;
    } catch (e) {
      error = (e as Error).message;
    }
  }

  function displayNameForComponent(value: string): string {
    const names: Record<string, string> = {
      nullclaw: "NullClaw",
      nullboiler: "NullBoiler",
      nulltickets: "NullTickets",
      nullwatch: "NullWatch",
    };
    return names[value] || value;
  }

  function componentActions(value: string): ComponentAction[] {
    if (value === "nullboiler") {
      return [
        { label: "Dashboard", href: nullboilerUiRoutes.dashboard() },
        { label: "Workflows", href: nullboilerUiRoutes.workflows() },
        { label: "Runs", href: nullboilerUiRoutes.runs() },
      ];
    }
    if (value === "nulltickets") {
      return [{ label: "Store", href: nullticketsUiRoutes.store() }];
    }
    if (value === "nullwatch") {
      return [{ label: "Flight Recorder", href: "/nullwatch" }];
    }
    return [];
  }

  onMount(() => {
    void refresh();
    interval = setInterval(refresh, 5000);
  });

  onDestroy(() => clearInterval(interval));
</script>

<div class="component-page">
  <div class="header">
    <div>
      <h1>{displayName}</h1>
      <p class="subtitle">{instanceEntries.length} installed instances</p>
    </div>
    <div class="header-actions">
      {#each actions as action}
        <a href={action.href} class="action-btn">{action.label}</a>
      {/each}
      <a href={installHref} class="action-btn">Install Instance</a>
    </div>
  </div>

  {#if error}
    <div class="error-banner">ERR: {error}</div>
  {/if}

  <div class="stats">
    <div class="stat">
      <span class="stat-label">Running</span>
      <span class="stat-value running">{runningCount}</span>
    </div>
    <div class="stat">
      <span class="stat-label">Stopped</span>
      <span class="stat-value stopped">{stoppedCount}</span>
    </div>
    <div class="stat">
      <span class="stat-label">Total</span>
      <span class="stat-value">{instanceEntries.length}</span>
    </div>
  </div>

  {#if status}
    {#if instanceEntries.length > 0}
      <div class="instance-grid">
        {#each instanceEntries as [name, info]}
          <InstanceCard
            {component}
            {name}
            version={info.version}
            status={info.status || "stopped"}
            autoStart={info.auto_start}
            port={info.port || 0}
            onAction={refresh}
          />
        {/each}
      </div>
    {:else}
      <div class="empty-state">
        <p>> No {displayName} instances installed.</p>
        <a href={installHref} class="btn">Install {displayName}</a>
      </div>
    {/if}
  {/if}
</div>

<style>
  .component-page {
    padding: 2rem;
    max-width: 1200px;
    margin: 0 auto;
  }

  .header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 1rem;
    margin-bottom: 2rem;
    padding-bottom: 1rem;
    border-bottom: 1px solid var(--border);
  }

  h1 {
    font-size: 1.75rem;
    font-weight: 700;
    text-shadow: var(--text-glow);
    text-transform: uppercase;
    letter-spacing: 2px;
  }

  .subtitle {
    margin-top: 0.35rem;
    color: var(--fg-dim);
    font-family: var(--font-mono);
    font-size: 0.875rem;
  }

  .header-actions {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    flex-wrap: wrap;
    gap: 0.75rem;
  }

  .action-btn,
  .empty-state .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-height: 2.35rem;
    padding: 0.5rem 1rem;
    background: var(--bg-surface);
    color: var(--accent);
    border: 1px solid var(--accent-dim);
    border-radius: var(--radius);
    font-size: 0.8125rem;
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 1px;
    transition: background-color 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease, color 0.2s ease, transform 0.2s ease, text-shadow 0.2s ease;
    text-shadow: var(--text-glow);
  }

  .action-btn:hover,
  .empty-state .btn:hover {
    text-decoration: none;
    background: var(--bg-hover);
    border-color: var(--accent);
    box-shadow: 0 0 10px var(--border-glow);
    text-shadow: 0 0 8px var(--accent);
  }

  .error-banner {
    padding: 0.75rem 1rem;
    background: rgba(255, 0, 0, 0.1);
    color: var(--error);
    border: 1px solid var(--error);
    border-radius: var(--radius);
    margin-bottom: 1.5rem;
    font-size: 0.875rem;
    font-weight: bold;
    text-shadow: 0 0 5px var(--error);
    box-shadow: 0 0 10px rgba(255, 0, 0, 0.2);
    animation: glitch 3s infinite;
  }

  .stats {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 1rem;
    margin-bottom: 1.5rem;
  }

  .stat {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
    padding: 1rem;
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: 4px;
  }

  .stat-label {
    color: var(--fg-dim);
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 1px;
  }

  .stat-value {
    color: var(--accent);
    font-family: var(--font-mono);
    font-size: 1.5rem;
    font-weight: 700;
    text-shadow: var(--text-glow);
  }

  .stat-value.running {
    color: var(--success);
    text-shadow: 0 0 8px var(--success);
  }

  .stat-value.stopped {
    color: var(--fg-dim);
    text-shadow: none;
  }

  .instance-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: 1.5rem;
  }

  .empty-state {
    text-align: center;
    padding: 4rem 2rem;
    color: var(--fg-dim);
    border: 1px dashed var(--border);
    background: var(--bg-surface);
    border-radius: var(--radius);
  }

  :global(body.theme-8bit-lobster) .empty-state,
  :global(body.theme-8bit-lobster-light) .empty-state {
    border-style: solid;
  }

  .empty-state p {
    margin-bottom: 1.5rem;
    font-size: 1.125rem;
    font-family: var(--font-mono);
  }

  @media (max-width: 760px) {
    .component-page {
      padding: 1rem;
    }

    .header {
      flex-direction: column;
      align-items: stretch;
    }

    .header-actions {
      justify-content: flex-start;
    }

    .stats {
      grid-template-columns: 1fr;
    }

    .instance-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
