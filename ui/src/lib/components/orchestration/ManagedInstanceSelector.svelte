<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";

  type InstanceOption = {
    name: string;
    status: string;
    port?: number;
  };

  let {
    component,
    label,
    getSelected,
    setSelected,
    onChange = () => {},
  } = $props<{
    component: string;
    label: string;
    getSelected: () => string;
    setSelected: (name: string) => void;
    onChange?: (name: string) => void;
  }>();

  let instances = $state<InstanceOption[]>([]);
  let selected = $state("");
  let loading = $state(true);

  onMount(() => {
    selected = getSelected();
    void loadInstances();
  });

  async function loadInstances() {
    loading = true;
    try {
      const status = await api.getStatus();
      const managedInstances = status?.instances?.[component] || {};
      instances = Object.entries(managedInstances).map(([name, info]: [string, any]) => ({
        name,
        status: info?.status || "stopped",
        port: info?.port,
      }));
      if (selected && !instances.some((instance) => instance.name === selected)) {
        selected = "";
        setSelected("");
        onChange("");
      }
    } catch {
      instances = [];
    } finally {
      loading = false;
    }
  }

  function handleChange(event: Event) {
    selected = (event.currentTarget as HTMLSelectElement).value;
    setSelected(selected);
    onChange(selected);
  }

  function optionLabel(instance: InstanceOption): string {
    const port = instance.port ? ` :${instance.port}` : "";
    const status = instance.status ? ` (${instance.status})` : "";
    return `${instance.name}${port}${status}`;
  }
</script>

{#if instances.length > 0}
  <label class="instance-selector" for={`${component}-instance-select`}>
    <span>{label}</span>
    <select
      id={`${component}-instance-select`}
      value={selected}
      onchange={handleChange}
      disabled={loading}
    >
      <option value="">Auto</option>
      {#each instances as instance}
        <option value={instance.name}>{optionLabel(instance)}</option>
      {/each}
    </select>
  </label>
{/if}

<style>
  .instance-selector {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--fg-dim);
    font-size: 0.75rem;
    font-weight: 700;
    letter-spacing: 1px;
    text-transform: uppercase;
  }

  .instance-selector select {
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

  .instance-selector select:focus {
    outline: none;
    border-color: var(--accent);
    box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 20%, transparent);
  }
</style>
