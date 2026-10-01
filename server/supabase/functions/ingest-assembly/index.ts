// Entry point for `ingest-assembly`. Called by pg_cron via pg_net:
//   POST /functions/v1/ingest-assembly?mode=members|bills|votes|bills_votes|portraits
//   POST /functions/v1/ingest-assembly?mode=bills_backfill&age=21[&page=1&pages=10]  (by hand)
//   header x-ingest-secret: <INGEST_SECRET>
import { ingestHandler } from "../_shared/ingest_common.ts";
import { createPostgrest } from "../_shared/postgrest.ts";
import { type PortraitStorage, runAssemblyIngest } from "./ingest.ts";

const env = (name: string) => Deno.env.get(name) ?? "";

const supabaseUrl = env("SUPABASE_URL").replace(/\/$/, "");
const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");

/** Writes into the public 'portraits' bucket (see the portraits migration). */
const storage: PortraitStorage = {
  async upload(path, bytes, contentType) {
    const res = await fetch(`${supabaseUrl}/storage/v1/object/portraits/${path}`, {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": contentType,
        "x-upsert": "true",
        "Cache-Control": "max-age=31536000",
      },
      body: bytes as BodyInit,
    });
    if (!res.ok) throw new Error(`storage ${res.status}`);
    await res.body?.cancel();
  },
};

Deno.serve(ingestHandler(env("INGEST_SECRET"), (mode, url) =>
  runAssemblyIngest(mode, {
    db: createPostgrest(fetch, supabaseUrl, serviceKey),
    fetch,
    key: env("ASSEMBLY_API_KEY"),
    storage,
  }, url.searchParams)));
