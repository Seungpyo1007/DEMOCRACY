// Fetch with retry/backoff. Everything takes an injected `fetch` so tests run
// offline and ingest code never reaches the network in CI.

export type FetchLike = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

export class UpstreamError extends Error {
  constructor(
    message: string,
    readonly status?: number,
    readonly retryable = false,
  ) {
    super(message);
    this.name = "UpstreamError";
  }
}

export interface RetryOptions {
  retries?: number;
  baseDelayMs?: number;
  timeoutMs?: number;
  sleep?: (ms: number) => Promise<void>;
  init?: RequestInit;
}

const defaultSleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/**
 * GETs `url` and returns the body text. Retries on network errors, timeouts,
 * 429 and 5xx with exponential backoff. 4xx other than 429 fail at once.
 *
 * The URL may carry an API key, so it never appears in a thrown message.
 */
export async function fetchTextWithRetry(
  fetchFn: FetchLike,
  url: string,
  opts: RetryOptions = {},
): Promise<string> {
  const retries = opts.retries ?? 3;
  const base = opts.baseDelayMs ?? 500;
  const timeoutMs = opts.timeoutMs ?? 20_000;
  const sleep = opts.sleep ?? defaultSleep;
  const label = redactUrl(url);

  let lastError: unknown;
  for (let attempt = 0; attempt <= retries; attempt++) {
    if (attempt > 0) await sleep(base * 2 ** (attempt - 1));
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetchFn(url, { ...opts.init, signal: controller.signal });
      const body = await res.text();
      if (res.ok) return body;
      const retryable = res.status === 429 || res.status >= 500;
      lastError = new UpstreamError(`${label} answered ${res.status}`, res.status, retryable);
      if (!retryable) throw lastError;
    } catch (error) {
      if (error instanceof UpstreamError && !error.retryable) throw error;
      lastError = error instanceof UpstreamError ? error : new UpstreamError(
        `${label} failed: ${(error as Error)?.name ?? "error"}`,
        undefined,
        true,
      );
    } finally {
      clearTimeout(timer);
    }
  }
  throw lastError;
}

export async function fetchJsonWithRetry(
  fetchFn: FetchLike,
  url: string,
  opts: RetryOptions = {},
): Promise<unknown> {
  const text = await fetchTextWithRetry(fetchFn, url, opts);
  try {
    return JSON.parse(text);
  } catch {
    // data.go.kr's gateway answers auth/quota failures in XML even when JSON
    // was asked for; surface its reason code rather than a parse error.
    const reason = /<returnReasonCode>(\d+)<\/returnReasonCode>/.exec(text)?.[1];
    const msg = /<returnAuthMsg>([^<]+)<\/returnAuthMsg>/.exec(text)?.[1];
    throw new UpstreamError(
      reason
        ? `gateway error ${reason} ${msg ?? ""}`.trim()
        : `${redactUrl(url)} returned non-JSON`,
      undefined,
      reason === "22", // LIMITED_NUMBER_OF_SERVICE_REQUESTS_EXCEEDS
    );
  }
}

/** Strips credential-bearing query params so a URL can be logged. */
export function redactUrl(url: string): string {
  try {
    const u = new URL(url);
    for (const key of [...u.searchParams.keys()]) {
      if (/^(KEY|ServiceKey|confmKey|apikey)$/i.test(key)) u.searchParams.set(key, "***");
    }
    return u.toString();
  } catch {
    return "<invalid url>";
  }
}
