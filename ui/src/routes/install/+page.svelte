<script lang="ts">
  import { afterNavigate } from "$app/navigation";
  import ComponentCard from "$lib/components/ComponentCard.svelte";
  import { api } from "$lib/api/client";

  let components = $state<any[]>([]);

  async function loadPageData() {
    try {
      const data = await api.getComponents();
      components = data.components || [];
    } catch (e) {
      console.error(e);
    }
  }

  afterNavigate(loadPageData);
</script>

<div class="install-page">
  <div class="page-header">
    <div>
      <h1>Install Component</h1>
      <p class="subtitle">Choose a component to install</p>
    </div>
  </div>

  <div class="catalog-grid">
    {#each components as comp}
      <ComponentCard
        name={comp.name}
        displayName={comp.display_name}
        description={comp.description}
        alpha={Boolean(comp.alpha)}
        stage={comp.stage || ""}
        installable={comp.installable !== false}
        installed={comp.instance_count > 0}
        instanceCount={comp.instance_count}
      />
    {/each}
  </div>
</div>

<style>
  .install-page {
    max-width: 900px;
  }
  .page-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 1rem;
    margin-bottom: 2rem;
  }
  h1 {
    font-size: 1.75rem;
    font-weight: 700;
    margin-bottom: 0.5rem;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 2px;
    text-shadow: var(--text-glow);
  }
  .subtitle {
    font-size: 0.875rem;
    color: var(--fg-dim);
    margin-bottom: 2rem;
    font-family: var(--font-mono);
  }
  .catalog-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: 1.5rem;
  }
  @media (max-width: 640px) {
    .page-header {
      flex-direction: column;
    }
  }
</style>
