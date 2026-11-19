import type { BinderPage, BinderSlot } from "./binder.ts";
import { applyMove, applyRemove, isOccupied } from "./binder.ts";
import type { AvailableCard } from "./binder-share.ts";
import { applyPlaceAvailable } from "./binder-share.ts";

/**
 * V1-13 · E2-1 — curadoria do fichário compartilhado pelo EDITOR (colocar,
 * mover/trocar, retirar). Regras puras, sem rede.
 *
 * Fronteira: a tela NUNCA decide autorização (C-234). O que está aqui só
 * escolhe o que mostrar e como reagir à resposta do servidor (5373/5374), que
 * classifica cada bolso sob trava (C-237) e recusa sem revelar conteúdo de
 * terceiros (C-243).
 */

/**
 * D1 (E2-1): habilitação da curadoria compartilhada no frontend, DESLIGADA por
 * padrão. Lida só no servidor (`MMKYU_V113_EDITOR_CURATION=on`). Ligada, apenas
 * mostra os controles a quem o servidor identifica como EDITOR; não abre a
 * barreira (5389) nem substitui a autorização de cada chamada.
 */
export const EDITOR_CURATION_ENV = "MMKYU_V113_EDITOR_CURATION";

export function editorCurationFlagOn(env: Record<string, string | undefined>): boolean {
  return env[EDITOR_CURATION_ENV]?.trim().toLowerCase() === "on";
}

/** Papel do participante lido da 5312 (5368: `role`). Só EDITOR/VIEWER interessam aqui. */
export type MemberRole = "EDITOR" | "VIEWER";

/** Os controles de escrita aparecem? Configuração ligada + papel EDITOR + coleção ativa. */
export function canShowEditorCuration(input: { flagOn: boolean; role: MemberRole | null; archived: boolean }): boolean {
  return input.flagOn && input.role === "EDITOR" && !input.archived;
}

// ---------------------------------------------------------------------------
// Posição do bolso: a leitura compartilhada (5315) não expõe ids internos; o
// bolso é identificado pela posição na grade, como nas escritas do EDITOR.

export type PocketPosition = { page: number; row: number; column: number };

/** `shared:<página>:<linha>:<coluna>` (formato de `sharedPageToBinderPage`) → posição. */
export function sharedSlotPosition(slotId: string): PocketPosition | null {
  const match = /^shared:(\d{1,6}):(\d{1,2}):(\d{1,2})$/.exec(slotId);
  if (!match) return null;
  const [page, row, column] = [Number(match[1]), Number(match[2]), Number(match[3])];
  if (page < 1 || row < 1 || column < 1 || row > 10 || column > 10) return null;
  return { page, row, column };
}

export function isPocketPosition(value: unknown): value is PocketPosition {
  if (!value || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  const ok = (n: unknown, max: number) => typeof n === "number" && Number.isInteger(n) && n >= 1 && n <= max;
  return ok(v.page, 100000) && ok(v.row, 10) && ok(v.column, 10);
}

// ---------------------------------------------------------------------------
// Lista de exemplares elegíveis (5373): só o que o titular já alocou a esta
// coleção E guardou no próprio fichário, ainda sem bolso. Nada de local,
// condição, outros exemplares ou contagens fora da lista.

export const PLACEABLE_PAGE_SIZE = 96;

/**
 * Lista vazia ≠ nada a colocar. A 5373 devolve ZERO linhas, sem erro, também
 * quando a capacidade está fechada pela barreira, quando o papel mudou ou a
 * coleção foi arquivada (não enumera). Só se afirma "Tudo no lugar" quando
 * a curadoria já foi comprovada nesta tela: uma leitura que trouxe cartas ou
 * uma escrita aceita pelo servidor. Antes disso, texto neutro — sem consultar
 * a barreira e sem dizer por que a lista está vazia.
 */
export function placeableEmptyState(curationConfirmed: boolean): { title: string; text: string } {
  return curationConfirmed
    ? { title: "Tudo no lugar", text: "Todas as cartas desta coleção guardadas neste fichário já estão nos bolsos." }
    : { title: "Nenhuma carta para mostrar agora", text: "Aqui aparecem as cartas desta coleção guardadas neste fichário e ainda sem bolso, quando estiverem disponíveis para organizar." };
}

export function parsePlaceableCards(data: unknown): { items: AvailableCard[]; total: number } | null {
  if (!Array.isArray(data)) return null;
  const items: AvailableCard[] = [];
  let total = 0;
  for (const row of data) {
    if (!row || typeof row !== "object") return null;
    const r = row as Record<string, unknown>;
    const id = typeof r.physical_card_id === "string" && /^[0-9a-f-]{36}$/i.test(r.physical_card_id) ? r.physical_card_id.toLowerCase() : null;
    const name = typeof r.card_name === "string" && r.card_name.trim() !== "" ? r.card_name : null;
    if (!id || !name) return null;
    const totalCount = Number(r.total_count);
    if (Number.isInteger(totalCount) && totalCount > total) total = totalCount;
    items.push({
      allocationId: null,
      physicalCardId: id,
      // A 5373 não expõe ids de carta/acabamento: a lista é só apresentação; o servidor revalida tudo.
      cardId: "",
      variantTypeId: null,
      cardName: name,
      collectorNumber: typeof r.collector_number === "string" ? r.collector_number : null,
      collectorTotal: Number.isInteger(r.collector_total) ? (r.collector_total as number) : null,
      setCode: typeof r.card_set_code === "string" ? r.card_set_code : null,
      variantLabel: typeof r.variant_label === "string" ? r.variant_label : null,
      languageCode: typeof r.language_code === "string" ? r.language_code : null,
      imagePath: typeof r.image_path === "string" ? r.image_path : null,
      originKind: "THIS",
      originCollectionId: null,
      originCollectionName: null,
      originArchived: false,
    });
  }
  return { items, total: Math.max(total, items.length) };
}

// ---------------------------------------------------------------------------
// Recusas do servidor (5374 + barreira 5389) → motivo estável → mensagem
// neutra. Nenhuma mensagem descreve o que ocupa um bolso nem onde um exemplar
// está (C-237, C-243).

export type EditorFailure =
  | "not_editable"
  | "not_eligible"
  | "already_placed"
  | "source_empty"
  | "locked"
  | "archived"
  | "lock_busy"
  | "capability_closed"
  | "access_lost"
  | "not_authenticated"
  | "disabled"
  | "invalid"
  | "unknown";

export function classifyEditorFailure(code: string | null | undefined, message: string | null | undefined): EditorFailure {
  const text = (message ?? "").trim().toUpperCase();
  if (text === "CAPABILITY_NOT_ENABLED") return "capability_closed";
  if (code === "55P03") return "lock_busy";
  if (code === "28000" || text.includes("AUTHENTICATION REQUIRED")) return "not_authenticated";
  if (text === "SLOT_NOT_EDITABLE") return "not_editable";
  if (text === "PHYSICAL_CARD_NOT_ELIGIBLE") return "not_eligible";
  if (text === "CARD_ALREADY_PLACED") return "already_placed";
  if (text === "SLOT_EMPTY") return "source_empty";
  if (text === "SLOT_LOCKED") return "locked";
  if (text === "COLLECTION_ARCHIVED") return "archived";
  // VIEWER, ex-membro, papel trocado, convite pendente, estranho: o servidor responde igual (não enumera).
  if (text === "COLLECTION_NOT_FOUND" || text === "BINDER_NOT_FOUND") return "access_lost";
  if (text === "INVALID_ARGUMENT" || text === "INVALID_PAGE" || code === "22023" || code === "22P02") return "invalid";
  return "unknown";
}

export function editorFailureMessage(reason: EditorFailure): string {
  switch (reason) {
    case "not_editable":
      return "Esse bolso não pode ser alterado por aqui. Ele é organizado pelo titular.";
    case "not_eligible":
      return "Essa carta não está disponível para este fichário.";
    case "already_placed":
      return "Essa carta já tem lugar no fichário. Atualizamos a página.";
    case "source_empty":
      return "Essa carta já não está mais naquele bolso. Atualizamos a página.";
    case "locked":
      return "Esse bolso está fixado.";
    case "archived":
      return "A coleção está arquivada. O fichário fica só para leitura.";
    case "lock_busy":
      return "O fichário está sendo atualizado em outra tela. Tente de novo em alguns segundos.";
    case "capability_closed":
    case "disabled":
      return "A organização compartilhada ainda não está disponível.";
    case "access_lost":
      return "Sua permissão para organizar este fichário mudou.";
    case "not_authenticated":
      return "Sua sessão terminou. Entre de novo para continuar.";
    case "invalid":
      return "Não foi possível entender o pedido. Recarregue a página e tente de novo.";
    default:
      return "Não foi possível concluir agora. Nada foi alterado — tente de novo em instantes.";
  }
}

/** Depois desta recusa a edição é desligada nesta tela (nenhuma nova escrita é oferecida). */
export function editorFailureDisablesEditing(reason: EditorFailure): boolean {
  return reason === "capability_closed" || reason === "access_lost" || reason === "archived" || reason === "disabled" || reason === "not_authenticated";
}

/** Depois desta recusa a tela relê a coleção (o papel pode ter mudado ou o acesso terminado). */
export function editorFailureRechecksAccess(reason: EditorFailure): boolean {
  return reason === "access_lost";
}

// ---------------------------------------------------------------------------
// Atualização otimista (espelho local; a tela relê o lote logo depois).

/** Bolso pode RECEBER uma carta escolhida pela tela? (A palavra final é do servidor.) */
export function editorCanTarget(slot: BinderSlot): boolean {
  return !slot.locked && !slot.image && !slot.regionId;
}

/** Bolso tem carta desta coleção visível para mover/retirar? */
export function editorCanPick(slot: BinderSlot): boolean {
  return isOccupied(slot) && editorCanTarget(slot);
}

export type SlotPatch = Map<string, BinderSlot>;

export function patchPlace(slot: BinderSlot, card: AvailableCard): SlotPatch {
  return new Map([[slot.slotId, applyPlaceAvailable(slot, card)]]);
}

export function patchMove(from: BinderSlot, to: BinderSlot): SlotPatch {
  const [nextFrom, nextTo] = applyMove(from, to);
  return new Map([
    [from.slotId, nextFrom],
    [to.slotId, nextTo],
  ]);
}

export function patchRemove(slot: BinderSlot): SlotPatch {
  return new Map([[slot.slotId, applyRemove(slot)]]);
}

/** Aplica um patch ao cache de páginas; devolve o cache novo e o anterior de cada bolso tocado (para reverter). */
export function applyPatch(cache: Map<number, BinderPage>, patch: SlotPatch): { cache: Map<number, BinderPage>; previous: SlotPatch } {
  const previous: SlotPatch = new Map();
  const next = new Map(cache);
  for (const [number, page] of cache) {
    if (!page.slots.some((slot) => patch.has(slot.slotId))) continue;
    next.set(number, {
      ...page,
      slots: page.slots.map((slot) => {
        const replacement = patch.get(slot.slotId);
        if (!replacement) return slot;
        previous.set(slot.slotId, slot);
        return replacement;
      }),
    });
  }
  return { cache: next, previous };
}

/** Carta que o desfazer da retirada recoloca (D2): o mesmo exemplar, no mesmo bolso, por NOVA colocação. */
export type UndoRemoval = { position: PocketPosition; physicalCardId: string; cardName: string };

/** Busca o exemplar recém-retirado na lista elegível (5373) pelo nome e número — a retirada não devolve o id. */
export function findUndoCandidate(items: AvailableCard[], removed: Pick<BinderSlot, "present">): AvailableCard | null {
  const face = removed.present;
  if (!face) return null;
  const matches = items.filter(
    (card) =>
      card.cardName === face.cardName &&
      (card.collectorNumber ?? null) === (face.collectorNumber ?? null) &&
      (card.setCode ?? "").toLowerCase() === (face.setCode ?? "").toLowerCase() &&
      (card.languageCode ?? null) === (face.languageCode ?? null) &&
      (card.variantLabel ?? null) === (face.variantLabel ?? null),
  );
  // Só desfaz com certeza: dois exemplares idênticos ficam ambíguos e o desfazer não é oferecido.
  return matches.length === 1 ? (matches[0] ?? null) : null;
}

// ---------------------------------------------------------------------------
// Fechamento de uma escrita otimista: dado o resultado do servidor, decide o
// que a tela faz. Puro (a área de trabalho aplica), para que reversão, perda
// de permissão e mensagens tenham teste sem rede.

export type EditorOutcome = { ok: true; operation: string } | { ok: false; reason: EditorFailure };

export type EditorOperation =
  | { kind: "place"; cardName: string; page: number }
  | { kind: "move"; cardName: string; otherName: string | null; page: number }
  | { kind: "remove" }
  | { kind: "undo"; cardName: string };

export type EditorSettlement = {
  /** Patch que desfaz a mudança otimista (só nas recusas). */
  revert: SlotPatch | null;
  toast: { tone: "success" | "error"; text: string };
  filledDelta: number;
  /** Desligar a edição nesta tela (perda de papel, saída, arquivada, barreira, sessão). */
  disable: boolean;
  /** Reler a coleção (o acesso pode ter acabado ou o papel mudado). */
  recheck: boolean;
};

export function settleEditorOutcome(op: EditorOperation, outcome: EditorOutcome, previous: SlotPatch): EditorSettlement {
  if (!outcome.ok) {
    return {
      revert: previous.size > 0 ? previous : null,
      toast: { tone: "error", text: editorFailureMessage(outcome.reason) },
      filledDelta: 0,
      disable: editorFailureDisablesEditing(outcome.reason),
      recheck: editorFailureRechecksAccess(outcome.reason),
    };
  }
  const added = outcome.operation === "ADD" ? 1 : 0;
  switch (op.kind) {
    case "place":
      return {
        revert: null,
        toast: { tone: "success", text: outcome.operation === "UNCHANGED" ? "A carta já está nesse bolso." : `${op.cardName} foi para a página ${op.page}.` },
        filledDelta: added,
        disable: false,
        recheck: false,
      };
    case "move":
      return {
        revert: null,
        toast: {
          tone: "success",
          text: outcome.operation === "SWAP" ? `${op.cardName} e ${op.otherName ?? "a outra carta"} trocaram de lugar.` : `${op.cardName} foi para a página ${op.page}.`,
        },
        filledDelta: 0,
        disable: false,
        recheck: false,
      };
    case "remove":
      return { revert: null, toast: { tone: "success", text: "A carta saiu do fichário e continua na coleção." }, filledDelta: -1, disable: false, recheck: false };
    case "undo":
      return { revert: null, toast: { tone: "success", text: `${op.cardName} voltou para o bolso.` }, filledDelta: added, disable: false, recheck: false };
  }
}
