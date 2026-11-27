import type { SpeciesReference } from "./binder-species.ts";
import { type SharedBinderPage, parseSharedBinderPages } from "./sharing.ts";

/**
 * V1-13 · E3-6 / F2 — páginas do fichário compartilhado com as referências de
 * espécie (5393), regras puras, sem rede.
 *
 * A 5393 devolve as mesmas linhas e as mesmas 11 colunas da 5316 + número
 * nacional, nome e arte da espécie (só em bolso EMPTY mascarado da camada da
 * própria coleção, com a exibição ligada) e `references_visible` (constante na
 * resposta; NULL fora da camada). As 11 colunas passam pelo MESMO parser da
 * 5316; as 4 novas só viram rótulo do bolso.
 *
 * Fallback (C2): só configuração desligada, barreira (`CAPABILITY_NOT_ENABLED`)
 * e função ausente voltam à 5316. Sessão expirada, acesso perdido, erro
 * inesperado e resposta inválida são falhas — nunca páginas vazias.
 */

export const SHARED_SPECIES_PAGES_FN = "get_shared_collection_binder_pages_with_species";

/** De onde vieram as páginas de um lote. `visible` = estado da camada (5393); `null` = sem camada desta coleção. */
export type SpeciesSource = { source: "5393"; visible: boolean | null } | { source: "5316" };

/** Recusa que autoriza ler pela 5316: a capacidade não está disponível (barreira) ou a função não existe. Só código + nome. */
export function speciesPagesFallback(code: string | null | undefined, message: string | null | undefined): boolean {
  if (code === "PGRST202" || code === "42883") return true;
  return code === "42501" && (message ?? "").trim() === "CAPABILITY_NOT_ENABLED";
}

function obj(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function int(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

/**
 * Linhas da 5393 → páginas (parser da 5316) + espécie por bolso + estado da
 * camada. Qualquer incoerência → `null` (o lote é rejeitado inteiro):
 *  - campo novo com tipo errado;
 *  - espécie em bolso que não é EMPTY, ou com a exibição diferente de `true`;
 *  - número sem nome, ou nome sem número;
 *  - `references_visible` diferente entre linhas.
 */
export function parseSharedBinderPagesWithSpecies(
  data: unknown,
  columns: number,
  rows: number,
): { pages: SharedBinderPage[]; visible: boolean | null } | null {
  const pages = parseSharedBinderPages(data, columns, rows);
  if (!pages || !Array.isArray(data)) return null;
  let visible: boolean | null | undefined;
  const species = new Map<string, SpeciesReference>();
  for (const raw of data) {
    const r = obj(raw);
    if (!r) return null;
    const v = r.references_visible;
    if (v !== null && v !== undefined && typeof v !== "boolean") return null;
    const rowVisible = v ?? null;
    if (visible === undefined) visible = rowVisible;
    else if (visible !== rowVisible) return null;
    const n = r.species_national_number;
    const name = r.species_name;
    const art = r.species_artwork_path;
    const hasN = n !== null && n !== undefined;
    const hasName = name !== null && name !== undefined;
    if (art !== null && art !== undefined && typeof art !== "string") return null;
    if (!hasN && !hasName) {
      if (art !== null && art !== undefined) return null;
      continue;
    }
    const number = int(n);
    if (number === null || number < 1 || typeof name !== "string" || name.trim() === "") return null;
    if (r.pocket_state !== "EMPTY" || rowVisible !== true) return null;
    species.set(`${r.page_number}:${r.row_index}:${r.column_index}`, {
      nationalNumber: number,
      speciesName: name,
      artworkPath: typeof art === "string" && art !== "" ? art : null,
    });
  }
  return {
    visible: visible ?? null,
    pages: pages.map((page) => ({
      ...page,
      pockets: page.pockets.map((pocket) => {
        const ref = species.get(`${page.pageNumber}:${pocket.row}:${pocket.column}`);
        return ref ? { ...pocket, species: ref } : pocket;
      }),
    })),
  };
}

/** A arte aparece nos bolsos só com páginas da 5393 e a camada visível. */
export function speciesReferencesShown(source: SpeciesSource | null): boolean {
  return source?.source === "5393" && source.visible === true;
}

/** Estado da exibição conhecido pela tela (para o interruptor do EDITOR); `null` = desconhecido. */
export function speciesVisibilityKnown(source: SpeciesSource | null): boolean | null {
  return source?.source === "5393" ? source.visible : null;
}

/**
 * Nova resposta × fonte atual da tela (C2, "não misturar"):
 *  - `keep`: mesma fonte e mesma exibição — o lote vale;
 *  - `adopt`: primeira resposta conhecida — vale e fixa a fonte;
 *  - `reload`: a fonte mudou (5393 → 5316) ou a exibição mudou — o lote é
 *    descartado, o cache esvaziado e tudo relido da fonte nova.
 */
export function speciesSourceTransition(prev: SpeciesSource | null, next: SpeciesSource): "keep" | "adopt" | "reload" {
  if (!prev) return "adopt";
  if (prev.source !== next.source) return "reload";
  if (prev.source === "5393" && next.source === "5393" && prev.visible !== next.visible) return "reload";
  return "keep";
}
