import { TICKETS_INSTANCE_QUERY_PARAM, getSelectedTicketsInstance } from "$lib/nullstack/backendSelection";
import { encodePathSegment, withQueryParam } from "$lib/nullstack/path";

type NullTicketsRouteOptions = {
  ticketsInstance?: string;
};

export function withTicketsInstance(path: string, ticketsInstance?: string): string {
  const value = ticketsInstance ?? getSelectedTicketsInstance();
  return withQueryParam(path, TICKETS_INSTANCE_QUERY_PARAM, value);
}

const nullticketsUiRoot = "/nulltickets";
const nullticketsApiRoot = "/nulltickets";
const storeBase = `${nullticketsApiRoot}/store`;

export const nullticketsUiRoutes = {
  store: (options?: NullTicketsRouteOptions) => withTicketsInstance(`${nullticketsUiRoot}/store`, options?.ticketsInstance),
};

export const nullticketsApiPaths = {
  storeNamespace: (namespace: string) => `${storeBase}/${encodePathSegment(namespace)}`,
  storeEntry: (namespace: string, key: string) => `${storeBase}/${encodePathSegment(namespace)}/${encodePathSegment(key)}`,
};
