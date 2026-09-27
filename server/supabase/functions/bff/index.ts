// Entry point for the `bff` edge function.
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided by the
// platform; the rest are `supabase secrets set`.
import { createAuth } from "../_shared/auth.ts";
import { createPostgrest } from "../_shared/postgrest.ts";
import { PostgrestAccountStore } from "./account_store.ts";
import { createHandler } from "./handler.ts";
import { PostgrestStore } from "./store.ts";

const env = (name: string) => Deno.env.get(name) ?? "";

const db = createPostgrest(fetch, env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));
const handler = createHandler({
  store: new PostgrestStore(db),
  accounts: new PostgrestAccountStore(db),
  auth: createAuth(
    fetch,
    env("SUPABASE_URL"),
    env("SUPABASE_ANON_KEY"),
    env("SUPABASE_SERVICE_ROLE_KEY"),
  ),
  fetch,
  jusoKey: env("JUSO_API_KEY"),
  vworldKey: env("VWORLD_KEY"),
  vworldDomain: Deno.env.get("VWORLD_DOMAIN") || undefined,
  // Error class names only: no query strings, coordinates or addresses.
  logError: (message) => console.error(message),
});

Deno.serve(handler);
