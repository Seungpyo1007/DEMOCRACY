// Entry point for `ingest-nec`. Called by pg_cron via pg_net:
//   POST /functions/v1/ingest-nec?mode=codes|candidates|backfill|counts[&sgIds=20160413,20200415]
//   header x-ingest-secret: <INGEST_SECRET>
import { ingestHandler } from "../_shared/ingest_common.ts";
import { createPostgrest } from "../_shared/postgrest.ts";
import { runNecIngest } from "./ingest.ts";

const env = (name: string) => Deno.env.get(name) ?? "";

Deno.serve(ingestHandler(env("INGEST_SECRET"), (mode, url) =>
  runNecIngest(mode, {
    db: createPostgrest(fetch, env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY")),
    fetch,
    // The *decoded* (일반 인증키 Decoding) key from data.go.kr.
    serviceKey: env("DATA_GO_KR_KEY"),
  }, url)));
