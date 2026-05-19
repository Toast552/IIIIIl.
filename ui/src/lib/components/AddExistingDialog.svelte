<script lang="ts">
  import type { StandaloneInfo } from "$lib/api/client";

  let {
    open = false,
    standalone = null as StandaloneInfo | null,
    importing = false,
    error = "",
    onClose = () => {},
    onSubmit = async (_payload: { path?: string; name?: string }) => {},
  } = $props();

  let path = $state("");
  let name = $state("");

  $effect(() => {
    if (!open) return;
    path = standalone?.standalone && !standalone?.already_imported ? (standalone.standalone_path ?? "") : "";
    name = "";
  });

  const canSubmit = $derived(!importing && path.trim().length > 0);

  async function handleSubmit() {
    if (!canSubmit) return;
    await onSubmit({
      path: path.trim(),
      name: name.trim() || undefined,
    });
  }

  function close() {
    if (importing) return;
    onClose();
  }
</script>

{#if open}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div class="modal-backdrop" role="button" tabindex="-1" onclick={close}>
    <div
      class="modal"
      role="dialog"
      aria-label="Add existing NullClaw"
      tabindex="-1"
      onclick={(e) => e.stopPropagation()}
      onkeydown={(e) => {
        if (e.key === "Escape") close();
      }}
    >
      <div class="modal-header">
        <div>
          <div class="modal-title">Add Existing NullClaw</div>
          <div class="modal-subtitle">Register a local NullClaw home already on this machine.</div>
        </div>
        <button class="modal-close" onclick={close} aria-label="Close">&#x2715;</button>
      </div>

      <div class="modal-body">
        <div class="form-field">
          <label class="form-label" for="existing-path">Instance Path</label>
          <input
            id="existing-path"
            class="form-input"
            bind:value={path}
            placeholder="/Users/you/.nullclaw"
            autocomplete="off"
            spellcheck="false"
          />
          <div class="form-hint">
            Path to the existing NullClaw directory containing `config.json`.
          </div>
        </div>

        <div class="form-field">
          <label class="form-label" for="existing-name">Instance Name</label>
          <input
            id="existing-name"
            class="form-input"
            bind:value={name}
            placeholder="Optional"
            autocomplete="off"
            spellcheck="false"
          />
          <div class="form-hint">
            Leave blank to use `instance_name` from config or let the server generate one.
          </div>
        </div>

        {#if standalone?.standalone && standalone.standalone_path}
          <div class="detected-note {standalone.already_imported ? 'muted' : ''}">
            Default install detected at <span>{standalone.standalone_path}</span>
            {#if standalone.already_imported}
              and already imported.
            {:else}
              and ready to attach.
            {/if}
          </div>
        {/if}

        {#if error}
          <div class="form-error">{error}</div>
        {/if}
      </div>

      <div class="modal-actions">
        <button class="btn secondary-btn" onclick={close} disabled={importing}>Cancel</button>
        <button class="btn primary-btn" onclick={handleSubmit} disabled={!canSubmit}>
          {importing ? "Importing..." : "Add Existing"}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .modal-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.7);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100;
    backdrop-filter: blur(2px);
  }

  .modal {
    width: min(560px, calc(100vw - 2rem));
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: 4px;
    box-shadow: 0 0 30px color-mix(in srgb, var(--accent) 15%, transparent);
  }

  .modal-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 1rem;
    padding: 1rem 1rem 0.875rem;
    border-bottom: 1px solid var(--border);
  }

  .modal-title {
    font-size: 0.95rem;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 1px;
    text-shadow: var(--text-glow);
  }

  .modal-subtitle {
    margin-top: 0.35rem;
    color: var(--fg-dim);
    font-size: 0.8rem;
    font-family: var(--font-mono);
  }

  .modal-close {
    background: none;
    border: none;
    color: var(--fg-dim);
    font-size: 1rem;
    cursor: pointer;
    padding: 0.25rem;
    line-height: 1;
  }

  .modal-body {
    padding: 1rem;
    display: grid;
    gap: 1rem;
  }

  .form-field {
    display: grid;
    gap: 0.45rem;
  }

  .form-label {
    font-size: 0.72rem;
    color: var(--fg-dim);
    text-transform: uppercase;
    letter-spacing: 1px;
    font-weight: 700;
  }

  .form-input {
    width: 100%;
    padding: 0.7rem 0.8rem;
    background: var(--bg);
    color: var(--fg);
    border: 1px solid var(--border);
    border-radius: 2px;
    font-size: 0.9rem;
    font-family: var(--font-mono);
    outline: none;
  }

  .form-input:focus {
    border-color: var(--accent-dim);
    box-shadow: 0 0 8px var(--border-glow);
  }

  .form-hint {
    color: var(--fg-dim);
    font-size: 0.78rem;
    font-family: var(--font-mono);
  }

  .detected-note {
    padding: 0.75rem 0.85rem;
    border: 1px solid color-mix(in srgb, var(--accent) 35%, transparent);
    background: color-mix(in srgb, var(--accent) 8%, transparent);
    color: var(--fg);
    font-size: 0.82rem;
    line-height: 1.5;
  }

  .detected-note.muted {
    border-color: color-mix(in srgb, var(--border) 80%, transparent);
    background: color-mix(in srgb, var(--fg-dim) 8%, transparent);
  }

  .detected-note span {
    color: var(--accent);
    font-family: var(--font-mono);
  }

  .form-error {
    color: #ff7a7a;
    font-size: 0.82rem;
    font-family: var(--font-mono);
  }

  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: 0.75rem;
    padding: 0 1rem 1rem;
  }

  .btn {
    padding: 0.65rem 0.95rem;
    border-radius: 2px;
    font-size: 0.78rem;
    text-transform: uppercase;
    letter-spacing: 1px;
    font-weight: 700;
    cursor: pointer;
  }

  .primary-btn {
    border: 1px solid var(--accent);
    background: color-mix(in srgb, var(--accent) 12%, transparent);
    color: var(--accent);
  }

  .secondary-btn {
    border: 1px solid var(--border);
    background: transparent;
    color: var(--fg-dim);
  }

  .btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
  @media (max-width: 640px) {
    .modal-actions {
      flex-direction: column-reverse;
    }

    .btn {
      width: 100%;
    }
  }
</style>
