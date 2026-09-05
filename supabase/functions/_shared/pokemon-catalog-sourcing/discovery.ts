// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/discovery.ts
// Percorre TODAS as páginas de uma listagem paginada da PokéAPI seguindo `next`
// — Seção 3 do contrato: "nunca assumir cardinalidade fixa" (nunca hardcodar
// "11 Regions"/"1025 Species").

import { fetchJsonWithRetry, type FetchJsonDeps } from "./http.ts";
import type {
  PokeApiNamedApiResource,
  PokeApiPagedList,
  SourcingCallLogEntry,
} from "./types.ts";

export interface DiscoverAllResult {
  status: "SUCCESS" | "TECHNICAL_FAILURE";
  items: PokeApiNamedApiResource[];
  callLog: SourcingCallLogEntry[];
  detail?: string;
}

export async function discoverAllPaged(
  firstUrl: string,
  deps: FetchJsonDeps,
  // REVISION-03 (Bloco 3) — renovação de heartbeat DURANTE a paginação de
  // discovery, não só depois que ela termina inteira. O chamador (via
  // acquisition.ts) injeta aqui a mesma função já limitada por tempo
  // (createHeartbeatGate, http.ts) usada nas outras fases — este módulo só
  // a invoca a cada página, sem saber (nem precisar saber) de tempo/relógio.
  onPageFetched?: () => Promise<void>,
): Promise<DiscoverAllResult> {
  const items: PokeApiNamedApiResource[] = [];
  const callLog: SourcingCallLogEntry[] = [];
  let url: string | null = firstUrl;

  while (url) {
    // fetchJsonWithRetry (http.ts) já rejeita qualquer url fora do
    // allowlist de origem ANTES de qualquer chamada de rede — cobre também
    // um `next` corrompido/malicioso vindo da própria resposta paginada.
    const result = await fetchJsonWithRetry(url, deps);
    callLog.push(...result.callLog);
    if (result.status !== "SUCCESS") {
      return {
        status: "TECHNICAL_FAILURE",
        items,
        callLog,
        detail: result.detail,
      };
    }
    const page = result.json as PokeApiPagedList;
    items.push(...(page.results ?? []));
    url = page.next ?? null;
    if (onPageFetched) await onPageFetched();
  }

  return { status: "SUCCESS", items, callLog };
}
