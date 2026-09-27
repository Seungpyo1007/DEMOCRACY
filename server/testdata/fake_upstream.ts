// An offline stand-in for every upstream API, serving the sample files in
// this directory. Records every URL it was asked for (keys included) so tests
// can assert that keys went upstream and nowhere else.

import type { FetchLike } from "../supabase/functions/_shared/http.ts";

export function sample(name: string): string {
  return Deno.readTextFileSync(new URL(`./${name}`, import.meta.url));
}

export interface FakeUpstream {
  fetch: FetchLike;
  requests: string[];
}

const json = (body: string, status = 200) =>
  new Response(body, { status, headers: { "Content-Type": "application/json" } });

export function fakeUpstream(overrides: Record<string, () => Response> = {}): FakeUpstream {
  const requests: string[] = [];
  const fetch: FetchLike = (input) => {
    const url = new URL(
      typeof input === "string" ? input : input instanceof URL ? input.href : input.url,
    );
    requests.push(url.toString());
    for (const [needle, respond] of Object.entries(overrides)) {
      if (url.toString().includes(needle)) return Promise.resolve(respond());
    }
    const p = url.searchParams;
    const page = Number(p.get("pIndex") ?? p.get("pageNo") ?? "1");

    if (url.host === "open.assembly.go.kr") {
      if (page > 1) return Promise.resolve(json(sample("assembly_info200.json")));
      const service = url.pathname.split("/").pop();
      switch (service) {
        case "nwvrqwxyaytdsfvhu":
          return Promise.resolve(json(sample("assembly_members.json")));
        case "ALLNAMEMBER":
          return Promise.resolve(json(sample("assembly_allmembers.json")));
        case "nzmimeepazxkubdpn":
          return Promise.resolve(json(
            p.get("AGE") === "21"
              ? sample("assembly_bills_21.json")
              : sample("assembly_bills.json"),
          ));
        case "nojepdqqaweusdfbi":
          return Promise.resolve(json(
            p.get("BILL_ID") === "PRC_FAKE0001"
              ? sample("assembly_votes.json")
              : sample("assembly_info200.json"),
          ));
      }
    }
    if (url.host === "apis.data.go.kr") {
      const op = url.pathname.split("/").pop();
      if (page > 1) return Promise.resolve(json(sample("nec_nodata.json")));
      switch (op) {
        case "getCommonSgCodeList":
          return Promise.resolve(json(sample("nec_sg_codes.json")));
        case "getCommonSggCodeList":
          return Promise.resolve(json(sample("nec_sgg_codes.json")));
        case "getWinnerInfoInqire": {
          const sg = p.get("sgId");
          const file = `nec_winners_${sg}.json`;
          try {
            return Promise.resolve(json(sample(file)));
          } catch {
            return Promise.resolve(json(sample("nec_nodata.json")));
          }
        }
        case "getPofelcddRegistSttusInfoInqire":
          return Promise.resolve(json(sample("nec_candidates_single.json")));
        case "getPoelpcddRegistSttusInfoInqire":
          return Promise.resolve(json(sample("nec_nodata.json")));
      }
    }
    if (url.host === "business.juso.go.kr") {
      return Promise.resolve(json(sample("juso_search.json")));
    }
    if (url.host === "api.vworld.kr") return Promise.resolve(json(sample("vworld_address.json")));
    return Promise.resolve(new Response("not found", { status: 404 }));
  };
  return { fetch, requests };
}
