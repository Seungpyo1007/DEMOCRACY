// Entry point for `ingest-kpa`. Called by pg_cron via pg_net:
//   POST /functions/v1/ingest-kpa?mode=latest   or   ?tag=v2026.10.22.3[&force=1]
//   header x-ingest-secret: <INGEST_SECRET>
import { ingestHandler } from "../_shared/ingest_common.ts";
import { createPostgrest } from "../_shared/postgrest.ts";
import { runKpaIngest } from "./ingest.ts";

const env = (name: string) => Deno.env.get(name) ?? "";

Deno.serve(ingestHandler(env("INGEST_SECRET"), (mode, url) =>
  runKpaIngest(mode, {
    db: createPostgrest(fetch, env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY")),
    fetch,
  }, url)));
