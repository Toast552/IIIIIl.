<script lang="ts">
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import AddExistingDialog from '$lib/components/AddExistingDialog.svelte';
  import WizardRenderer from '$lib/components/WizardRenderer.svelte';
  import { api, type StandaloneInfo } from '$lib/api/client';
  import { instanceRoute } from '$lib/nullstack/path';

  let componentName = $derived($page.params.component);
  let wizardData = $state<any>(null);
  let wizardError = $state('');
  let selectedVersion = $state('latest');
  let wizardRequestSeq = 0;
  let standalone = $state<StandaloneInfo | null>(null);
  let standaloneRequestSeq = 0;
  let dialogOpen = $state(false);
  let dialogError = $state('');
  let dialogImporting = $state(false);
  let wizardSteps = $derived(
    (wizardData?.wizard?.steps || wizardData?.steps || []).filter((step: any) => {
      if (step.id === 'gateway_port') return false;
      if (step.id === 'port') return componentName !== 'nullclaw';
      return true;
    }),
  );
  let displayName = $derived(
    typeof wizardData?.display_name === 'string' && wizardData.display_name.length > 0
      ? wizardData.display_name
      : defaultDisplayName(componentName),
  );
  let existingButtonLabel = $derived(
    standalone?.already_imported ? 'Add Another Existing' : 'Add Existing',
  );

  $effect(() => {
    const comp = componentName;
    const version = selectedVersion;
    const requestSeq = ++wizardRequestSeq;
    wizardData = null;
    wizardError = '';
    api.getWizard(comp, version).then((data) => {
      if (requestSeq !== wizardRequestSeq) return;
      if (data?.error) {
        wizardError = data.error;
      } else {
        wizardData = data;
      }
    }).catch((e) => {
      if (requestSeq !== wizardRequestSeq) return;
      wizardError = (e as Error).message;
    });
  });

  $effect(() => {
    const comp = componentName;
    dialogOpen = false;
    dialogError = '';
    standalone = null;
    void refreshStandalone(comp);
  });

  function defaultDisplayName(component: string) {
    const names: Record<string, string> = {
      nullclaw: 'NullClaw',
      nullboiler: 'NullBoiler',
      nulltickets: 'NullTickets',
      nullwatch: 'NullWatch',
    };
    return names[component] || component;
  }

  async function refreshStandalone(component: string): Promise<StandaloneInfo | null> {
    const requestSeq = ++standaloneRequestSeq;
    try {
      const data = await api.getStandalone(component);
      if (requestSeq === standaloneRequestSeq && component === componentName) {
        standalone = data;
      }
      return data;
    } catch (e) {
      if (requestSeq === standaloneRequestSeq && component === componentName) {
        standalone = { standalone: false };
      }
      console.error(e);
      return null;
    }
  }

  async function openExistingDialog() {
    const comp = componentName;
    dialogError = '';
    if (!standalone) {
      await refreshStandalone(comp);
    }
    dialogOpen = true;
  }

  function closeDialog() {
    if (dialogImporting) return;
    dialogOpen = false;
    dialogError = '';
  }

  async function handleExistingSubmit(payload: { path?: string; name?: string }) {
    const comp = componentName;
    dialogImporting = true;
    dialogError = '';
    try {
      const result = await api.importInstance(comp, payload);
      dialogOpen = false;
      await goto(instanceRoute(comp, result?.instance || payload.name || 'default'));
    } catch (e) {
      dialogError = (e as Error).message;
    } finally {
      dialogImporting = false;
    }
  }

  function handleVersionChange(version: string) {
    selectedVersion = version || 'latest';
  }

</script>

<div class="wizard-page">
  <div class="existing-install">
    <div>
      <div class="existing-title">Already Have {displayName}</div>
      <div class="existing-detail">
        {#if standalone?.standalone && standalone.standalone_path}
          {#if standalone.already_imported}
            Default install is already added.
          {:else}
            Default install detected at {standalone.standalone_path}
          {/if}
        {:else}
          Add a local {displayName} home.
        {/if}
      </div>
    </div>
    <button
      type="button"
      class="existing-btn"
      onclick={openExistingDialog}
      disabled={dialogImporting}
    >
      {existingButtonLabel}
    </button>
  </div>

  {#if wizardError}
    <div class="wizard-error">
      <p>{wizardError}</p>
      <button onclick={() => goto('/install')}>Back</button>
    </div>
  {:else if wizardData}
    <WizardRenderer
      component={componentName}
      steps={wizardSteps}
      onVersionChange={handleVersionChange}
      onComplete={() => goto('/')}
    />
  {:else}
    <p>Loading wizard...</p>
  {/if}
</div>

<AddExistingDialog
  open={dialogOpen}
  component={componentName}
  {displayName}
  {standalone}
  importing={dialogImporting}
  error={dialogError}
  onClose={closeDialog}
  onSubmit={handleExistingSubmit}
/>

<style>
  .wizard-page { max-width: 600px; margin: 0 auto; }
  .existing-install {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
    margin-bottom: 1rem;
    padding: 1rem;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: color-mix(in srgb, var(--bg-surface) 85%, transparent);
  }
  .existing-title {
    color: var(--accent);
    font-size: 0.8rem;
    font-weight: 700;
    letter-spacing: 1px;
    text-transform: uppercase;
  }
  .existing-detail {
    margin-top: 0.35rem;
    color: var(--fg-dim);
    font-family: var(--font-mono);
    font-size: 0.78rem;
    line-height: 1.45;
    overflow-wrap: anywhere;
  }
  .existing-btn {
    flex: 0 0 auto;
    padding: 0.65rem 0.9rem;
    border: 1px solid var(--accent-dim);
    border-radius: 2px;
    background: color-mix(in srgb, var(--accent) 10%, transparent);
    color: var(--accent);
    cursor: pointer;
    font-size: 0.75rem;
    font-weight: 700;
    letter-spacing: 1px;
    text-transform: uppercase;
    white-space: nowrap;
  }
  .existing-btn:hover {
    border-color: var(--accent);
    box-shadow: 0 0 10px var(--border-glow);
  }
  .existing-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    box-shadow: none;
  }
  .wizard-error {
    background: var(--bg-secondary);
    border: 1px solid color-mix(in srgb, var(--error) 30%, transparent);
    border-radius: var(--radius);
    padding: 2rem;
    text-align: center;
  }
  .wizard-error p {
    color: var(--text-primary);
    margin-bottom: 1rem;
    font-size: 0.9rem;
  }
  .wizard-error button {
    padding: 0.4rem 1rem;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: var(--bg-tertiary);
    color: var(--text-primary);
    font-size: 0.8125rem;
    cursor: pointer;
  }
  .wizard-error button:hover {
    background: var(--bg-hover);
    border-color: var(--accent);
  }
  @media (max-width: 640px) {
    .existing-install {
      align-items: stretch;
      flex-direction: column;
    }

    .existing-btn {
      width: 100%;
    }
  }
</style>
