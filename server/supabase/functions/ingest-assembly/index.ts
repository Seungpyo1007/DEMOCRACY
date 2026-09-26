// Entry point for `ingest-assembly`. Called by pg_cron via pg_net:
//   POST /functions/v1/ingest-assembly?mode=members|bills|votes|bills_votes
//   header x-ingest-secret: <INGEST_SECRET>
import { ingestHandler } from "../_shared/ingest_common.ts";
import { createPostgrest } from "../_shared/postgrest.ts";
import { runAssemblyIngest } from "./ingest.ts";

const env = (name: string) => Deno.env.get(name) ?? "";

Deno.serve(ingestHandler(env("INGEST_SECRET"), (mode) =>
  runAssemblyIngest(mode, {
    db: createPostgrest(fetch, env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY")),
    fetch,
    key: env("ASSEMBLY_API_KEY"),
  })));
