import type { BinderPage, BinderSlot } from "./binder.ts";
import { hasForbiddenKey, isCopyToken } from "./copy-token.ts";
import { applyClearReservation, applyMove, applyRemove, isOccupied } from "./binder.ts";
import type { AvailableCard } from "./binder-share.ts";
import { applyPlaceAvailable } from "./binder-share.ts";
import type { ReserveCandidate, ReserveScope } from "./binder-reserve.ts";
import { applyReserveFor, reserveScopeOf } from "./binder-reserve.ts";

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

/**
 * 5397 (`get_shared_binder_placeable_copies`): o exemplar chega como token opaco (5391), nunca como
 * UUID físico. Linha com qualquer chave de identidade física/pessoal → resposta recusada (falha fechada).
 */
export function parsePlaceableCards(data: unknown): { items: AvailableCard[]; total: number } | null {
  if (!Array.isArray(data)) return null;
  const items: AvailableCard[] = [];
  let total = 0;
  for (const row of data) {
    if (!row || typeof row !== "object" || hasForbiddenKey(row)) return null;
    const r = row as Record<string, unknown>;
    const id = isCopyToken(r.copy_token) ? r.copy_token : null;
    const name = typeof r.card_name === "string" && r.card_name.trim() !== "" ? r.card_name : null;
    if (!id || !name) return null;
    const totalCount = Number(r.total_count);
    if (Number.isInteger(totalCount) && totalCount > total) total = totalCount;
    items.push({
      allocationId: null,
      // Token opaco (5397) no campo-chave da lista; a lista é só apresentação e o servidor revalida tudo.
      physicalCardId: id,
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
      // E4 (D-E4-3): sem atribuir o bolso a ninguém — pode ser do titular ou de outra coleção do fichário (C-237).
      return "Esse bolso não pode ser alterado por aqui. Escolha um bolso desta coleção.";
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
/** Desfazer a retirada: recoloca pelo token opaco (5397) do exemplar que voltou à lista. */
export type UndoRemoval = { position: PocketPosition; copyToken: string; cardName: string };

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
  | { kind: "undo"; cardName: string }
  | { kind: "reserve"; cardName: string }
  | { kind: "release" }
  | { kind: "lock"; locked: boolean };

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
    case "reserve":
      return {
        revert: null,
        toast: {
          tone: "success",
          text:
            outcome.operation === "UNCHANGED"
              ? "O bolso já estava reservado para essa carta."
              : outcome.operation === "REPLACED"
                ? `Reserva trocada para ${op.cardName}.`
                : `Bolso reservado para ${op.cardName}.`,
        },
        filledDelta: 0,
        disable: false,
        recheck: false,
      };
    case "release":
      return { revert: null, toast: { tone: "success", text: outcome.operation === "UNCHANGED" ? "Esse bolso já estava sem reserva." : "Reserva liberada." }, filledDelta: 0, disable: false, recheck: false };
    case "lock":
      return {
        revert: null,
        toast: {
          tone: "success",
          text: outcome.operation === "UNCHANGED" ? (op.locked ? "Esse bolso já estava fixado." : "Esse bolso já estava solto.") : op.locked ? "Bolso fixado." : "Bolso solto.",
        },
        filledDelta: 0,
        disable: false,
        recheck: false,
      };
  }
}

// ---------------------------------------------------------------------------
// V1-13 · E2-2 — reservas e fixação pelo EDITOR (5375).

/**
 * Estado de fixação que a TELA conhece de um bolso (P1). A leitura
 * compartilhada (5315) nunca informa fixação; o estado vem só de respostas
 * conclusivas do servidor nesta sessão e é preservado nas releituras (P2),
 * podendo estar desatualizado. UNKNOWN nunca significa "solto": a autorização
 * de cada escrita continua no servidor.
 */
export type LockKnowledge = "LOCKED" | "UNLOCKED" | "UNKNOWN";

export function positionKey(p: PocketPosition): string {
  return `${p.page}:${p.row}:${p.column}`;
}

export function knownLock(map: ReadonlyMap<string, "LOCKED" | "UNLOCKED">, position: PocketPosition | null): LockKnowledge {
  return position ? (map.get(positionKey(position)) ?? "UNKNOWN") : "UNKNOWN";
}

/**
 * O que uma resposta do servidor ENSINA sobre a fixação (só respostas
 * conclusivas; o resto não muda nada):
 *  - fixar/soltar aceito ou UNCHANGED → o estado pedido vale agora;
 *  - colocar, retirar, mover, reservar ou liberar aceitos → não havia trava que
 *    impedisse ESSA operação no bolso (colocar/retirar/mover recusam bolso
 *    fixado: o bolso estava solto); reservar/liberar não ensinam (o servidor
 *    aceita reserva em bolso fixado);
 *  - recusa SLOT_LOCKED numa operação de UM bolso → ele está fixado. No mover
 *    não se sabe qual dos dois: nada é aprendido.
 */
export type LockLesson = { position: PocketPosition; state: "LOCKED" | "UNLOCKED" };

export function lockLessons(
  op: { kind: "lock"; locked: boolean; position: PocketPosition } | { kind: "place" | "remove" | "undo"; position: PocketPosition } | { kind: "move"; from: PocketPosition; to: PocketPosition } | { kind: "reserve" | "release"; position: PocketPosition },
  outcome: EditorOutcome,
): LockLesson[] {
  if (op.kind === "lock") {
    return outcome.ok ? [{ position: op.position, state: op.locked ? "LOCKED" : "UNLOCKED" }] : [];
  }
  if (op.kind === "reserve" || op.kind === "release") return [];
  if (outcome.ok) {
    return op.kind === "move"
      ? [
          { position: op.from, state: "UNLOCKED" },
          { position: op.to, state: "UNLOCKED" },
        ]
      : [{ position: op.position, state: "UNLOCKED" }];
  }
  if (outcome.reason === "locked" && op.kind !== "move") return [{ position: op.position, state: "LOCKED" }];
  return [];
}

export function applyLockLessons(map: ReadonlyMap<string, "LOCKED" | "UNLOCKED">, lessons: LockLesson[]): Map<string, "LOCKED" | "UNLOCKED"> {
  const next = new Map(map);
  for (const lesson of lessons) next.set(positionKey(lesson.position), lesson.state);
  return next;
}

/** Página para a tela: o bolso que a sessão SABE fixado ganha `locked` (selo e bloqueio local); UNKNOWN/UNLOCKED ficam como vieram. */
export function overlayLocks(page: BinderPage, map: ReadonlyMap<string, "LOCKED" | "UNLOCKED">): BinderPage {
  if (map.size === 0) return page;
  let changed = false;
  const slots = page.slots.map((slot) => {
    const position = sharedSlotPosition(slot.slotId);
    const locked = knownLock(map, position) === "LOCKED";
    if (slot.locked === locked) return slot;
    changed = true;
    return { ...slot, locked };
  });
  return changed ? { ...page, slots } : page;
}

/**
 * Ações de reserva/fixação que a tela OFERECE ao EDITOR num bolso — só sobre
 * conteúdo de X visível (C-237). Nunca em bolso com imagem ou mesclagem.
 * Bolso aparentemente vazio pode ser de terceiros: oferecer reservar não é
 * afirmar que é livre; a resposta do servidor decide.
 */
export type EditorPocketActions = { reserve: boolean; changeReserve: boolean; release: boolean; lock: boolean; unlock: boolean };

export function editorPocketActions(slot: BinderSlot, lock: LockKnowledge, inTray: boolean): EditorPocketActions {
  const none: EditorPocketActions = { reserve: false, changeReserve: false, release: false, lock: false, unlock: false };
  if (slot.image || slot.regionId) return none;
  const occupied = isOccupied(slot);
  const reserved = !occupied && slot.state === "RESERVED_EMPTY";
  const ownContent = occupied || reserved;
  return {
    // Reservar: bolso vazio que a sessão não sabe fixado (fixado sem conteúdo de X é do titular).
    reserve: !occupied && !reserved && lock !== "LOCKED" && !inTray,
    // Reserva visível de X: trocar e liberar (P4: liberar mesmo fixado; o servidor decide).
    changeReserve: reserved,
    release: reserved,
    // Fixar/soltar: só com conteúdo de X visível; nunca com a carta na Bandeja.
    lock: ownContent && lock !== "LOCKED" && !inTray,
    unlock: ownContent && lock === "LOCKED",
  };
}

export function patchReserve(slot: BinderSlot, candidate: ReserveCandidate, collectionId: string): SlotPatch {
  return new Map([[slot.slotId, applyReserveFor(slot, candidate, collectionId)]]);
}

export function patchRelease(slot: BinderSlot): SlotPatch {
  return new Map([[slot.slotId, applyClearReservation(slot)]]);
}

// ---- cartas para reservar, pela leitura compartilhada do tipo da coleção ----

/** Escopo da reserva para o EDITOR: o do tipo da coleção (Pokédex e desconhecidos não têm reserva por carta). */
export function editorReserveScope(completionPolicy: string | null | undefined): ReserveScope | null {
  return reserveScopeOf(completionPolicy);
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const text = (v: unknown) => (typeof v === "string" && v.trim() !== "" ? v : null);

/** 5320 (Set padrão) ou 5323 (Master Set) → candidatos. Só campos de catálogo e "já tem" da coleção (sem acervo). */
export function candidatesFromSharedPositions(
  scope: "STANDARD_SET" | "MASTER_SET",
  rows: unknown,
  set: { code: string | null; name: string | null },
): ReserveCandidate[] | null {
  if (!Array.isArray(rows)) return null;
  const out: ReserveCandidate[] = [];
  for (const row of rows) {
    if (!row || typeof row !== "object") return null;
    const r = row as Record<string, unknown>;
    if (typeof r.card_id !== "string" || !UUID_RE.test(r.card_id)) return null;
    const cardId = r.card_id.toLowerCase();
    const variant = scope === "MASTER_SET" && typeof r.variant_type_id === "string" && UUID_RE.test(r.variant_type_id) ? r.variant_type_id.toLowerCase() : null;
    if (scope === "MASTER_SET" && !variant) return null;
    out.push({
      key: variant ? `${cardId}:${variant}` : cardId,
      cardId,
      variantTypeId: variant,
      finishName: scope === "MASTER_SET" ? text(r.variant_type_name) : null,
      cardName: text(r.card_name) ?? "Carta",
      collectorNumber: text(r.collector_number),
      collectorTotal: Number.isInteger(r.collector_total) ? (r.collector_total as number) : null,
      setCode: set.code,
      setName: set.name,
      imagePath: text(r.image_path),
      owned: typeof r.is_satisfied === "boolean" ? r.is_satisfied : null,
    });
  }
  return out;
}

/** `search_cards` (Catálogo, coleção livre) → candidatos — mesma leitura do titular. */
export function candidatesFromCatalogSearch(rows: unknown): ReserveCandidate[] | null {
  if (!Array.isArray(rows)) return null;
  return rows
    .filter((r): r is Record<string, unknown> => !!r && typeof r === "object" && typeof (r as Record<string, unknown>).card_id === "string" && UUID_RE.test((r as Record<string, unknown>).card_id as string))
    .map((r) => ({
      key: (r.card_id as string).toLowerCase(),
      cardId: (r.card_id as string).toLowerCase(),
      variantTypeId: null,
      finishName: null,
      cardName: text(r.card_name) ?? "Carta",
      collectorNumber: text(r.collector_number),
      collectorTotal: typeof r.collector_total === "number" ? r.collector_total : null,
      setCode: text(r.card_set_code),
      setName: text(r.card_set_name),
      imagePath: text(r.image_path_pt) ?? text(r.image_path_en),
      owned: null,
    }));
}
