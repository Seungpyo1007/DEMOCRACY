// KoreaPoliticsAPI release → kpa_apply (see the kpa_import migration).
//
//   mode=latest     the repo's latest release; skipped when kpa_imports already has its tag
//   tag=v2026.10.22 a given release, for pinning or rolling back
//   force=1         apply even when the tag was applied before
//
// Every file is checked against manifest.json before anything is written.

import { kstToday } from "../_shared/dates.ts";
import type { FetchLike } from "../_shared/http.ts";
import type { Postgrest } from "../_shared/postgrest.ts";

export const KPA_REPO = "Seungpyo1007/KoreaPoliticsAPI";
export const SCHEMA_VERSION = 1;

/** The files this pass reads. people.json only maps a photo's person to a mona_cd. */
export const KPA_FILES = [
  "parties.json",
  "ruling_periods.json",
  "pledges.json",
  "photos.json",
  "people.json",
] as const;

export interface KpaIngestDeps {
  db: Postgrest;
  fetch: FetchLike;
  now?: () => Date;
}

type J = Record<string, unknown>;

interface Release {
  tag_name: string;
  assets: { name: string; browser_download_url: string }[];
}

export interface Manifest {
  tag: string;
  schema_version: number;
  files: Record<string, { records: number; sha256: string }>;
}

const TAG = /^v\d{4}\.\d{2}\.\d{2}(\.\d+)?$/;

async function get(fetchFn: FetchLike, url: string, accept: string): Promise<Uint8Array> {
  const res = await fetchFn(url, {
    headers: { Accept: accept, "User-Agent": "democracy-ingest-kpa" },
    signal: AbortSignal.timeout(60_000),
  });
  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`${url} answered ${res.status}`);
  }
  return new Uint8Array(await res.arrayBuffer());
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes as BufferSource);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function parse(bytes: Uint8Array, name: string): unknown {
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new Error(`${name}: not JSON`);
  }
}

/** Checks one file against its manifest entry and returns the parsed array. */
export async function verifyFile(
  manifest: Manifest,
  name: string,
  bytes: Uint8Array,
): Promise<J[]> {
  const entry = manifest.files[name];
  if (!entry) throw new Error(`${name}: not in the manifest`);
  const sum = await sha256Hex(bytes);
  if (sum !== entry.sha256.toLowerCase()) {
    throw new Error(`${name}: sha256 ${sum} does not match the manifest`);
  }
  const data = parse(bytes, name);
  if (!Array.isArray(data)) throw new Error(`${name}: not an array`);
  if (data.length !== entry.records) {
    throw new Error(`${name}: ${data.length} records, the manifest says ${entry.records}`);
  }
  return data as J[];
}

export function checkManifest(raw: unknown, tag: string): Manifest {
  const m = raw as Manifest;
  if (!m || typeof m !== "object" || typeof m.files !== "object" || m.files === null) {
    throw new Error("manifest.json: no files map");
  }
  if (m.schema_version !== SCHEMA_VERSION) {
    throw new Error(
      `manifest.json: schema_version ${m.schema_version}, this function reads ${SCHEMA_VERSION}`,
    );
  }
  if (m.tag !== tag) throw new Error(`manifest.json: tag ${m.tag}, release is ${tag}`);
  return m;
}

/**
 * The colour valid on `today`: among entries whose `from` is null (no start known) or not
 * after today, the one that started last. None means no colour.
 */
export function pickColor(colors: unknown, today: string): J | null {
  const list = (Array.isArray(colors) ? colors : []) as J[];
  let best: J | null = null;
  for (const c of list) {
    const from = c.from as string | null | undefined;
    if (from && from > today) continue;
    const bestFrom = (best?.from as string | null | undefined) ?? "";
    if (!best || (from ?? "") >= bestFrom) best = c;
  }
  return best;
}

const PUBLISHERS: [string, string][] = [
  ["nec.go.kr", "중앙선거관리위원회"],
  ["assembly.go.kr", "국회사무처"],
];

/** Who published a source, from its domain. An unknown domain is shown as the host. */
export function publisherFor(url: string): string {
  const host = new URL(url).host.toLowerCase();
  for (const [domain, name] of PUBLISHERS) {
    if (host === domain || host.endsWith(`.${domain}`)) return name;
  }
  return host.replace(/^www\./, "");
}

/** A KPA `checked_at` date is a Korean calendar day. */
function kstMidnight(date: unknown, field: string): string {
  if (typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error(`${field}: checked_at must be YYYY-MM-DD`);
  }
  return `${date}T00:00:00+09:00`;
}

function firstUrl(v: unknown, field: string): string {
  const url = Array.isArray(v) ? v[0] : undefined;
  if (typeof url !== "string" || !url) throw new Error(`${field}: no source_urls`);
  return url;
}

export interface Dump {
  parties: J[];
  rulingPeriods: J[];
  pledges: J[];
  photos: J[];
  people: J[];
}

/** Turns the dump into kpa_apply's arguments. Throws on anything kpa_apply cannot take. */
export function toApplyArgs(dump: Dump, today: string) {
  const partyName = new Map<string, string>();
  for (const p of dump.parties) partyName.set(String(p.id), String(p.name));

  // One row per name; the record whose id sorts first gives the row its kpa_id.
  const byName = new Map<string, J[]>();
  for (const p of [...dump.parties].sort((a, b) => String(a.id).localeCompare(String(b.id)))) {
    const name = String(p.name ?? "");
    if (!name || !p.id) throw new Error(`parties: a record without id or name`);
    byName.set(name, [...(byName.get(name) ?? []), p]);
  }
  const sameName: { name: string; kpaIds: string[] }[] = [];
  const parties = [...byName.entries()].map(([name, records]) => {
    if (records.length > 1) sameName.push({ name, kpaIds: records.map((r) => String(r.id)) });
    const p = records[0];
    const color = pickColor(p.colors, today);
    let predecessor: string | null = null;
    if (p.predecessor) {
      predecessor = partyName.get(String(p.predecessor)) ?? null;
      if (!predecessor) throw new Error(`parties ${p.id}: predecessor ${p.predecessor} unknown`);
    }
    return {
      kpa_id: String(p.id),
      name,
      color: color ? color.hex : null,
      color_source_url: color ? firstUrl(color.source_urls, `parties ${p.id} colour`) : null,
      color_checked_at: color ? color.checked_at : null,
      predecessor,
      note: typeof p.note === "string" ? p.note : null,
    };
  });

  const rulingPeriods = dump.rulingPeriods.map((r) => {
    let party: string | null = null;
    if (r.party_id !== null && r.party_id !== undefined) {
      party = partyName.get(String(r.party_id)) ?? null;
      if (!party) throw new Error(`ruling_periods ${r.starts_on}: party ${r.party_id} unknown`);
    }
    return {
      starts_on: r.starts_on,
      ends_on: r.ends_on ?? null,
      party_name: party,
      president: r.president,
      note: typeof r.note === "string" ? r.note : null,
      source_url: firstUrl(r.source_urls, `ruling_periods ${r.starts_on}`),
    };
  });

  const seen = new Set<string>();
  const boards = dump.pledges.map((b) => {
    const office = /^assembly\/(nec-[0-9a-z]+)$/.exec(String(b.office ?? ""));
    if (!office) throw new Error(`pledges: office ${b.office} is not assembly/<district id>`);
    const sourceUrl = firstUrl(b.source_urls, `pledges ${b.office}`);
    const list = (Array.isArray(b.pledges) ? b.pledges : []) as J[];
    return {
      district_id: office[1],
      source_url: sourceUrl,
      publisher: publisherFor(sourceUrl),
      fetched_at: kstMidnight(b.checked_at, `pledges ${b.office}`),
      pledges: list.map((p, i) => {
        const id = String(p.id ?? "");
        if (!id || typeof p.title !== "string" || !p.title) {
          throw new Error(`pledges ${b.office}: pledge ${i} needs id and title`);
        }
        if (seen.has(id)) throw new Error(`pledges: id ${id} appears twice`);
        seen.add(id);
        return { id, title: p.title, page: p.page ?? null, sort: i };
      }),
    };
  });

  const monaCd = new Map<string, string | null>();
  for (const p of dump.people) {
    const ids = p.external_ids as J | undefined;
    monaCd.set(
      String(p.id),
      typeof ids?.assembly_mona_cd === "string" ? ids.assembly_mona_cd : null,
    );
  }
  const photos = dump.photos.map((p) => ({
    person_id: String(p.person_id),
    mona_cd: monaCd.get(String(p.person_id)) ?? null,
    license: p.license,
    attribution: p.attribution ?? null,
    license_checked_at: kstMidnight(p.checked_at, `photos ${p.person_id}`),
    license_note: typeof p.decision === "string" ? p.decision : null,
  }));

  return { parties, rulingPeriods, boards, photos, sameName };
}

async function release(deps: KpaIngestDeps, tag: string | null): Promise<Release> {
  const path = tag ? `tags/${tag}` : "latest";
  const bytes = await get(
    deps.fetch,
    `https://api.github.com/repos/${KPA_REPO}/releases/${path}`,
    "application/vnd.github+json",
  );
  const r = parse(bytes, "release") as Release;
  if (!r || typeof r.tag_name !== "string" || !Array.isArray(r.assets)) {
    throw new Error("GitHub answered without tag_name or assets");
  }
  return r;
}

export async function runKpaIngest(mode: string, deps: KpaIngestDeps, url: URL) {
  const pinned = url.searchParams.get("tag");
  if (pinned !== null && !TAG.test(pinned)) {
    throw new RangeError(`tag ${pinned} is not vYYYY.MM.DD`);
  }
  if (pinned === null && mode !== "latest") throw new RangeError("mode=latest or tag=<tag>");
  const force = url.searchParams.get("force") === "1";

  const rel = await release(deps, pinned);
  const tag = rel.tag_name;
  if (!force) {
    const done = await deps.db.select("kpa_imports", { select: "tag", tag: `eq.${tag}` });
    if (done.length > 0) return { tag, skipped: "already applied" };
  }

  const asset = (name: string) => {
    const a = rel.assets.find((x) => x.name === name);
    if (!a) throw new Error(`release ${tag} has no ${name}`);
    return get(deps.fetch, a.browser_download_url, "application/octet-stream");
  };

  const manifest = checkManifest(parse(await asset("manifest.json"), "manifest.json"), tag);
  const files: Record<string, J[]> = {};
  for (const name of KPA_FILES) files[name] = await verifyFile(manifest, name, await asset(name));

  const today = kstToday(deps.now?.() ?? new Date());
  const args = toApplyArgs({
    parties: files["parties.json"],
    rulingPeriods: files["ruling_periods.json"],
    pledges: files["pledges.json"],
    photos: files["photos.json"],
    people: files["people.json"],
  }, today);

  const applied = await deps.db.rpc<J>("kpa_apply", {
    p_tag: tag,
    p_schema_version: manifest.schema_version,
    p_files: manifest.files,
    p_parties: args.parties,
    p_ruling_periods: args.rulingPeriods,
    p_boards: args.boards,
    p_photos: args.photos,
  });
  return { tag, ...applied, partiesSharingName: args.sameName };
}
