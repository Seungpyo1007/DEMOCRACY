// Minimal PostgREST client using the service-role key. Only edge functions use
// it; tables have RLS enabled with no policies, so anon/authenticated cannot
// read them directly.

import type { FetchLike } from "./http.ts";

export class PostgrestError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = "PostgrestError";
  }
}

export interface Postgrest {
  select<T>(table: string, query: Record<string, string>): Promise<T[]>;
  upsert(table: string, rows: object[], onConflict: string): Promise<void>;
  rpc<T>(fn: string, args: Record<string, unknown>): Promise<T>;
  delete(table: string, query: Record<string, string>): Promise<void>;
  update(table: string, query: Record<string, string>, patch: object): Promise<void>;
}

export function createPostgrest(
  fetchFn: FetchLike,
  supabaseUrl: string,
  serviceRoleKey: string,
): Postgrest {
  const base = `${supabaseUrl.replace(/\/$/, "")}/rest/v1`;
  const headers = {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
    "Content-Type": "application/json",
  };

  async function call(url: string, init: RequestInit): Promise<Response> {
    const res = await fetchFn(url, { ...init, headers: { ...headers, ...(init.headers ?? {}) } });
    if (!res.ok) {
      const body = await res.text();
      throw new PostgrestError(`postgrest ${res.status}: ${body.slice(0, 300)}`, res.status);
    }
    return res;
  }

  return {
    async select<T>(table: string, query: Record<string, string>): Promise<T[]> {
      const url = new URL(`${base}/${table}`);
      for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
      const res = await call(url.toString(), { method: "GET" });
      return (await res.json()) as T[];
    },
    async upsert(table: string, rows: object[], onConflict: string): Promise<void> {
      if (rows.length === 0) return;
      const CHUNK = 500;
      for (let i = 0; i < rows.length; i += CHUNK) {
        const url = new URL(`${base}/${table}`);
        url.searchParams.set("on_conflict", onConflict);
        const res = await call(url.toString(), {
          method: "POST",
          headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
          body: JSON.stringify(rows.slice(i, i + CHUNK)),
        });
        await res.body?.cancel();
      }
    },
    async rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
      const res = await call(`${base}/rpc/${fn}`, { method: "POST", body: JSON.stringify(args) });
      return (await res.json()) as T;
    },
    async delete(table: string, query: Record<string, string>): Promise<void> {
      const url = new URL(`${base}/${table}`);
      for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
      const res = await call(url.toString(), {
        method: "DELETE",
        headers: { Prefer: "return=minimal" },
      });
      await res.body?.cancel();
    },
    async update(table: string, query: Record<string, string>, patch: object): Promise<void> {
      const url = new URL(`${base}/${table}`);
      for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
      const res = await call(url.toString(), {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify(patch),
      });
      await res.body?.cancel();
    },
  };
}

/** PostgREST `in.(...)` filter value with each item double-quoted. */
export function inList(values: string[]): string {
  return `in.(${values.map((v) => `"${v.replace(/"/g, '\\"')}"`).join(",")})`;
}
