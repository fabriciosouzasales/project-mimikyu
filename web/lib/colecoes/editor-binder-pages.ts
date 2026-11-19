import type { BinderPage, BinderSlot } from "./binder.ts";
import { type EditorFailure, classifyEditorFailure, editorFailureDisablesEditing, editorFailureMessage, editorFailureRechecksAccess } from "./editor-binder.ts";

/**
 * V1-13 · E2-3A — páginas do fichário compartilhado pelo EDITOR (5382:
 * adicionar, remover e reordenar). Regras puras, sem rede.
 *
 * Fronteira: a tela só escolhe o que oferecer e como reagir. Quem decide é o
 * servidor, a cada chamada: fichário EXCLUSIVO da coleção (C-237) e nenhum
 * conteúdo de terceiros na página removida, sob a trava do fichário. A tela
 * mascarada (5315) não define o que pode ser editado: uma página que parece
 * vazia pode guardar conteúdo que o participante não vê.
 */

export type PageOp = "add" | "remove" | "reorder";

export type PageFailure =
  | "reserved_to_owner"
  | "page_not_empty"
  | "page_not_found"
  | "keep_one_page"
  | "species_on_page"
  | "order_changed"
  | EditorFailure;

/**
 * Recusa → motivo estável. Lê só o código e a MENSAGEM (o nome da exceção);
 * `hint` e `details` nunca são lidos nem exibidos — os da 5382 distinguem
 * "várias coleções" de "conteúdo de terceiros", e isso não sai do servidor.
 */
export function classifyPageFailure(code: string | null | undefined, message: string | null | undefined): PageFailure {
  const text = (message ?? "").trim().toUpperCase();
  if (text === "OPERATION_RESERVED_TO_OWNER") return "reserved_to_owner";
  if (text === "PAGE_NOT_EMPTY") return "page_not_empty";
  if (text === "PAGE_NOT_FOUND") return "page_not_found";
  if (text === "BINDER_MUST_KEEP_ONE_PAGE") return "keep_one_page";
  if (text === "SPECIES_REFERENCES_ON_PAGE") return "species_on_page";
  if (text === "INVALID_PAGE_ORDER") return "order_changed";
  return classifyEditorFailure(code, message);
}

function isEditorFailure(reason: PageFailure): reason is EditorFailure {
  return !["reserved_to_owner", "page_not_empty", "page_not_found", "keep_one_page", "species_on_page", "order_changed"].includes(reason);
}

/** Mensagem neutra: nunca descreve o que ocupa a página nem por que o fichário é do titular. */
export function pageFailureMessage(op: PageOp, reason: PageFailure): string {
  switch (reason) {
    case "reserved_to_owner":
      return op === "remove" ? "Essa página não pode ser removida por aqui. Ela fica com o titular." : "Neste fichário, as páginas são organizadas pelo titular.";
    case "page_not_empty":
      return "A página ainda tem cartas ou reservas desta coleção. Esvazie a página antes de removê-la.";
    case "page_not_found":
      return "Essa página não existe mais. Atualizamos o fichário.";
    case "keep_one_page":
      return "O fichário precisa de ao menos uma página.";
    case "species_on_page":
      // D2: referências de espécie não são geridas pelo EDITOR nesta versão (nenhuma contagem é lida nem confirmada).
      return "Essa página não pode ser removida por aqui. Ela fica com o titular.";
    case "order_changed":
      return "O número de páginas mudou. Atualizamos o fichário: monte a ordem de novo.";
    case "unknown":
      return op === "add"
        ? "Não foi possível confirmar se a página foi criada. Atualizamos o fichário para mostrar o estado atual."
        : "Não foi possível confirmar o resultado. Atualizamos o fichário para mostrar o estado atual.";
    default:
      return editorFailureMessage(reason);
  }
}

/** Depois desta recusa a edição é desligada nesta tela (mesma regra da E2-1). */
export function pageFailureDisablesEditing(reason: PageFailure): boolean {
  return isEditorFailure(reason) && editorFailureDisablesEditing(reason);
}

export function pageFailureRechecksAccess(reason: PageFailure): boolean {
  return isEditorFailure(reason) && editorFailureRechecksAccess(reason);
}

// ---------------------------------------------------------------------------
// D1 — exclusividade aprendida na sessão.

/** `UNKNOWN` nunca vale como "exclusivo": só significa que a tela não tem prova do contrário. */
export type Exclusivity = "UNKNOWN" | "NOT_EXCLUSIVE";

/**
 * Só uma recusa INEQUÍVOCA prova que o fichário não é exclusivo. Na 5382,
 * adicionar e reordenar recusam `OPERATION_RESERVED_TO_OWNER` apenas na
 * autorização de exclusividade (X não é a proprietária ou há convidada):
 * adicionar só cria bolsos vazios e reordenar não toca bolso. Remover recusa
 * com o mesmo código também por conteúdo de terceiros NA PÁGINA — ambíguo,
 * não ensina nada.
 */
export function exclusivityLesson(op: PageOp, reason: PageFailure): Exclusivity | null {
  if (reason !== "reserved_to_owner") return null;
  return op === "add" || op === "reorder" ? "NOT_EXCLUSIVE" : null;
}

// ---------------------------------------------------------------------------
// R1 — remover e reordenar por NÚMERO, sem token de versão. A tela relê logo
// antes e compara o que mostrou com o que leu; isso reduz, mas não elimina, a
// janela de corrida (a ordem pode mudar entre a releitura e a gravação).

function slotSignature(slot: BinderSlot): string {
  const face = slot.present;
  const reserve = slot.expected;
  return [
    slot.row,
    slot.column,
    face ? `c:${face.cardName}|${face.collectorNumber ?? ""}|${face.setCode ?? ""}|${face.languageCode ?? ""}|${face.variantLabel ?? ""}` : "",
    reserve ? `r:${reserve.cardName}|${reserve.collectorNumber ?? ""}|${reserve.setCode ?? ""}` : "",
    slot.image ? "i" : "",
    slot.regionId ? "g" : "",
  ].join("/");
}

/** Assinatura do que o participante VÊ numa página (mascarada): base da comparação antes de gravar. */
export function pageSignature(page: Pick<BinderPage, "slots" | "regions">): string {
  const slots = [...page.slots].sort((a, b) => a.row - b.row || a.column - b.column).map(slotSignature);
  const regions = (page.regions ?? []).map((r) => `${r.row}:${r.leftColumn}:${r.width}x${r.height}`).sort();
  return `${slots.join(";")}#${regions.join(",")}`;
}

export type FreshCheck = { ok: true } | { ok: false; reason: "count_changed" | "content_changed" | "unreadable" };

/**
 * Confere, logo antes da gravação, se o fichário ainda é o que a tela mostrou:
 * mesmo número de páginas e, para cada página mostrada, o mesmo conteúdo
 * visível no mesmo número. Páginas idênticas na tela mascarada continuam
 * indistinguíveis (limitação registrada).
 */
export function checkFreshPages(shown: readonly BinderPage[], shownTotal: number, freshTotal: number | null, fresh: ReadonlyMap<number, BinderPage> | null): FreshCheck {
  if (freshTotal === null || fresh === null) return { ok: false, reason: "unreadable" };
  if (freshTotal !== shownTotal) return { ok: false, reason: "count_changed" };
  for (const page of shown) {
    const now = fresh.get(page.pageNumber);
    if (!now) return { ok: false, reason: "unreadable" };
    if (pageSignature(now) !== pageSignature(page)) return { ok: false, reason: "content_changed" };
  }
  return { ok: true };
}

export function freshCheckMessage(op: "remove" | "reorder", reason: "count_changed" | "content_changed" | "unreadable"): string {
  if (reason === "unreadable") return "Não foi possível conferir o fichário agora. Nada foi alterado — tente de novo.";
  if (op === "remove") return "O fichário mudou desde que você abriu esta confirmação. Confira a página de novo antes de remover.";
  return reason === "count_changed"
    ? "O número de páginas mudou desde que você abriu a organização. Atualizamos as páginas: monte a ordem de novo."
    : "As páginas mudaram desde que você abriu a organização. Atualizamos as miniaturas: revise a ordem antes de aplicar.";
}

/**
 * Ordem montada na tela → parâmetro da 5382: o i-ésimo elemento é o número
 * ATUAL da página que passa a ser a página i. Precisa ser uma permutação
 * completa de 1..total; senão nada é enviado.
 */
export function reorderPayload(order: readonly Pick<BinderPage, "pageNumber">[], total: number): number[] | null {
  if (!Number.isInteger(total) || total < 1 || order.length !== total) return null;
  const numbers = order.map((page) => page.pageNumber);
  const seen = new Set<number>();
  for (const n of numbers) {
    if (!Number.isInteger(n) || n < 1 || n > total || seen.has(n)) return null;
    seen.add(n);
  }
  return numbers;
}

export function reorderChanged(payload: readonly number[]): boolean {
  return payload.some((n, index) => n !== index + 1);
}

// ---------------------------------------------------------------------------
// Remoção vista pelo EDITOR: só o que ele VÊ e pode resolver bloqueia na tela.
// Uma página que parece vazia nunca é anunciada como "vazia": o servidor decide.

export type EditorRemovalBlocker = "last_page" | "cards" | "reservations" | "owner_content";

export function editorRemovalBlockers(page: Pick<BinderPage, "slots" | "regions">, totalPages: number): EditorRemovalBlocker[] {
  const found = new Set<EditorRemovalBlocker>();
  if (!Number.isInteger(totalPages) || totalPages <= 1) found.add("last_page");
  if ((page.regions?.length ?? 0) > 0) found.add("owner_content");
  for (const slot of page.slots) {
    if (slot.present) found.add("cards");
    if (slot.expected && !slot.present) found.add("reservations");
    if (slot.image || slot.regionId) found.add("owner_content");
  }
  return (["last_page", "cards", "reservations", "owner_content"] as const).filter((reason) => found.has(reason));
}

export function editorRemovalBlockerLabel(reason: EditorRemovalBlocker): string {
  switch (reason) {
    case "last_page":
      return "É a única página do fichário — o fichário precisa de ao menos uma.";
    case "cards":
      return "Tem cartas desta coleção — tire-as do fichário antes.";
    case "reservations":
      return "Tem bolsos reservados para esta coleção — libere as reservas antes.";
    case "owner_content":
      return "Tem imagens do fichário — essa página fica com o titular.";
  }
}

// ---------------------------------------------------------------------------
// Bloqueio das operações estruturais enquanto outra coisa está em curso.

export type StructuralState = {
  busy: boolean;
  trayCount: number;
  armed: boolean;
  armedCard: boolean;
  dragging: boolean;
  confirming: boolean;
  reserving: boolean;
};

/** Motivo pelo qual páginas não podem mudar agora; `null` = livre. */
export function structuralBlocker(s: StructuralState): string | null {
  if (s.busy) return "Aguarde a alteração em andamento terminar.";
  if (s.trayCount > 0) return "Devolva ou posicione as cartas da Bandeja antes de mudar as páginas.";
  if (s.armed || s.armedCard || s.dragging) return "Termine de posicionar a carta antes de mudar as páginas.";
  if (s.confirming || s.reserving) return "Conclua a confirmação aberta antes de mudar as páginas.";
  return null;
}

/** Resumo do lote de "Adicionar páginas" (sequencial, para na primeira recusa, sem repetir). */
export function addPagesMessage(requested: number, added: number, failure: PageFailure | null): { tone: "success" | "error"; text: string } {
  if (failure === null) return { tone: "success", text: added === 1 ? "1 página adicionada no fim do fichário." : `${added} páginas adicionadas no fim do fichário.` };
  const reason = pageFailureMessage("add", failure);
  if (added === 0) return { tone: "error", text: reason };
  return { tone: "error", text: `Adicionamos ${added} de ${requested} páginas. ${reason}` };
}
