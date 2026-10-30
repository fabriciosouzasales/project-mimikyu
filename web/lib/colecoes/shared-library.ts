import { resolveFinish } from "./binder-finish.ts";
import { collectionHref } from "./colecoes.ts";
import type { CollectionSummary } from "./colecoes-queries.ts";
import { type SharedWithMe, sharedCollectionHref } from "./sharing.ts";

/**
 * Coleções compartilhadas dentro da Biblioteca (V1-12 — ajuste final de UX de
 * Minhas coleções). A coleção que alguém compartilhou com você é uma coleção
 * normal da sua estante: mesmo fichário, mesmo progresso, mesmos três modos.
 * A única diferença visível é um selo discreto ("Compartilhada") e o titular
 * na metadata ("de Fulano"). Regras puras — a autorização continua no banco
 * (5311/5312/5328 só respondem a participante ACTIVE).
 */

/** Chave sintética da capa enviada da coleção compartilhada no mapa de logos assinados. */
export function sharedCoverKey(collectionId: string): string {
  return `shared-cover:${collectionId}`;
}

/**
 * Item de "Compartilhadas com você" (5311) no formato do card da Biblioteca.
 * A identidade da placa (logo do Set ou capa enviada) é preenchida depois, por
 * `withSharedIdentity`, só para os itens exibidos na página.
 */
export function sharedLibraryItem(shared: SharedWithMe): CollectionSummary {
  const total = shared.progress?.total ?? 0;
  const satisfied = shared.progress?.satisfied ?? 0;
  return {
    id: shared.collectionId,
    name: shared.name,
    completionPolicy: shared.completionPolicy ?? "NONE",
    lifecycleStatus: shared.archived ? "ARCHIVED" : "ACTIVE",
    cardSetCode: shared.cardSetCode,
    cardSetName: shared.cardSetName,
    cardSetLogoPath: null,
    coverLogoPath: null,
    coverCode: null,
    finish: resolveFinish(shared.collectionId, shared.coverFinish),
    finishEditable: false,
    totalPositions: total,
    satisfiedPositions: satisfied,
    isComplete: shared.progress?.complete ?? false,
    copiesCount: shared.copies,
    coverImagePath: null,
    createdAt: "",
    sharedBy: shared.ownerDisplayName,
  };
}

/** Identidade da placa lida para a coleção compartilhada (5312: logo do Set; 5328: capa enviada e código). */
export type SharedIdentity = { cardSetLogoPath: string | null; coverUrl: string | null; coverCode: string | null };

/**
 * Aplica a identidade lida. Mesma precedência do card do titular
 * (`plateLogoKey`): logo do Set primeiro; capa enviada só sem Set. A capa já
 * vem assinada (URL curta para terceiros), então entra no mapa com chave
 * sintética.
 */
export function withSharedIdentity(
  item: CollectionSummary,
  identity: SharedIdentity | undefined,
): { item: CollectionSummary; coverUrl: [string, string] | null } {
  if (!identity) return { item, coverUrl: null };
  const coverLogoPath = !identity.cardSetLogoPath && identity.coverUrl ? sharedCoverKey(item.id) : null;
  return {
    item: { ...item, cardSetLogoPath: identity.cardSetLogoPath, coverLogoPath, coverCode: identity.coverCode },
    coverUrl: coverLogoPath && identity.coverUrl ? [coverLogoPath, identity.coverUrl] : null,
  };
}

/**
 * Uma estante só: as coleções próprias (paginadas no banco, na ordem do
 * colecionador) e, depois delas, as compartilhadas (até 100, mais recentes
 * primeiro). Para a página `pageNumber`, devolve que fatia das compartilhadas
 * completa a página e o total combinado.
 */
export function sharedLibrarySlice(args: {
  ownedTotal: number;
  ownedOnPage: number;
  sharedCount: number;
  pageNumber: number;
  pageSize: number;
}): { offset: number; count: number; total: number } {
  const { ownedTotal, ownedOnPage, sharedCount, pageSize } = args;
  const pageNumber = Math.max(1, Math.trunc(args.pageNumber));
  const total = ownedTotal + sharedCount;
  const offset = Math.max(0, (pageNumber - 1) * pageSize - ownedTotal);
  const room = Math.max(0, pageSize - ownedOnPage);
  const count = Math.max(0, Math.min(room, sharedCount - offset));
  return { offset, count, total };
}

/** Destino do card: a coleção própria ou a página da coleção compartilhada (só leitura). */
export function libraryItemHref(collection: Pick<CollectionSummary, "id" | "sharedBy">): string {
  return collection.sharedBy ? sharedCollectionHref(collection.id) : collectionHref(collection.id);
}

/** Texto discreto de propriedade, para a metadata e o nome acessível do card. */
export function sharedOwnerText(collection: Pick<CollectionSummary, "sharedBy">): string | null {
  return collection.sharedBy ? `de ${collection.sharedBy}` : null;
}
