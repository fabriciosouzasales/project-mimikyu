/**
 * V1-14 F2-3 (D7 §4q) — "Composição da coleção" para Pokédex e Coleção livre. Regras puras, sem banco.
 *
 * Unidade = EXEMPLAR FÍSICO alocado à coleção consultada (não espécie, não posição, não carta editorial,
 * não objetivo). Base = os mesmos grupos variante + idioma do Valor estimado da coleção (5159 com
 * `p_collection_id`, `SET_NUMBER`). Motor = o MESMO da R1-H (`buildSetInventoryReport` →
 * `buildDistributionReport`), sem preços: mesmas faixas, mesma raridade da CARTA por `rarity_code`
 * (nomes e ordem da 5355; códigos com o mesmo nome nunca mesclados), mesmo idioma (código e nome da
 * 5159), mesma ordem dos Sets (exemplares ↓, ordem canônica do inventário, código) e mesmos textos de
 * percentual. Nenhuma regra paralela de composição.
 *
 * Conferência (além da própria R1-H — Σ por dimensão = total da leitura): leitura sem grupo repetido e
 * com páginas estáveis; total de exemplares da 5159 = `copies_count` do resumo canônico da coleção
 * (5332). Qualquer divergência → incompleto com motivo e impressão bloqueada; nada é estimado.
 */
import { type SetInventoryItemInput, buildSetInventoryReport } from "./acervo-set-inventory.ts";
import { COLLECTION_VALUE_MAX_GROUPS, type CollectionValueReadCheck } from "./collection-value.ts";
import { type DistributionReport, type RarityCatalogInput, buildDistributionReport } from "./distribution.ts";

export const COLLECTION_COMPOSITION_TITLE = "Composição da coleção";

export type CompositionKind = "POKEDEX" | "FREE";

export type CompositionIncompleteReason = "too_large" | "read" | "mismatch" | "rarity_unknown" | "rarity_unavailable";

export type CollectionCompositionReport = {
  /** Distribuição da R1-H restrita à coleção (sem valores: nenhum preço é lido). */
  distribution: DistributionReport;
  /** Exemplares físicos alocados (o universo das três perspectivas). */
  copies: number;
  /** Grupos variante + idioma (complementar; nunca somado aos exemplares). */
  items: number;
  sets: number;
  /** Raridades presentes (códigos; "Sem raridade definida" não conta) — mesma contagem da R1-H. */
  rarities: number;
  languages: number;
  complete: boolean;
  incompleteReason: CompositionIncompleteReason | null;
};

export function compositionKindOf(completionPolicy: string | null | undefined): CompositionKind | null {
  if (completionPolicy === "REFERENCE_POSITION") return "POKEDEX";
  if (completionPolicy === "NONE") return "FREE";
  return null;
}

export function buildCollectionCompositionReport(input: {
  /** Grupos da 5159 (coleção autorizada), na ordem lida. */
  items: readonly SetInventoryItemInput[];
  read: CollectionValueReadCheck;
  /** `copies_count` do resumo canônico (5332). */
  collectionCopies: number;
  rarities: RarityCatalogInput;
}): CollectionCompositionReport {
  const { read } = input;
  const tooLarge = read.totalCount > COLLECTION_VALUE_MAX_GROUPS;
  const inventory = buildSetInventoryReport({
    summary: { totalCopies: read.totalCopies, distinctItems: read.totalCount, distinctSets: new Set(input.items.map((i) => i.cardSetCode)).size, duplicateCopies: 0 },
    items: input.items,
    prices: new Map(),
    itemsComplete: !tooLarge,
  });
  const distribution = buildDistributionReport({ inventory, unavailable: new Set(), rarities: input.rarities });

  const r = distribution.incompleteReason;
  const incompleteReason: CompositionIncompleteReason | null = tooLarge
    ? "too_large"
    : read.duplicate || read.inconsistentPages
      ? "read"
      : r === "mismatch" || read.totalCopies !== input.collectionCopies
        ? "mismatch"
        : r === "rarity_unknown"
          ? "rarity_unknown"
          : r === "rarity_unavailable"
            ? "rarity_unavailable"
            : null;

  return {
    distribution,
    copies: distribution.totalCopies,
    items: distribution.distinctItems,
    sets: distribution.sets.bands.length,
    rarities: distribution.rarityCount,
    languages: distribution.languages.bands.length,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

// ---------------------------------------------------------------------------------------------
// Textos (pt-BR)
// ---------------------------------------------------------------------------------------------

export function compositionIncompleteText(reason: CompositionIncompleteReason | null): string | null {
  switch (reason) {
    case null:
      return null;
    case "too_large":
      return "Relatório incompleto: a coleção tem mais itens do que esta versão consegue ler. A impressão fica indisponível.";
    case "read":
      return "Relatório incompleto: a leitura dos exemplares não fechou (a coleção mudou durante a leitura?). Tente novamente; nada foi alterado.";
    case "mismatch":
      return "Relatório incompleto: as contagens não conferem com o total de exemplares da coleção. Tente novamente; nada foi alterado.";
    case "rarity_unknown":
      return "Relatório incompleto: há exemplares com uma raridade que não está no catálogo de raridades. A impressão fica indisponível.";
    case "rarity_unavailable":
      return "Relatório incompleto: o catálogo de raridades não pôde ser carregado agora. Feche e abra o relatório de novo em instantes.";
  }
}

export function compositionNotes(kind: CompositionKind, satisfiedSpecies: number | null): string[] {
  const notes = [
    "Contagem por exemplar físico alocado a esta coleção: cópias da mesma carta contam uma a uma; exemplares de outras coleções ou só disponíveis no acervo ficam fora. Cada perspectiva soma o mesmo total.",
    "Participação = parte dos exemplares desta coleção — não é completude nem objetivo atendido. Percentuais com uma casa, truncados; podem não somar exatamente 100,0%.",
    "Raridade da carta, conforme o catálogo, na ordem oficial (uma variante herda a raridade da sua carta); raridades diferentes com o mesmo nome aparecem com o código ao lado. Idioma = o registrado em cada exemplar.",
  ];
  if (kind === "POKEDEX") {
    const species = satisfiedSpecies === null ? "" : ` Hoje ${satisfiedSpecies === 1 ? "1 espécie está atendida" : `${new Intl.NumberFormat("pt-BR").format(satisfiedSpecies)} espécies estão atendidas`} nesta Pokédex.`;
    notes.push(`Espécie, carta e exemplar são grandezas diferentes: várias cópias podem atender a mesma espécie, e aqui cada cópia conta.${species}`);
  } else {
    notes.push("Coleção livre: sem objetivo de completude — o relatório mostra só como os exemplares estão distribuídos.");
  }
  return notes;
}
