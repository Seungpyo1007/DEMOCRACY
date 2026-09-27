// Minimal .xlsx reader: the first worksheet as a grid of strings.
//
// Enough for the Assembly's plain tabular downloads (shared strings, inline
// strings, numbers). No formulas are evaluated (the cached value is read), no
// styles, no dates-as-serials. Kept dependency-free so the importers stay
// `deno run --allow-read` scripts.

const EOCD = 0x06054b50;
const CENTRAL = 0x02014b50;
const LOCAL = 0x04034b50;

/** Entries of a zip archive, inflated. Stored (0) and deflated (8) only. */
export async function unzip(bytes: Uint8Array): Promise<Map<string, Uint8Array>> {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 0xffff); i--) {
    if (view.getUint32(i, true) === EOCD) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error("xlsx: not a zip archive");
  const count = view.getUint16(eocd + 10, true);
  let p = view.getUint32(eocd + 16, true);
  const out = new Map<string, Uint8Array>();
  const decoder = new TextDecoder();
  for (let n = 0; n < count; n++) {
    if (view.getUint32(p, true) !== CENTRAL) throw new Error("xlsx: bad central directory");
    const method = view.getUint16(p + 10, true);
    const size = view.getUint32(p + 20, true);
    const nameLen = view.getUint16(p + 28, true);
    const extraLen = view.getUint16(p + 30, true);
    const commentLen = view.getUint16(p + 32, true);
    const local = view.getUint32(p + 42, true);
    const name = decoder.decode(bytes.subarray(p + 46, p + 46 + nameLen));
    p += 46 + nameLen + extraLen + commentLen;

    if (view.getUint32(local, true) !== LOCAL) throw new Error(`xlsx: bad local header ${name}`);
    const start = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
    const data = bytes.subarray(start, start + size);
    if (method === 0) out.set(name, data);
    else if (method === 8) out.set(name, await inflateRaw(data));
    else throw new Error(`xlsx: unsupported compression ${method} for ${name}`);
  }
  return out;
}

async function inflateRaw(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data as BlobPart]).stream().pipeThrough(
    new DecompressionStream("deflate-raw"),
  );
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

function unescapeXml(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, e: string) => {
    if (e[0] === "#") {
      return String.fromCodePoint(
        e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : Number(e.slice(1)),
      );
    }
    return { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" }[e.toLowerCase()]!;
  });
}

/** Text of every <t> in a fragment, joined (rich-text runs become one string). */
function texts(fragment: string): string {
  let s = "";
  for (const m of fragment.matchAll(/<t\b[^>]*?(?:\/>|>([\s\S]*?)<\/t>)/g)) s += m[1] ?? "";
  return unescapeXml(s);
}

function columnIndex(ref: string): number {
  const letters = /^[A-Z]+/.exec(ref)?.[0];
  if (!letters) throw new Error(`xlsx: bad cell ref ${ref}`);
  let n = 0;
  for (const c of letters) n = n * 26 + c.charCodeAt(0) - 64;
  return n - 1;
}

/** Rows of the first worksheet (sheet1.xml), each padded to its last non-empty cell. */
export async function readFirstSheet(bytes: Uint8Array): Promise<string[][]> {
  const files = await unzip(bytes);
  const decoder = new TextDecoder();
  const sheet = files.get("xl/worksheets/sheet1.xml");
  if (!sheet) throw new Error("xlsx: no xl/worksheets/sheet1.xml");
  const shared: string[] = [];
  const sst = files.get("xl/sharedStrings.xml");
  if (sst) {
    for (const m of decoder.decode(sst).matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)) {
      shared.push(texts(m[1]));
    }
  }
  const rows: string[][] = [];
  for (const rm of decoder.decode(sheet).matchAll(/<row\b[^>]*?(?:\/>|>([\s\S]*?)<\/row>)/g)) {
    const cells = new Map<number, string>();
    for (const cm of (rm[1] ?? "").matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const attrs = cm[1];
      const body = cm[2] ?? "";
      const ref = /\br="([A-Z]+\d+)"/.exec(attrs)?.[1];
      if (!ref) continue;
      const type = /\bt="(\w+)"/.exec(attrs)?.[1];
      const v = /<v>([\s\S]*?)<\/v>/.exec(body)?.[1];
      let value = "";
      if (type === "s" && v !== undefined) value = shared[Number(v)] ?? "";
      else if (type === "inlineStr") value = texts(body);
      else if (v !== undefined) value = unescapeXml(v);
      cells.set(columnIndex(ref), value);
    }
    const last = Math.max(-1, ...[...cells].filter(([, v]) => v !== "").map(([i]) => i));
    rows.push(Array.from({ length: last + 1 }, (_, i) => cells.get(i) ?? ""));
  }
  return rows;
}
