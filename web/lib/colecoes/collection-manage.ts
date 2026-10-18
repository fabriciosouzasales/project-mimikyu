/**
 * Gerenciar uma coleção — regras puras de apresentação
 * (COLLECTION-MANAGEMENT-RECOVERY-01). Sem banco, sem React: testável com
 * `node --test`.
 *
 * Duas capacidades, ambas sobre contratos já no LIVE:
 *
 * - **Tirar da coleção** (N14) — `5047 deallocate_physical_cards_from_collection`.
 *   Remove SÓ o vínculo lógico do exemplar escolhido com esta coleção: a carta
 *   continua no acervo, o registro físico fica intacto, o local físico não muda
 *   e nenhuma outra coleção é tocada (o banco recusa tudo se o exemplar não
 *   estiver nesta coleção).
 * - **Onde guardo** (N24) — `5036 set_collection_default_storage`. Troca o
 *   local padrão da COLEÇÃO; nenhum exemplar muda de lugar (NS-13/NS-15).
 */

/** Liga a interface de gerenciamento (local — publicação após homologação). */
export const COLLECTION_MANAGE_ENABLED = true;

/** Um exemplar físico que está nesta coleção. */
export type CollectionCopy = {
  physicalCardId: string;
  /** Número do exemplar dentro da mesma versão + idioma (estável, vem de 5162). */
  copyNumber: number;
  addedAt: string;
  /** Local físico do exemplar; `null` = sem localização definida (N25). */
  storageName: string | null;
};

/** Uma versão + idioma da carta, com os exemplares dela nesta coleção. */
export type CopyGroup = {
  cardVariantId: string;
  languageCode: string;
  languageName: string;
  variantLabel: string | null;
  isDefaultVariant: boolean;
  copies: CollectionCopy[];
};

/** Linha mínima de 5162 para filtrar pela coleção. */
type CopyRow = {
  physicalCardId: string;
  copyNumber: number;
  addedAt: string;
  storageName: string | null;
  collectionId: string | null;
};

/**
 * Só os exemplares que estão NESTA coleção, em ordem de número. Exemplares
 * livres ou de outra coleção nunca aparecem como retiráveis.
 */
export function copiesInCollection(rows: readonly CopyRow[], collectionId: string): CollectionCopy[] {
  const id = collectionId.toLowerCase();
  return rows
    .filter((row) => row.collectionId !== null && row.collectionId.toLowerCase() === id)
    .map((row) => ({
      physicalCardId: row.physicalCardId,
      copyNumber: row.copyNumber,
      addedAt: row.addedAt,
      storageName: row.storageName,
    }))
    .sort((a, b) => a.copyNumber - b.copyNumber);
}

/** "025" ≡ "25" ≡ "25 "; letras comparadas sem caixa ("TG05" ≡ "tg05"). */
export function sameCollectorNumber(a: string, b: string): boolean {
  const norm = (value: string) => {
    const text = value.trim().toLowerCase();
    return /^\d+$/.test(text) ? String(Number(text)) : text;
  };
  return norm(a) === norm(b);
}

/** Total de exemplares desta coleção em todos os grupos. */
export function totalCopies(groups: readonly CopyGroup[]): number {
  return groups.reduce((sum, group) => sum + group.copies.length, 0);
}

/**
 * Lista depois de tirar um exemplar: remove só aquele `physicalCardId`; grupo
 * que ficar vazio sai da lista. Nenhum outro exemplar é afetado.
 */
export function withoutCopy(groups: readonly CopyGroup[], physicalCardId: string): CopyGroup[] {
  return groups
    .map((group) => ({ ...group, copies: group.copies.filter((copy) => copy.physicalCardId !== physicalCardId) }))
    .filter((group) => group.copies.length > 0);
}

/** Rótulo do exemplar, inequívoco mesmo com várias cópias iguais. */
export function copyTitle(copy: Pick<CollectionCopy, "copyNumber">): string {
  return `Exemplar nº ${copy.copyNumber}`;
}

/** Local físico em linguagem de colecionador (N24/N25). */
export function storageLabel(storageName: string | null): string {
  const name = storageName?.trim();
  return name ? `Guardado em ${name}` : "Sem localização definida";
}

/** Data curta pt-BR ("12/10/2026"); vazio se inválida. */
export function addedLabel(addedAt: string): string {
  const date = new Date(addedAt);
  if (Number.isNaN(date.getTime())) return "";
  return `Registrado em ${date.toLocaleDateString("pt-BR", { timeZone: "UTC" })}`;
}

/** Versão + idioma em uma linha ("Reverse Holo · Português"). */
export function groupLabel(group: Pick<CopyGroup, "variantLabel" | "isDefaultVariant" | "languageName">): string {
  const variant = group.isDefaultVariant ? "Versão padrão" : group.variantLabel?.trim() || "Outra versão";
  return `${variant} · ${group.languageName}`;
}

/**
 * Efeito no progresso de uma coleção de Set ao tirar um exemplar: a carta só
 * deixa de contar quando era o ÚLTIMO exemplar dela na coleção (o banco
 * recalcula; aqui é só o aviso antes de confirmar).
 */
export function removalAffectsProgress(kind: "card_set" | "free", copiesOfCardInCollection: number): boolean {
  return kind === "card_set" && copiesOfCardInCollection === 1;
}
