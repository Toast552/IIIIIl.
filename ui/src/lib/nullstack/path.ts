export function encodePathSegment(value: string): string {
  return encodeURIComponent(value);
}

export function instanceRoute(component: string, name: string): string {
  return `/instances/${encodePathSegment(component)}/${encodePathSegment(name)}`;
}

export function componentInstancesRoute(component: string): string {
  return `/instances/${encodePathSegment(component)}`;
}

export function instanceApiPath(component: string, name: string, suffix = ""): string {
  return `/instances/${encodePathSegment(component)}/${encodePathSegment(name)}${suffix}`;
}

export function componentApiPath(component: string, suffix = ""): string {
  return `/instances/${encodePathSegment(component)}${suffix}`;
}

export function routePath(path: string): string {
  const queryIndex = path.search(/[?#]/);
  return queryIndex >= 0 ? path.slice(0, queryIndex) : path;
}

export function withQueryParam(path: string, key: string, value: string): string {
  const hashIndex = path.indexOf("#");
  const withoutHash = hashIndex >= 0 ? path.slice(0, hashIndex) : path;
  const hash = hashIndex >= 0 ? path.slice(hashIndex) : "";
  const queryIndex = withoutHash.indexOf("?");
  const pathname = queryIndex >= 0 ? withoutHash.slice(0, queryIndex) : withoutHash;
  const query = queryIndex >= 0 ? withoutHash.slice(queryIndex + 1) : "";
  const params = new URLSearchParams(query);

  if (value) params.set(key, value);
  else params.delete(key);

  const nextQuery = params.toString();
  return `${pathname}${nextQuery ? `?${nextQuery}` : ""}${hash}`;
}
