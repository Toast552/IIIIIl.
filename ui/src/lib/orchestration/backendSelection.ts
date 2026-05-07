const SELECTED_BOILER_STORAGE_KEY = "nullhub.orchestration.boiler_instance";
const SELECTED_TICKETS_STORAGE_KEY = "nullhub.orchestration.tickets_instance";

function storage(): Storage | null {
  try {
    return typeof globalThis !== "undefined" && "localStorage" in globalThis
      ? globalThis.localStorage
      : null;
  } catch {
    return null;
  }
}

export function getSelectedBoilerInstance(): string {
  return storage()?.getItem(SELECTED_BOILER_STORAGE_KEY) || "";
}

export function setSelectedBoilerInstance(value: string) {
  const store = storage();
  if (!store) return;
  if (value) store.setItem(SELECTED_BOILER_STORAGE_KEY, value);
  else store.removeItem(SELECTED_BOILER_STORAGE_KEY);
}

export function getSelectedTicketsInstance(): string {
  return storage()?.getItem(SELECTED_TICKETS_STORAGE_KEY) || "";
}

export function setSelectedTicketsInstance(value: string) {
  const store = storage();
  if (!store) return;
  if (value) store.setItem(SELECTED_TICKETS_STORAGE_KEY, value);
  else store.removeItem(SELECTED_TICKETS_STORAGE_KEY);
}
