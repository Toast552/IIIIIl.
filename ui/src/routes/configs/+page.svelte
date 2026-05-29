<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";

  type ConfigCard = {
    title: string;
    href: string;
    primary: string;
    secondary: string;
    tone: "ok" | "warn" | "neutral";
  };

  let providers = $state<any[]>([]);
  let channels = $state<any[]>([]);
  let providerError = $state("");
  let channelError = $state("");
  let loading = $state(true);

  let validProviders = $derived(
    providers.filter((provider) => provider.last_validation_ok || provider.validated_at).length,
  );
  let validChannels = $derived(
    channels.filter((channel) => channel.last_validation_ok || channel.validated_at).length,
  );
  let cards = $derived<ConfigCard[]>([
    {
      title: "Providers",
      href: "/providers",
      primary: `${providers.length} saved`,
      secondary: providerError || `${validProviders} validated`,
      tone: providerError ? "warn" : providers.length > 0 ? "ok" : "neutral",
    },
    {
      title: "Channels",
      href: "/channels",
      primary: `${channels.length} saved`,
      secondary: channelError || `${validChannels} validated`,
      tone: channelError ? "warn" : channels.length > 0 ? "ok" : "neutral",
    },
  ]);

  onMount(async () => {
    await Promise.all([loadProviders(), loadChannels()]);
    loading = false;
  });

  async function loadProviders() {
    providerError = "";
    try {
      const data = await api.getSavedProviders();
      providers = data.providers || [];
    } catch (e) {
      providerError = (e as Error).message;
    }
  }

  async function loadChannels() {
    channelError = "";
    try {
      const data = await api.getSavedChannels();
      channels = data.channels || [];
    } catch (e) {
      channelError = (e as Error).message;
    }
  }
</script>

<div class="configs-page" aria-busy={loading}>
  <div class="page-header">
    <h1>Configs</h1>
  </div>

  <div class="config-grid">
    {#each cards as card}
      <a href={card.href} class="config-card {card.tone}">
        <div>
          <h2>{card.title}</h2>
        </div>
        <div class="card-meta">
          <strong>{loading ? "Loading..." : card.primary}</strong>
          <span>{loading ? "-" : card.secondary}</span>
        </div>
      </a>
    {/each}
  </div>
</div>

<style>
  .configs-page {
    padding: 2rem;
    max-width: 1000px;
    margin: 0 auto;
  }

  .page-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
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

  .config-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 1.5rem;
  }

  .config-card {
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    min-height: 180px;
    gap: 1.5rem;
    padding: 1.5rem;
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: 4px;
    color: var(--fg);
    transition: background-color 0.2s ease, border-color 0.2s ease, box-shadow 0.2s ease, color 0.2s ease, transform 0.2s ease, text-shadow 0.2s ease;
    backdrop-filter: blur(4px);
  }

  .config-card:hover,
  .config-card:focus-visible {
    text-decoration: none;
    background: var(--bg-hover);
    border-color: var(--accent);
    box-shadow: 0 0 15px var(--border-glow);
    transform: translateY(-2px);
  }

  .config-card.ok {
    border-color: color-mix(in srgb, var(--success) 35%, var(--border));
  }

  .config-card.warn {
    border-color: color-mix(in srgb, var(--warning) 45%, var(--border));
  }

  h2 {
    color: var(--accent);
    font-size: 1.25rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1px;
    text-shadow: var(--text-glow);
  }

  .card-meta {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: 1rem;
    padding-top: 1rem;
    border-top: 1px solid color-mix(in srgb, var(--border) 50%, transparent);
  }

  .card-meta strong {
    color: var(--fg);
    font-family: var(--font-mono);
    font-size: 1rem;
  }

  .card-meta span {
    color: var(--fg-dim);
    font-family: var(--font-mono);
    font-size: 0.8125rem;
    text-align: right;
  }

  @media (max-width: 760px) {
    .configs-page {
      padding: 1rem;
    }

    .config-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
