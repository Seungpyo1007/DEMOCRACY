// Entry point for the `bff` edge function.
import { createPostgrest } from "../_shared/postgrest.ts";
import { createHandler } from "./handler.ts";
import { PostgrestStore } from "./store.ts";

const env = (name: string) => Deno.env.get(name) ?? "";

const handler = createHandler({
  store: new PostgrestStore(
    createPostgrest(fetch, env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY")),
  ),
  fetch,
  jusoKey: env("JUSO_API_KEY"),
  kakaoKey: env("KAKAO_REST_KEY"),
  // Error class names only: no query strings, coordinates or addresses.
  logError: (message) => console.error(message),
});

Deno.serve(handler);
