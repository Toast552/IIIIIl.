const SELECTED_BOILER_STORAGE_KEY = "nullhub.orchestration.boiler_instance";
const SELECTED_TICKETS_STORAGE_KEY = "nullhub.orchestration.tickets_instance";
export const BOILER_INSTANCE_QUERY_PARAM = "boiler_instance";
export const BOILER_INSTANCE_CHANGE_EVENT = "nullhub:boiler-instance-change";

function storage(): Storage | null {
  try {
    return typeof globalThis !== "undefined" && "localStorage" in globalThis
      ? globalThis.localStorage
      : null;
  } catch {
    return null;
  }
}

function currentLocation(): Location | null {
  try {
    return typeof globalThis !== "undefined" && "location" in globalThis
      ? globalThis.location
      : null;
  } catch {
    return null;
  }
}

function currentHistory(): History | null {
  try {
    return typeof globalThis !== "undefined" && "history" in globalThis
      ? globalThis.history
      : null;
  } catch {
    return null;
  }
}

function getUrlBoilerInstance(): string {
  const location = currentLocation();
  if (!location) return "";
  try {
    return new URLSearchParams(location.search).get(BOILER_INSTANCE_QUERY_PARAM) || "";
  } catch {
    return "";
  }
}

function syncCurrentBoilerUrl(value: string) {
  const location = currentLocation();
  const history = currentHistory();
  if (!location || !history || !location.pathname.startsWith("/orchestration")) return;

  const url = new URL(location.href);
  if (value) url.searchParams.set(BOILER_INSTANCE_QUERY_PARAM, value);
  else url.searchParams.delete(BOILER_INSTANCE_QUERY_PARAM);
  history.replaceState(history.state, "", `${url.pathname}${url.search}${url.hash}`);
}

function dispatchBoilerInstanceChange(value: string) {
  try {
    if (
      typeof globalThis !== "undefined" &&
      "dispatchEvent" in globalThis &&
      "CustomEvent" in globalThis
    ) {
      globalThis.dispatchEvent(new CustomEvent(BOILER_INSTANCE_CHANGE_EVENT, { detail: { value } }));
    }
  } catch {
    /* ignore */
  }
}

export function getSelectedBoilerInstance(): string {
  return getUrlBoilerInstance() || storage()?.getItem(SELECTED_BOILER_STORAGE_KEY) || "";
}

export function setSelectedBoilerInstance(value: string) {
  const store = storage();
  if (store) {
    if (value) store.setItem(SELECTED_BOILER_STORAGE_KEY, value);
    else store.removeItem(SELECTED_BOILER_STORAGE_KEY);
  }
  syncCurrentBoilerUrl(value);
  dispatchBoilerInstanceChange(value);
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
