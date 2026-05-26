export type InstanceCliError = {
  error: string;
  message?: string;
  stderr?: string;
  stdout?: string;
  backend?: string;
};

export function isInstanceCliError(value: unknown): value is InstanceCliError {
  return Boolean(
    value &&
      typeof value === 'object' &&
      !Array.isArray(value) &&
      'error' in (value as Record<string, unknown>),
  );
}

export function describeInstanceCliError(value: unknown, fallback = 'Data is unavailable.'): string {
  if (!isInstanceCliError(value)) return fallback;
  if (value.message && value.message.length > 0) return value.message;
  if (value.error && value.error.length > 0) return value.error.replaceAll('_', ' ');
  return fallback;
}
