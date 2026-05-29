<script lang="ts">
  import { afterNavigate } from "$app/navigation";
  import AddExistingDialog from "$lib/components/AddExistingDialog.svelte";
  import ComponentCard from "$lib/components/ComponentCard.svelte";
  import { api, type StandaloneInfo } from "$lib/api/client";

  let components = $state<any[]>([]);
  let standalone = $state<StandaloneInfo | null>(null);
  let dialogOpen = $state(false);
  let dialogError = $state("");
  let dialogImporting = $state(false);

  async function loadPageData() {
    try {
      const [data, standaloneInfo] = await Promise.all([
        api.getComponents(),
        api.getStandalone("nullclaw").catch(() => null),
      ]);
      components = data.components || [];
      standalone = standaloneInfo;
    } catch (e) {
      console.error(e);
    }
  }

  async function openExistingDialog(component: string) {
    if (component !== "nullclaw") return;
    dialogError = "";
    dialogOpen = true;
    try {
      standalone = await api.getStandalone("nullclaw");
    } catch (e) {
      console.error(e);
    }
  }

  function closeDialog() {
    if (dialogImporting) return;
    dialogOpen = false;
    dialogError = "";
  }

  async function handleExistingSubmit(payload: { path?: string; name?: string }) {
    dialogImporting = true;
    dialogError = "";
    try {
      await api.importInstance("nullclaw", payload);
      dialogOpen = false;
      await loadPageData();
    } catch (e) {
      dialogError = (e as Error).message;
    } finally {
      dialogImporting = false;
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
    <button class="add-existing-btn" onclick={() => openExistingDialog("nullclaw")}>
      Add Existing NullClaw
    </button>
  </div>

  <div class="catalog-grid">
    {#each components as comp}
      <ComponentCard
        name={comp.name}
        displayName={comp.display_name}
        description={comp.description}
        alpha={Boolean(comp.alpha)}
        installable={comp.installable !== false}
        installed={comp.installed}
        standalone={comp.name === "nullclaw" ? comp.standalone : false}
        instanceCount={comp.instance_count}
        importLabel={comp.name === "nullclaw" ? "Add Existing" : "Import"}
        onImportExisting={openExistingDialog}
      />
    {/each}
  </div>
</div>

<AddExistingDialog
  open={dialogOpen}
  {standalone}
  importing={dialogImporting}
  error={dialogError}
  onClose={closeDialog}
  onSubmit={handleExistingSubmit}
/>

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
  .add-existing-btn {
    padding: 0.7rem 0.95rem;
    border-radius: 2px;
    border: 1px solid var(--accent-dim);
    background: color-mix(in srgb, var(--accent) 10%, transparent);
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 1px;
    font-weight: 700;
    cursor: pointer;
    white-space: nowrap;
  }
  .add-existing-btn:hover {
    box-shadow: 0 0 12px var(--border-glow);
    border-color: var(--accent);
  }
  @media (max-width: 640px) {
    .page-header {
      flex-direction: column;
    }

    .add-existing-btn {
      width: 100%;
    }
  }
</style>
