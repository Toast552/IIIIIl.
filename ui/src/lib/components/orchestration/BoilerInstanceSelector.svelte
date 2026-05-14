<script lang="ts">
  import ManagedInstanceSelector from "./ManagedInstanceSelector.svelte";
  import {
    getSelectedBoilerInstance,
    setSelectedBoilerInstance,
  } from "$lib/orchestration/backendSelection";

  let {
    onChange = () => {},
  } = $props<{
    onChange?: (name: string) => void;
  }>();
</script>

<ManagedInstanceSelector
  component="nullboiler"
  label="NullBoiler"
  getSelected={getSelectedBoilerInstance}
  setSelected={setSelectedBoilerInstance}
  {onChange}
/>
