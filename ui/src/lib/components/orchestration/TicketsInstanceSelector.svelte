<script lang="ts">
  import ManagedInstanceSelector from "./ManagedInstanceSelector.svelte";
  import {
    getSelectedTicketsInstance,
    setSelectedTicketsInstance,
  } from "$lib/orchestration/backendSelection";

  let {
    onChange = () => {},
  } = $props<{
    onChange?: (name: string) => void;
  }>();
</script>

<ManagedInstanceSelector
  component="nulltickets"
  label="NullTickets"
  getSelected={getSelectedTicketsInstance}
  setSelected={setSelectedTicketsInstance}
  {onChange}
/>
