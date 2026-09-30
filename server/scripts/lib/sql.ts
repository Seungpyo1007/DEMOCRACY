// SQL text helpers for importer output. Values are always literals (no
// interpolation of identifiers from input).

export type SqlValue = string | number | boolean | null | string[] | object;

export function lit(v: SqlValue): string {
  if (v === null || v === undefined) return "null";
  if (typeof v === "number") {
    if (!Number.isFinite(v)) throw new Error(`non-finite number ${v}`);
    return String(v);
  }
  if (typeof v === "boolean") return v ? "true" : "false";
  if (Array.isArray(v)) return `array[${v.map((x) => lit(x)).join(",")}]::text[]`;
  if (typeof v === "object") return `${lit(JSON.stringify(v))}::jsonb`;
  return `'${v.replace(/'/g, "''")}'`;
}

/** INSERT ... ON CONFLICT (keys) DO UPDATE for rows with identical columns; plain INSERT when keys = []. */
export function upsertSql(
  table: string,
  rows: Record<string, SqlValue>[],
  conflict: string[],
): string {
  if (rows.length === 0) return `-- ${table}: no rows\n`;
  const cols = Object.keys(rows[0]);
  const updates = cols.filter((c) => !conflict.includes(c)).map((c) => `${c} = excluded.${c}`);
  const out: string[] = [];
  const CHUNK = 500;
  for (let i = 0; i < rows.length; i += CHUNK) {
    const values = rows.slice(i, i + CHUNK).map((r) =>
      `  (${cols.map((c) => lit(r[c])).join(", ")})`
    );
    const onConflict = conflict.length === 0
      ? ""
      : `\non conflict (${conflict.join(", ")}) ${
        updates.length ? `do update set ${updates.join(", ")}` : "do nothing"
      }`;
    out.push(
      `insert into public.${table} (${cols.join(", ")}) values\n${
        values.join(",\n")
      }${onConflict};`,
    );
  }
  return out.join("\n") + "\n";
}

export function requireHttpUrl(url: string | undefined, flag: string): string {
  if (!url || !/^https?:\/\/[^/]+/.test(url) || /[?&](KEY|ServiceKey|confmKey)=/i.test(url)) {
    throw new Error(`${flag} must be a public http(s) page without API keys`);
  }
  return url;
}

/** --name value / --name=value */
export function parseFlags(
  args: string[],
): { flags: Record<string, string>; positional: string[] } {
  const flags: Record<string, string> = {};
  const positional: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a.startsWith("--")) {
      const eq = a.indexOf("=");
      if (eq > 0) flags[a.slice(2, eq)] = a.slice(eq + 1);
      else flags[a.slice(2)] = args[++i] ?? "";
    } else {
      positional.push(a);
    }
  }
  return { flags, positional };
}
