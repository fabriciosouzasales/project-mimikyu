/**
 * V1-07 — reservar um bolso VAZIO para uma carta escolhida (C-42: reserva =
 * Expected Content). Regras puras; sem banco.
 *
 * A gravação é a operação canônica de reserva (5128 `set_slot_expected_content`,
 * a mesma do "Reservar este bolso para a carta" e da montagem), agora com a
 * coleção da reserva informada (`p_collection_id`). O banco continua sendo a
 * fronteira: dono do fichário, coleção = proprietária OU convidada DESTE
 * fichário, do mesmo dono e ativa (senão recusa); acabamento do mesmo jogo,
 * variante ativa e os gatilhos "reserva fora de mesclagem" e "reserva sem
 * imagem personalizada".
 *
 * Decisões (V1-07 IMPLEMENTATION-01; D3 revisada em INVITED COLLECTION
 * RESERVATION CORRECTION-01):
 * - D1 origem das cartas, pelo tipo da coleção ESCOLHIDA: Set padrão e Master Set
 *   → posições do objetivo (5169 / 5189-5198, inclusive as que faltam); coleção
 *   livre → busca no catálogo (`search_cards`); Pokédex → fora da escolha (a
 *   reserva exige carta e não há leitura de catálogo por espécie — nada é inferido).
 * - D2 granularidade: Set padrão e livre = carta; Master Set = carta + acabamento
 *   da posição (a posição secreta, "Qualquer acabamento", fica só carta).
 * - D3 (revisada): a reserva pertence à coleção escolhida entre as coleções
 *   vinculadas ao fichário (5246 `get_my_binder_participants`: proprietária e
 *   convidadas) que estão ativas e aceitam reserva por carta. Substitui a D3
 *   original ("sempre a proprietária"), que impedia planejar no mesmo fichário
 *   as cartas das convidadas. Trocar mantém a coleção original da reserva.
 * - D4 só bolso vazio recebe "Reservar para uma carta…"; bolso ocupado mantém
 *   "Reservar este bolso para a carta" (a carta presente).
 * - D5 a mesma carta pode ser reservada em mais de um bolso — aviso, sem bloqueio
 *   (conta só reservas da mesma coleção).
 */
import type { BinderCardFace, BinderSlot } from "./binder.ts";

export type ReserveScope = "STANDARD_SET" | "MASTER_SET" | "FREE";

/** Política de completude → escopo da reserva; `null` = a ação não é oferecida (Pokédex e desconhecidas). */
export function reserveScopeOf(completionPolicy: string | null | undefined): ReserveScope | null {
  if (completionPolicy === "STANDARD_SET") return "STANDARD_SET";
  if (completionPolicy === "MASTER_SET") return "MASTER_SET";
  if (completionPolicy === "NONE") return "FREE";
  return null;
}

/** Tipo da coleção no cabeçalho do fichário (5223) → escopo; mesma regra de `reserveScopeOf`. */
export function reserveScopeOfKind(kind: string | null | undefined): ReserveScope | null {
  if (kind === "SET") return "STANDARD_SET";
  if (kind === "MASTER_SET") return "MASTER_SET";
  if (kind === "FREE") return "FREE";
  return null;
}

/** Uma carta (ou posição) que pode ser reservada. */
export type ReserveCandidate = {
  /** Identidade da escolha (carta, ou carta + acabamento no Master Set). */
  key: string;
  cardId: string;
  /** Master Set: acabamento da posição; `null` = só carta. */
  variantTypeId: string | null;
  finishName: string | null;
  cardName: string;
  collectorNumber: string | null;
  collectorTotal: number | null;
  setCode: string | null;
  setName: string | null;
  imagePath: string | null;
  /** Set/Master Set: a posição já está satisfeita na coleção (só informativo). */
  owned: boolean | null;
};

/** Coleção vinculada ao fichário que pode receber reserva por carta. */
export type ReserveTarget = {
  collectionId: string;
  name: string;
  role: "OWNER" | "GUEST";
  scope: ReserveScope;
};

/** Coleção vinculada que NÃO entra na escolha (informativo no seletor). */
export type ReserveExcluded = { collectionId: string; name: string; reason: "pokedex" | "archived" | "unknown" };

/**
 * Coleções do fichário (5246) + política de cada uma (`get_my_collections`) →
 * destinos possíveis. Só ativas e com escopo; proprietária primeiro, depois as
 * convidadas por nome. Nenhuma coleção fora da lista do fichário entra.
 */
export function reserveTargetsFrom(
  participants: readonly { collectionId: string; name: string; role: "OWNER" | "GUEST"; active: boolean }[],
  policies: ReadonlyMap<string, string | null>,
): { targets: ReserveTarget[]; excluded: ReserveExcluded[] } {
  const targets: ReserveTarget[] = [];
  const excluded: ReserveExcluded[] = [];
  const seen = new Set<string>();
  for (const p of participants) {
    const id = p.collectionId.toLowerCase();
    if (seen.has(id)) continue;
    seen.add(id);
    const policy = policies.has(id) ? policies.get(id) : policies.get(p.collectionId);
    const scope = reserveScopeOf(policy);
    if (!p.active) excluded.push({ collectionId: id, name: p.name, reason: "archived" });
    else if (scope === null) excluded.push({ collectionId: id, name: p.name, reason: policy === "REFERENCE_POSITION" ? "pokedex" : "unknown" });
    else targets.push({ collectionId: id, name: p.name, role: p.role, scope });
  }
  targets.sort((a, b) => (a.role === b.role ? a.name.localeCompare(b.name, "pt-BR", { sensitivity: "base", numeric: true }) : a.role === "OWNER" ? -1 : 1));
  return { targets, excluded };
}

/** Contexto do fichário em que a ação aparece. */
export type ReserveContext = {
  editable: boolean;
  /** Coleção pela qual o fichário está aberto. */
  collectionId: string;
  ownerCollectionId: string | null;
  /** Escopo da coleção aberta — só vale enquanto as coleções do fichário não foram lidas. */
  scope: ReserveScope | null;
  /** Destinos lidos do fichário (5246); `null` = ainda não lidos (ou leitura falhou). */
  targets?: readonly ReserveTarget[] | null;
};

const same = (a: string | null | undefined, b: string | null | undefined) => !!a && !!b && a.toLowerCase() === b.toLowerCase();

/** O fichário permite reservar para uma carta escolhida? */
export function reserveContextOk(ctx: ReserveContext): boolean {
  if (!ctx.editable || ctx.ownerCollectionId === null) return false;
  if (ctx.targets) return ctx.targets.length > 0;
  // Antes de ler as coleções do fichário: só o caso seguro e conhecido (aberto pela proprietária, com escopo).
  return ctx.scope !== null && same(ctx.ownerCollectionId, ctx.collectionId);
}

/** Coleção dona de uma reserva (sem registro = proprietária, 5128 D8). */
export function reservationCollectionOf(slot: Pick<BinderSlot, "expectedCollectionId">, ownerCollectionId: string): string {
  return (slot.expectedCollectionId ?? ownerCollectionId).toLowerCase();
}

/** A coleção pode receber reserva por carta neste fichário? */
export function isReserveTarget(ctx: ReserveContext, collectionId: string): boolean {
  if (ctx.targets) return ctx.targets.some((t) => same(t.collectionId, collectionId));
  return ctx.scope !== null && same(ctx.ownerCollectionId, collectionId) && same(ctx.ownerCollectionId, ctx.collectionId);
}

/**
 * Qual ação o bolso oferece:
 * - "reserve": vazio de verdade — sem carta, sem reserva, sem imagem, fora de mesclagem
 *   (bolso travado e vazio pode: a trava é independente da reserva, C-43);
 * - "change": reservado e vazio, com reserva de uma coleção que pode receber reserva
 *   (a troca fica na coleção original);
 * - `null`: nada (ocupado, imagem, mesclagem, reserva de coleção fora da escolha, contexto não editável).
 */
export function reserveForMode(
  slot: Pick<BinderSlot, "state" | "expectedCardId" | "expectedCollectionId" | "presentCardId" | "image" | "regionId">,
  ctx: ReserveContext,
): "reserve" | "change" | null {
  if (!reserveContextOk(ctx) || !ctx.ownerCollectionId) return null;
  if (slot.image || slot.regionId || slot.presentCardId) return null;
  if (slot.state === "EMPTY" && slot.expectedCardId === null) return "reserve";
  if (slot.state === "RESERVED_EMPTY" && slot.expectedCardId !== null) {
    return isReserveTarget(ctx, reservationCollectionOf(slot, ctx.ownerCollectionId)) ? "change" : null;
  }
  return null;
}

/**
 * Coleção inicial do seletor: na troca, a da reserva; ao reservar, a última
 * escolhida neste fichário (se ainda vale), senão a aberta, senão a proprietária.
 */
export function initialReserveCollection(input: {
  mode: "reserve" | "change";
  slot: Pick<BinderSlot, "expectedCollectionId">;
  targets: readonly ReserveTarget[];
  remembered: string | null;
  openingCollectionId: string;
  ownerCollectionId: string;
}): string | null {
  const has = (id: string | null) => (id ? input.targets.find((t) => same(t.collectionId, id))?.collectionId ?? null : null);
  if (input.mode === "change") return has(reservationCollectionOf(input.slot, input.ownerCollectionId));
  return has(input.remembered) ?? has(input.openingCollectionId) ?? has(input.ownerCollectionId) ?? input.targets[0]?.collectionId ?? null;
}

/** Mesma identidade de reserva (carta; e acabamento, quando a escolha tem acabamento). */
export function sameReservation(
  slot: Pick<BinderSlot, "expectedCardId" | "expectedVariantTypeId">,
  candidate: Pick<ReserveCandidate, "cardId" | "variantTypeId">,
): boolean {
  if (!slot.expectedCardId || slot.expectedCardId.toLowerCase() !== candidate.cardId.toLowerCase()) return false;
  if (candidate.variantTypeId === null) return true;
  return (slot.expectedVariantTypeId ?? null)?.toLowerCase() === candidate.variantTypeId.toLowerCase();
}

/**
 * D5: outros bolsos JÁ CARREGADOS deste fichário com a mesma reserva, da mesma coleção (sem leitura
 * nova — páginas não carregadas não entram; o aviso é informativo).
 */
export function duplicateReservationCount(
  slots: readonly Pick<BinderSlot, "slotId" | "expectedCardId" | "expectedVariantTypeId" | "expectedCollectionId">[],
  candidate: Pick<ReserveCandidate, "cardId" | "variantTypeId">,
  exceptSlotId: string,
  /** Coleção que receberá a reserva; reservas de outras coleções não contam. */
  collectionId: string,
  ownerCollectionId: string,
): number {
  return slots.filter(
    (slot) =>
      slot.slotId !== exceptSlotId &&
      sameReservation(slot, candidate) &&
      same(reservationCollectionOf(slot, ownerCollectionId), collectionId),
  ).length;
}

export const DUPLICATE_RESERVATION_WARNING =
  "Esta carta já possui outra reserva neste fichário. Reservas duplicadas podem gerar ambiguidade na organização automática.";

function fold(value: string): string {
  return value.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
}

/** Busca local nas posições do objetivo: nome, número ("25", "025", "25/88") ou acabamento. */
export function filterCandidates(candidates: readonly ReserveCandidate[], query: string): ReserveCandidate[] {
  const q = fold(query);
  if (q === "") return [...candidates];
  const numberQuery = q.split("/")[0]!.replace(/^0+/, "");
  return candidates.filter((c) => {
    if (fold(c.cardName).includes(q)) return true;
    if (c.finishName && fold(c.finishName).includes(q)) return true;
    const number = (c.collectorNumber ?? "").replace(/^0+/, "").toLowerCase();
    return numberQuery !== "" && /^\d/.test(numberQuery) && number === numberQuery;
  });
}

/** Posição do objetivo (linha do checklist) → candidata, na granularidade D2. */
export function candidateFromPosition(
  scope: "STANDARD_SET" | "MASTER_SET",
  row: { key: string; cardId?: string; number: string; name: string; finish: string | null; owned: boolean; imagePath?: string | null },
  set: { code: string | null; name: string | null; total: number | null },
): ReserveCandidate | null {
  if (!row.cardId) return null;
  let variantTypeId: string | null = null;
  if (scope === "MASTER_SET") {
    const suffix = row.key.slice(row.key.indexOf(":") + 1);
    variantTypeId = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(suffix) ? suffix.toLowerCase() : null;
  }
  return {
    key: row.key,
    cardId: row.cardId,
    variantTypeId,
    finishName: scope === "MASTER_SET" ? row.finish : null,
    cardName: row.name,
    collectorNumber: row.number || null,
    collectorTotal: set.total,
    setCode: set.code,
    setName: set.name,
    imagePath: row.imagePath ?? null,
    owned: row.owned,
  };
}

/** Prévia otimista do bolso depois de reservar (a releitura do servidor confirma). */
export function applyReserveFor(slot: BinderSlot, candidate: ReserveCandidate, collectionId: string): BinderSlot {
  const face: BinderCardFace = {
    cardName: candidate.cardName,
    collectorNumber: candidate.collectorNumber,
    collectorTotal: candidate.collectorTotal,
    setCode: candidate.setCode,
    imagePath: candidate.imagePath,
    finishCode: null,
    finishName: candidate.finishName,
  };
  return {
    ...slot,
    state: "RESERVED_EMPTY",
    expected: face,
    expectedCardId: candidate.cardId,
    expectedCardVariantId: null,
    expectedVariantTypeId: candidate.variantTypeId,
    expectedCollectionId: collectionId.toLowerCase(),
  };
}
