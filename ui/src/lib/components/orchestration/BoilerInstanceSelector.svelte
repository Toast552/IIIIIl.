<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";
  import {
    getSelectedBoilerInstance,
    setSelectedBoilerInstance,
  } from "$lib/orchestration/backendSelection";

  type BoilerOption = {
    name: string;
    status: string;
  };

  let boilers = $state<BoilerOption[]>([]);
  let selected = $state("");
  let loading = $state(true);

  onMount(() => {
    selected = getSelectedBoilerInstance();
    void loadBoilers();
  });

  async function loadBoilers() {
    loading = true;
    try {
      const status = await api.getStatus();
      const instances = status?.instances?.nullboiler || {};
      boilers = Object.entries(instances).map(([name, info]: [string, any]) => ({
        name,
        status: info?.status || "stopped",
      }));
      if (selected && !boilers.some((boiler) => boiler.name === selected)) {
        selected = "";
        setSelectedBoilerInstance("");
      }
    } catch {
      boilers = [];
    } finally {
      loading = false;
    }
  }

  function handleChange(event: Event) {
    selected = (event.currentTarget as HTMLSelectElement).value;
    setSelectedBoilerInstance(selected);
    window.location.reload();
  }
</script>

{#if boilers.length > 0}
  <label class="boiler-selector" for="boiler-instance-select">
    <span>NullBoiler</span>
    <select
      id="boiler-instance-select"
      value={selected}
      onchange={handleChange}
      disabled={loading}
    >
      <option value="">Auto</option>
      {#each boilers as boiler}
        <option value={boiler.name}>
          {boiler.name}{boiler.status ? ` (${boiler.status})` : ""}
        </option>
      {/each}
    </select>
  </label>
{/if}

<style>
  .boiler-selector {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--fg-dim);
    font-size: 0.75rem;
    font-weight: 700;
    letter-spacing: 1px;
    text-transform: uppercase;
  }

  .boiler-selector select {
    min-width: 11rem;
    height: 2.25rem;
    padding: 0 0.625rem;
    background: var(--bg-surface);
    color: var(--fg);
    border: 1px solid var(--border);
    border-radius: 4px;
    font-size: 0.8125rem;
    font-family: var(--font-mono);
  }

  .boiler-selector select:focus {
    outline: none;
    border-color: var(--accent);
    box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 20%, transparent);
  }
</style>
