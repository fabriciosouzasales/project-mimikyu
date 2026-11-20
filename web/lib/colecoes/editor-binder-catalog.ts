import {
  CATALOG_ITEM_LIMIT,
  type CatalogFailure,
  type CatalogNovelty,
  type CatalogNoveltyState,
  type CatalogPreview,
  catalogFailureMessage,
  classifyCatalogFailure,
  isCatalogItemKey,
} from "./binder-catalog.ts";

/**
 * V1-13 · E2-3D — novidades do Catálogo pelo EDITOR (5387), só Master Set.
 * Regras puras, sem rede.
 *
 * O servidor é a autoridade: fichário exclusivo de X (C-237), X elegível
 * (5264), conjunto afetado inteiro (destinos e trechos deslocados) de X ou
 * livre, mesmo plano e token `rc1` do titular, limites de 100 novidades e 500
 * itens (C-200). A prévia do EDITOR devolve EM BRANCO o id do fichário, a
 * capacidade, os bolsos livres e a posição de uma barreira que não seja de X;
 * a tela não preenche nada disso.
 *
 * Diferença em relação ao titular: o EDITOR não tem a leitura de novidades da
 * 5265 (nomes, "já no fichário"). A lista vem da própria prévia sem seleção
 * (`p_keys = null`, todas as novidades pendentes) e os nomes vêm da leitura de
 * participante do Master Set (5323) — nada do acervo do titular.
 */

/** Só Master Set recebe novidades do Catálogo. */
export function editorCatalogAvailable(completionPolicy: string | null | undefined): boolean {
  return completionPolicy === "MASTER_SET";
}

export type NoveltyName = { cardName: string; collectorNumber: string | null; variantTypeName: string | null };

/**
 * Lista de novidades a partir da prévia sem seleção: uma por item do plano,
 * na ordem do plano. "Já no fichário" fica DESCONHECIDO (`null`, indicador
 * oculto): o EDITOR não tem essa leitura; a prévia avisa quando a carta já
 * está no bolso certo ou fora da ordem. Sem nome conhecido: "Carta" — nada é
 * inventado.
 */
export function noveltiesFromEditorPreview(preview: CatalogPreview, names: ReadonlyMap<string, NoveltyName>): CatalogNoveltyState {
  if (preview.outcome === "NOT_ELIGIBLE") return { eligible: false, reason: "OTHER" };
  const items: CatalogNovelty[] = [];
  const seen = new Set<string>();
  for (const item of preview.items) {
    if (seen.has(item.itemKey)) continue;
    seen.add(item.itemKey);
    const name = names.get(item.itemKey) ?? names.get(`${item.cardId}:*`) ?? null;
    items.push({
      itemKey: item.itemKey,
      cardId: item.cardId,
      variantTypeId: item.variantTypeId,
      collectorNumber: name?.collectorNumber ?? null,
      cardName: name?.cardName ?? "Carta",
      variantTypeCode: null,
      variantTypeName: name?.variantTypeName ?? null,
      bornAt: null,
      // Desconhecido: nenhuma leitura autorizada do EDITOR informa isso (nem a tela mascarada, nem o acervo do titular).
      placedInBinder: null,
    });
  }
  return { eligible: true, count: items.length, items };
}

/** Nomes por chave de novidade (`carta:acabamento`) a partir das posições de participante (5323). */
export function noveltyNamesFrom(rows: readonly { cardId: string; variantTypeId: string | null; cardName: string; collectorNumber: string | null; finishName: string | null }[]): Map<string, NoveltyName> {
  const names = new Map<string, NoveltyName>();
  for (const r of rows) {
    const value = { cardName: r.cardName, collectorNumber: r.collectorNumber, variantTypeName: r.finishName };
    names.set(`${r.cardId}:${r.variantTypeId ?? "*"}`, value);
    // Novidade genérica da carta (sem acabamento): o primeiro nome da carta serve de rótulo.
    if (!names.has(`${r.cardId}:*`)) names.set(`${r.cardId}:*`, { ...value, variantTypeName: null });
  }
  return names;
}

/** Chaves enviadas: lista explícita, distinta, válida e dentro do limite. */
export function validEditorCatalogKeys(keys: unknown): keys is string[] {
  return Array.isArray(keys) && keys.length >= 1 && keys.length <= CATALOG_ITEM_LIMIT && keys.every(isCatalogItemKey) && new Set(keys).size === keys.length;
}

// ---------------------------------------------------------------------------
// Recusas. Só o código e o NOME da exceção: `hint`/`detail` nunca são lidos
// (a 5387 descreve no hint por que a operação é do titular e quais limites
// excedem). A confirmação faltando só ocorre se o plano mudou depois da
// prévia (a tela envia exatamente as confirmações que a prévia pediu).

export type EditorCatalogFailure = { reason: CatalogFailure; message: string; disables: boolean; recheck: boolean };

export function classifyEditorCatalogFailure(code: string | null | undefined, message: string | null | undefined): EditorCatalogFailure {
  const text = (message ?? "").trim().toUpperCase();
  if (text === "OPERATION_RESERVED_TO_OWNER") {
    return { reason: "not_eligible", message: "Neste fichário, as novidades do Catálogo são incorporadas pelo titular.", disables: false, recheck: false };
  }
  if (text === "CAPABILITY_NOT_ENABLED") return { reason: "unavailable", message: "A organização compartilhada ainda não está disponível.", disables: true, recheck: false };
  if (text === "COLLECTION_NOT_FOUND" || text === "BINDER_NOT_FOUND") return { reason: "not_found", message: "Sua permissão para organizar este fichário mudou.", disables: true, recheck: true };
  if (text === "COLLECTION_ARCHIVED") return { reason: "archived", message: "A coleção está arquivada. O fichário fica só para leitura.", disables: true, recheck: false };
  if (text === "RECONCILE_CONFIRMATION_REQUIRED") return { reason: "plan_changed", message: catalogFailureMessage("plan_changed"), disables: false, recheck: false };
  const reason = classifyCatalogFailure(code, message, null);
  return { reason, message: editorCatalogFailureMessage(reason), disables: reason === "not_authenticated", recheck: false };
}

/** Mensagens do titular, com os casos que falariam do que o EDITOR não controla ajustados. */
export function editorCatalogFailureMessage(reason: CatalogFailure): string {
  switch (reason) {
    case "blocked":
      return "Um bolso fixado ou com imagem está no caminho. Nada foi movido.";
    case "not_eligible":
      return "Este fichário não recebe novidades do Catálogo.";
    case "reference_missing":
      return "A coleção está sem Set ou sem acabamentos no objetivo. Só o titular ajusta o objetivo.";
    case "not_found":
      return "Sua permissão para organizar este fichário mudou.";
    default:
      return catalogFailureMessage(reason);
  }
}

/** Resultado incerto (rede, tempo esgotado, resposta ilegível): a escrita pode ter acontecido. */
export function catalogOutcomeUncertain(reason: CatalogFailure): boolean {
  return reason === "unknown";
}

/** A incorporação deslocou bolsos ou criou páginas? Então o que a tela sabia por posição deixa de valer. */
export function catalogApplyShifted(result: { pocketsMoved: number; pagesAdded: number }): boolean {
  return result.pocketsMoved > 0 || result.pagesAdded > 0;
}
