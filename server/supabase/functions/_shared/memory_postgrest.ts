// In-memory stand-in for the PostgREST client, for offline ingest tests.
// Supports the filter forms the ingest code uses: eq., neq., gte., lte.,
// is.null, not.is.null, in.(...), plus `limit`. `select`/`order` are ignored
// except that `order=<col>.desc` sorts descending.

import type { Postgrest } from "./postgrest.ts";

type Row = Record<string, unknown>;

function parseIn(v: string): string[] {
  const inner = v.slice(4, -1);
  const out: string[] = [];
  for (const m of inner.matchAll(/"((?:[^"\\]|\\.)*)"|([^,]+)/g)) {
    out.push(m[1] !== undefined ? m[1].replace(/\\"/g, '"') : m[2]);
  }
  return out;
}

function matches(row: Row, col: string, filter: string): boolean {
  const val = row[col];
  const s = val === null || val === undefined ? null : String(val);
  if (filter === "is.null") return s === null;
  if (filter === "not.is.null") return s !== null;
  if (filter.startsWith("eq.")) return s === filter.slice(3);
  if (filter.startsWith("neq.")) return s !== filter.slice(4);
  if (filter.startsWith("gte.")) return s !== null && s >= filter.slice(4);
  if (filter.startsWith("lte.")) return s !== null && s <= filter.slice(4);
  if (filter.startsWith("in.(")) return s !== null && parseIn(filter).includes(s);
  throw new Error(`memory postgrest: unsupported filter ${col}=${filter}`);
}

const RESERVED = new Set(["select", "order", "limit", "on_conflict"]);

export class MemoryPostgrest implements Postgrest {
  readonly tables = new Map<string, Row[]>();
  readonly calls: string[] = [];

  rows(table: string): Row[] {
    if (!this.tables.has(table)) this.tables.set(table, []);
    return this.tables.get(table)!;
  }

  private filter(table: string, query: Record<string, string>): Row[] {
    let out = this.rows(table).filter((r) =>
      Object.entries(query).every(([k, v]) => RESERVED.has(k) || matches(r, k, v))
    );
    const order = query.order?.split(",")[0];
    if (order) {
      const [col, dir] = order.split(".");
      out = [...out].sort((a, b) => String(a[col] ?? "").localeCompare(String(b[col] ?? "")));
      if (dir === "desc") out.reverse();
    }
    if (query.limit) out = out.slice(0, Number(query.limit));
    return out;
  }

  select<T>(table: string, query: Record<string, string>): Promise<T[]> {
    this.calls.push(`select ${table}`);
    return Promise.resolve(this.filter(table, query).map((r) => ({ ...r })) as T[]);
  }

  upsert(table: string, rows: object[], onConflict: string): Promise<void> {
    this.calls.push(`upsert ${table} ${rows.length}`);
    const keys = onConflict.split(",");
    const data = this.rows(table);
    for (const row of rows as Row[]) {
      const i = data.findIndex((d) => keys.every((k) => d[k] === row[k]));
      if (i >= 0) data[i] = { ...data[i], ...row };
      else data.push({ ...row });
    }
    return Promise.resolve();
  }

  /** Tests register SQL-function stand-ins here. */
  readonly rpcs = new Map<
    string,
    (args: Record<string, unknown>, db: MemoryPostgrest) => unknown
  >();

  rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
    this.calls.push(`rpc ${fn}`);
    const impl = this.rpcs.get(fn);
    return Promise.resolve((impl ? impl(args, this) : []) as T);
  }

  delete(table: string, query: Record<string, string>): Promise<void> {
    const keep = this.rows(table).filter((r) => !this.filter(table, query).includes(r));
    this.tables.set(table, keep);
    return Promise.resolve();
  }

  update(table: string, query: Record<string, string>, patch: object): Promise<void> {
    this.calls.push(`update ${table}`);
    for (const r of this.filter(table, query)) Object.assign(r, patch);
    return Promise.resolve();
  }
}
