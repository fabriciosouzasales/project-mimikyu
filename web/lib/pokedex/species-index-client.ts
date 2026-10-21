import { type SpeciesIndexEntry, parseSpeciesIndex } from "./species-search.ts";

/**
 * Índice compacto da Pokédex Nacional no navegador ([número, nome, arte]),
 * servido por `/api/pokedex/species-index` (sem SQL novo, Query 6131/6132).
 *
 * Único carregador para todas as buscas de espécie (busca rápida da ficha e
 * busca/salto da coleção Pokédex — antes duplicado, unificado no UX-08):
 * - uma requisição por aba, compartilhada entre montagens e componentes;
 * - carregado só na primeira intenção de busca, nunca no carregamento da página;
 * - falha não fica em cache: a próxima intenção tenta de novo.
 */
export type SpeciesIndexLoader = {
  /** Índice já carregado nesta aba, ou `null`. */
  cached: () => SpeciesIndexEntry[] | null;
  /** Carrega (uma vez) e devolve o índice; `null` = indisponível agora. */
  load: () => Promise<SpeciesIndexEntry[] | null>;
};

type FetchLike = (input: string, init?: RequestInit) => Promise<{ ok: boolean; json: () => Promise<unknown> }>;

export function createSpeciesIndexLoader(fetchImpl: FetchLike, url = "/api/pokedex/species-index"): SpeciesIndexLoader {
  let request: Promise<SpeciesIndexEntry[] | null> | null = null;
  let cache: SpeciesIndexEntry[] | null = null;

  return {
    cached: () => cache,
    load: () => {
      if (cache) return Promise.resolve(cache);
      if (!request) {
        request = fetchImpl(url, { credentials: "same-origin" })
          .then((response) => (response.ok ? response.json() : null))
          .then((body) => parseSpeciesIndex(body))
          .catch(() => null)
          .then((entries) => {
            if (entries && entries.length > 0) cache = entries;
            else request = null;
            return cache;
          });
      }
      return request;
    },
  };
}

/** Instância da aba — a mesma para todos os componentes de busca. */
export const speciesIndex: SpeciesIndexLoader = createSpeciesIndexLoader((input, init) => fetch(input, init));
