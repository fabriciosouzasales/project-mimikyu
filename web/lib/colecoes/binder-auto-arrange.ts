// Organização automática do fichário (P2, C-220–C-226) — regras puras do cliente.
//
// Contrato efetivo (canônicas `database/schema/5342`–`5344`, contrato
// `binder-auto-arrange-contract.md` v1.6 — Set/Master Set: bolsos reservados;
// Pokédex: bolso de cada espécie recebe a representante da espécie):
//  - prévia 5343 `preview_my_binder_auto_arrange(collection) → jsonb`
//    { status READY|EMPTY|LIMIT_EXCEEDED, insert_count, limit (500), plan_token,
//      excluded_cards {motivo: n}, unfilled_slots {motivo: n}, unfilled_count,
//      pages [n…], items [{ord, slot_id, physical_card_id, page_number,
//      row_index, column_index, card_id, card_variant_id}] } — `items` vem
//      vazio em LIMIT_EXCEEDED; `pages` cobre todas as inserções planejadas;
//  - confirmação 5344 `apply_my_binder_auto_arrange(collection, token) → jsonb`
//    APPLIED {inserted, event_id, pages} | NOTHING_TO_DO {inserted 0}
//    | ALREADY_APPLIED {inserted 0, event_id}.
//
// O cliente NUNCA decide posições: o plano e o token vêm do servidor e são só
// validados e apresentados aqui. O token é opaco — conferido no formato
// (`aa1:` + 64 hex) e devolvido como recebido. Formato inesperado → `null`
// (nunca adivinha). Nenhum texto exposto contém identificador.
//
// Executar os testes: node --experimental-strip-types --test lib/colecoes/binder-auto-arrange.test.ts (a partir de web/)

// ---------------------------------------------------------------------------
// Constantes do contrato
// ---------------------------------------------------------------------------

/** Limite por confirmação (C-225; `c_limit` da 5343/5344). */
export const AUTO_ARRANGE_LIMIT = 500;

/** `aa1:` + SHA-256 em hex minúsculo — mesmo padrão da 5344 (`^aa1:[0-9a-f]{64}$`). */
const PLAN_TOKEN_RE = /^aa1:[0-9a-f]{64}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const AUTO_ARRANGE_STATUSES = ["READY", "EMPTY", "LIMIT_EXCEEDED"] as const;
export type AutoArrangeStatus = (typeof AUTO_ARRANGE_STATUSES)[number];

/** Motivos de exemplar fora do plano (5342 `card_reason`). */
export const EXCLUDED_CARD_REASONS = ["INACTIVE_VARIANT", "NO_COMPATIBLE_RESERVATION", "MULTIPLE_DESTINATIONS", "COMPETING_CANDIDATES", "NOT_REPRESENTATIVE"] as const;
export type ExcludedCardReason = (typeof EXCLUDED_CARD_REASONS)[number];

/** Motivos de bolso reservado que continua vazio (5342 `slot_reason`). */
export const UNFILLED_SLOT_REASONS = ["NO_CANDIDATE", "COMPETING_CANDIDATES", "MULTIPLE_DESTINATIONS", "INACTIVE_VARIANT"] as const;
export type UnfilledSlotReason = (typeof UNFILLED_SLOT_REASONS)[number];

export function isPlanToken(value: unknown): value is string {
  return typeof value === "string" && PLAN_TOKEN_RE.test(value);
}

// ---------------------------------------------------------------------------
// Elegibilidade (só apresentação; o servidor é a autoridade — C-220)
// ---------------------------------------------------------------------------

export type AutoArrangeEntry =
  /** Ação ausente: tipo de coleção sem organização automática ou sem fichário. */
  | { visible: false }
  /**
   * Ação presente; `enabled = false` mostra o motivo (padrão do trilho: indisponível, nunca some).
   * `target: "SPECIES"` = Pokédex (bolsos de espécie); ausente = Set/Master Set (bolsos reservados).
   */
  | { visible: true; enabled: true; target?: "SPECIES" }
  | { visible: true; enabled: false; reason: "NOT_BINDER_OWNER" | "ARCHIVED" | "READ_ONLY"; target?: "SPECIES" };

/** Destino da organização: bolsos reservados (Set/Master Set) ou bolsos de espécie (Pokédex). */
export type AutoArrangeTarget = "RESERVED" | "SPECIES";

export function autoArrangeTarget(entry: AutoArrangeEntry): AutoArrangeTarget {
  return entry.visible && entry.target === "SPECIES" ? "SPECIES" : "RESERVED";
}

export function autoArrangeEntry(header: {
  hasBinder: boolean;
  kind: string;
  active: boolean;
  editable: boolean;
  role: "OWNER" | "GUEST" | null;
}): AutoArrangeEntry {
  if (!header.hasBinder) return { visible: false };
  const species = header.kind === "POKEDEX";
  if (header.kind !== "SET" && header.kind !== "MASTER_SET" && !species) return { visible: false };
  // Pokédex não tem fichário hóspede: sem papel de dono, a ação não aparece.
  if (header.role === "GUEST") return species ? { visible: false } : { visible: true, enabled: false, reason: "NOT_BINDER_OWNER" };
  if (header.role !== "OWNER") return { visible: false };
  const t = species ? ({ target: "SPECIES" } as const) : {};
  if (!header.active) return { visible: true, enabled: false, reason: "ARCHIVED", ...t };
  if (!header.editable) return { visible: true, enabled: false, reason: "READ_ONLY", ...t };
  return { visible: true, enabled: true, ...t };
}

export function entryHint(entry: AutoArrangeEntry): string | null {
  if (!entry.visible || entry.enabled) return null;
  switch (entry.reason) {
    case "NOT_BINDER_OWNER":
      return "Só a coleção dona deste fichário organiza as cartas automaticamente.";
    case "ARCHIVED":
      return "A coleção está arquivada. Reative-a para organizar o fichário.";
    case "READ_ONLY":
      return "Este fichário está só para leitura.";
  }
}

// ---------------------------------------------------------------------------
// Prévia (5343)
// ---------------------------------------------------------------------------

export type AutoArrangeItem = {
  ord: number;
  slotId: string;
  physicalCardId: string;
  page: number;
  row: number;
  col: number;
  cardId: string;
  cardVariantId: string;
};

export type AutoArrangePreview = {
  status: AutoArrangeStatus;
  insertCount: number;
  limit: number;
  planToken: string;
  excludedCards: Partial<Record<ExcludedCardReason, number>>;
  excludedCount: number;
  unfilledSlots: Partial<Record<UnfilledSlotReason, number>>;
  unfilledCount: number;
  pages: number[];
  items: AutoArrangeItem[];
};

function obj(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function int(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function uuid(value: unknown): string | null {
  return typeof value === "string" && UUID_RE.test(value) ? value : null;
}

function reasonCounts<R extends string>(value: unknown, allowed: readonly R[]): { counts: Partial<Record<R, number>>; total: number } | null {
  const r = obj(value);
  if (!r) return null;
  const counts: Partial<Record<R, number>> = {};
  let total = 0;
  for (const [key, raw] of Object.entries(r)) {
    if (!(allowed as readonly string[]).includes(key)) return null; // motivo desconhecido: não adivinha
    const n = int(raw);
    if (n === null || n < 1) return null; // a 5343 só emite motivos presentes (count ≥ 1)
    counts[key as R] = n;
    total += n;
  }
  return { counts, total };
}

function parseItem(value: unknown): AutoArrangeItem | null {
  const r = obj(value);
  if (!r) return null;
  const ord = int(r.ord);
  const page = int(r.page_number);
  const row = int(r.row_index);
  const col = int(r.column_index);
  const slotId = uuid(r.slot_id);
  const physicalCardId = uuid(r.physical_card_id);
  const cardId = uuid(r.card_id);
  const cardVariantId = uuid(r.card_variant_id);
  if (ord === null || ord < 1 || page === null || page < 1 || row === null || row < 1 || col === null || col < 1) return null;
  if (!slotId || !physicalCardId || !cardId || !cardVariantId) return null;
  return { ord, slotId, physicalCardId, page, row, col, cardId, cardVariantId };
}

/**
 * Valida a resposta da 5343 por inteiro. Qualquer incoerência com o contrato
 * (estado × contagem × itens, motivo desconhecido, token malformado, páginas
 * fora de ordem, bolso ou exemplar repetido) → `null`.
 */
export function parsePreview(value: unknown): AutoArrangePreview | null {
  const r = obj(value);
  if (!r) return null;
  const status = r.status;
  if (typeof status !== "string" || !(AUTO_ARRANGE_STATUSES as readonly string[]).includes(status)) return null;
  const insertCount = int(r.insert_count);
  const limit = int(r.limit);
  const unfilledCount = int(r.unfilled_count);
  if (insertCount === null || insertCount < 0 || limit === null || limit < 1 || unfilledCount === null || unfilledCount < 0) return null;
  if (!isPlanToken(r.plan_token)) return null;
  const excluded = reasonCounts(r.excluded_cards, EXCLUDED_CARD_REASONS);
  const unfilled = reasonCounts(r.unfilled_slots, UNFILLED_SLOT_REASONS);
  if (!excluded || !unfilled || unfilled.total !== unfilledCount) return null;

  if (!Array.isArray(r.pages)) return null;
  const pages: number[] = [];
  for (const raw of r.pages) {
    const p = int(raw);
    if (p === null || p < 1 || (pages.length > 0 && p <= pages[pages.length - 1]!)) return null; // distintas e crescentes
    pages.push(p);
  }

  if (!Array.isArray(r.items)) return null;
  const items: AutoArrangeItem[] = [];
  const slots = new Set<string>();
  const cards = new Set<string>();
  for (const raw of r.items) {
    const item = parseItem(raw);
    if (!item || item.ord !== items.length + 1) return null; // ord 1..n em sequência
    if (slots.has(item.slotId) || cards.has(item.physicalCardId)) return null; // 1:1 estrito (C-222)
    if (!pages.includes(item.page)) return null;
    slots.add(item.slotId);
    cards.add(item.physicalCardId);
    items.push(item);
  }

  // Coerência estado × contagem × itens (5343: CASE do status).
  if (status === "EMPTY" && (insertCount !== 0 || items.length !== 0 || pages.length !== 0)) return null;
  if (status === "READY" && (insertCount < 1 || insertCount > limit || items.length !== insertCount)) return null;
  if (status === "READY" && new Set(items.map((i) => i.page)).size !== pages.length) return null;
  if (status === "LIMIT_EXCEEDED" && (insertCount <= limit || items.length !== 0 || pages.length === 0)) return null;

  return {
    status: status as AutoArrangeStatus,
    insertCount,
    limit,
    planToken: r.plan_token,
    excludedCards: excluded.counts,
    excludedCount: excluded.total,
    unfilledSlots: unfilled.counts,
    unfilledCount,
    pages,
    items,
  };
}

/** Só READY pode seguir para a confirmação; EMPTY e LIMIT_EXCEEDED nunca chamam a 5344. */
export function canConfirm(preview: AutoArrangePreview | null): boolean {
  return !!preview && preview.status === "READY" && preview.insertCount >= 1 && preview.insertCount <= preview.limit && isPlanToken(preview.planToken);
}

// ---------------------------------------------------------------------------
// Textos (linguagem do colecionador; sem códigos internos nem identificadores)
// ---------------------------------------------------------------------------

const NUMBER = new Intl.NumberFormat("pt-BR");

function count(n: number, one: string, many: string): string {
  return `${NUMBER.format(n)} ${n === 1 ? one : many}`;
}

export function excludedCardReasonLabel(reason: ExcludedCardReason, target: AutoArrangeTarget = "RESERVED"): string {
  switch (reason) {
    case "NO_COMPATIBLE_RESERVATION":
      return target === "SPECIES" ? "O bolso da espécie não está livre" : "Sem bolso reservado para esta carta";
    case "NOT_REPRESENTATIVE":
      return "Outra cópia representa esta espécie";
    case "COMPETING_CANDIDATES":
      return "Mais de uma cópia para o mesmo bolso";
    case "MULTIPLE_DESTINATIONS":
      return "A carta tem mais de um bolso reservado";
    case "INACTIVE_VARIANT":
      return "Versão desativada no catálogo";
  }
}

export function unfilledSlotReasonLabel(reason: UnfilledSlotReason): string {
  switch (reason) {
    case "NO_CANDIDATE":
      return "Nenhuma cópia guardada neste fichário";
    case "COMPETING_CANDIDATES":
      return "Várias cópias disputam este bolso";
    case "MULTIPLE_DESTINATIONS":
      return "A mesma cópia serve a mais de um bolso";
    case "INACTIVE_VARIANT":
      return "A carta reservada está com a versão desativada";
  }
}

export type ReasonLine = { key: string; label: string; count: number };

/** Linhas de motivo na ordem do contrato, só as presentes. */
export function excludedLines(preview: AutoArrangePreview, target: AutoArrangeTarget = "RESERVED"): ReasonLine[] {
  return EXCLUDED_CARD_REASONS.filter((r) => (preview.excludedCards[r] ?? 0) > 0).map((r) => ({ key: r, label: excludedCardReasonLabel(r, target), count: preview.excludedCards[r]! }));
}

export function unfilledLines(preview: AutoArrangePreview): ReasonLine[] {
  return UNFILLED_SLOT_REASONS.filter((r) => (preview.unfilledSlots[r] ?? 0) > 0).map((r) => ({ key: r, label: unfilledSlotReasonLabel(r), count: preview.unfilledSlots[r]! }));
}

export const REASONS_FOOTNOTE = "Para resolver, posicione essas cartas manualmente ou ajuste as reservas dos bolsos.";
export const SPECIES_REASONS_FOOTNOTE = "As cópias extras continuam em Cartas disponíveis. Para trocar a carta do bolso, escolha outra representante na Pokédex ou posicione manualmente.";

export function reasonsFootnote(target: AutoArrangeTarget): string {
  return target === "SPECIES" ? SPECIES_REASONS_FOOTNOTE : REASONS_FOOTNOTE;
}

/** Subtítulo do painel. */
export function panelHint(target: AutoArrangeTarget): string {
  return target === "SPECIES"
    ? "Coloca no bolso de cada espécie a carta que a representa na Pokédex, entre as guardadas neste fichário que ainda não têm lugar."
    : "Coloca nos bolsos reservados as cartas guardadas neste fichário que ainda não têm lugar.";
}

/** "página 3", "páginas 2 e 3", "páginas 1, 2 e 5", "12 páginas". */
export function pagesPhrase(pages: readonly number[]): string {
  if (pages.length === 0) return "";
  if (pages.length === 1) return `página ${pages[0]}`;
  if (pages.length > 6) return `${NUMBER.format(pages.length)} páginas`;
  return `páginas ${pages.slice(0, -1).join(", ")} e ${pages[pages.length - 1]}`;
}

export type PreviewSummary = { headline: string; detail: string };

export function previewSummary(preview: AutoArrangePreview, target: AutoArrangeTarget = "RESERVED"): PreviewSummary {
  switch (preview.status) {
    case "READY":
      return {
        headline: `${count(preview.insertCount, "carta pronta", "cartas prontas")} para o seu lugar`,
        detail: `Entram em ${count(preview.pages.length, "página", "páginas")} (${pagesPhrase(preview.pages)}). Nenhuma carta é substituída, movida ou retirada.`,
      };
    case "EMPTY":
      return {
        headline: "Nenhuma alteração",
        detail:
          target === "SPECIES"
            ? "Não há nenhuma carta representante de espécie esperando pelo bolso dela neste fichário."
            : "Não há nenhuma carta com um único bolso reservado livre esperando por ela neste fichário.",
      };
    case "LIMIT_EXCEEDED":
      return {
        headline: `${count(preview.insertCount, "carta", "cartas")} — o limite é ${NUMBER.format(preview.limit)} por vez`,
        detail: "Nada será posicionado agora. Fixe algumas páginas ou organize parte das cartas manualmente e gere a prévia de novo.",
      };
  }
}

export function unfilledPhrase(preview: AutoArrangePreview): string | null {
  return preview.unfilledCount > 0 ? `${count(preview.unfilledCount, "bolso reservado continua vazio", "bolsos reservados continuam vazios")}` : null;
}

export function excludedPhrase(preview: AutoArrangePreview): string | null {
  return preview.excludedCount > 0 ? `${count(preview.excludedCount, "carta fica de fora", "cartas ficam de fora")}` : null;
}

/** Resumo da confirmação explícita (C-224). */
export function confirmationText(preview: AutoArrangePreview, target: AutoArrangeTarget = "RESERVED"): string {
  const kept = target === "SPECIES" ? "bolsos fixados e cópias extras ficam como estão" : "reservas e bolsos fixados ficam como estão";
  return `${count(preview.insertCount, "carta será colocada", "cartas serão colocadas")} em ${count(preview.pages.length, "página", "páginas")}. Nenhuma carta é substituída, movida ou retirada; ${kept}.`;
}

export function confirmLabel(preview: AutoArrangePreview): string {
  return `Posicionar ${count(preview.insertCount, "carta", "cartas")}`;
}

// ---------------------------------------------------------------------------
// Confirmação (5344)
// ---------------------------------------------------------------------------

export type AutoArrangeApplyResult =
  | { outcome: "APPLIED"; inserted: number; eventId: number; pages: number[] }
  | { outcome: "NOTHING_TO_DO"; inserted: 0 }
  | { outcome: "ALREADY_APPLIED"; inserted: 0; eventId: number };

export function parseApply(value: unknown): AutoArrangeApplyResult | null {
  const r = obj(value);
  if (!r) return null;
  const inserted = int(r.inserted);
  if (inserted === null) return null;
  switch (r.status) {
    case "APPLIED": {
      const eventId = int(r.event_id);
      if (eventId === null || eventId < 1 || inserted < 1 || inserted > AUTO_ARRANGE_LIMIT || !Array.isArray(r.pages)) return null;
      const pages: number[] = [];
      for (const raw of r.pages) {
        const p = int(raw);
        if (p === null || p < 1 || (pages.length > 0 && p <= pages[pages.length - 1]!)) return null;
        pages.push(p);
      }
      if (pages.length === 0 || pages.length > inserted) return null;
      return { outcome: "APPLIED", inserted, eventId, pages };
    }
    case "NOTHING_TO_DO":
      return inserted === 0 ? { outcome: "NOTHING_TO_DO", inserted: 0 } : null;
    case "ALREADY_APPLIED": {
      const eventId = int(r.event_id);
      return inserted === 0 && eventId !== null && eventId >= 1 ? { outcome: "ALREADY_APPLIED", inserted: 0, eventId } : null;
    }
    default:
      return null;
  }
}

export function applyResultMessage(result: AutoArrangeApplyResult): string {
  switch (result.outcome) {
    case "APPLIED":
      return `${count(result.inserted, "carta posicionada", "cartas posicionadas")} em ${count(result.pages.length, "página", "páginas")}.`;
    case "ALREADY_APPLIED":
      return "Essa organização já tinha sido aplicada. Nada mudou agora.";
    case "NOTHING_TO_DO":
      return "Nada a posicionar agora.";
  }
}

// ---------------------------------------------------------------------------
// Falhas (contrato v1.4 §3/§7)
// ---------------------------------------------------------------------------

export type AutoArrangeFailure =
  | "plan_changed" // 40001 AUTO_ARRANGE_PLAN_CHANGED
  | "lock_timeout" // 55P03 (lock_timeout 5 s)
  | "deadlock" // 40P01
  | "statement_timeout" // 57014
  | "limit_exceeded" // 54000 AUTO_ARRANGE_LIMIT_EXCEEDED
  | "unsupported" // 22023 AUTO_ARRANGE_UNSUPPORTED_COLLECTION
  | "not_owner" // 42501 AUTO_ARRANGE_NOT_BINDER_OWNER
  | "forbidden" // 42501 sem mensagem de domínio (ex.: sem EXECUTE)
  | "archived" // 55000 COLLECTION_ARCHIVED
  | "collection_not_found" // P0002 COLLECTION_NOT_FOUND (inexistente ou alheia)
  | "binder_not_found" // P0002 BINDER_NOT_FOUND
  | "not_authenticated" // 28000
  | "invalid_argument" // 22023 INVALID_ARGUMENT
  | "unavailable" // função ausente (PGRST202 / 42883)
  | "invalid_response" // resposta fora do contrato
  | "uncertain" // sem resposta do banco: resultado desconhecido
  | "unknown"; // erro do banco não previsto (transação desfeita)

/** Erro como chega do PostgREST/supabase-js; `null` = nenhuma resposta (rede, timeout do cliente, gateway). */
export type RpcErrorLike = { code?: string | null; message?: string | null } | null | undefined;

const SQLSTATE_RE = /^[0-9A-Z]{5}$/;
const CONNECTION_LOSS_RE = /^(08[0-9A-Z]{3}|57P0[1-5]|58[0-9A-Z]{3})$/;

/**
 * Classe da falha. A MENSAGEM de domínio vem antes do código quando o código
 * é compartilhado (22023, 42501, P0002). Sem código SQLSTATE válido (nenhuma
 * resposta, erro de transporte, gateway) → `uncertain`: não dá para afirmar se
 * a escrita aconteceu.
 */
export function classifyAutoArrangeFailure(error: RpcErrorLike): AutoArrangeFailure {
  const code = (error?.code ?? "").trim();
  const text = (error?.message ?? "").toUpperCase();
  if (code === "PGRST202" || code === "42883") return "unavailable";
  if (!SQLSTATE_RE.test(code)) return "uncertain";
  // Conexão perdida (08), servidor interrompido (57P01–57P05) ou falha de
  // sistema (58): o código veio, mas não prova que a transação foi desfeita
  // antes de qualquer confirmação.
  if (CONNECTION_LOSS_RE.test(code)) return "uncertain";
  switch (code) {
    case "28000":
      return "not_authenticated";
    case "40001":
      return "plan_changed";
    case "55P03":
      return "lock_timeout";
    case "40P01":
      return "deadlock";
    case "57014":
      return "statement_timeout";
    case "54000":
      return "limit_exceeded";
    case "55000":
      return "archived";
    case "22023":
      return text.includes("AUTO_ARRANGE_UNSUPPORTED_COLLECTION") ? "unsupported" : "invalid_argument";
    case "42501":
      return text.includes("AUTO_ARRANGE_NOT_BINDER_OWNER") ? "not_owner" : "forbidden";
    case "P0002":
      return text.includes("BINDER_NOT_FOUND") ? "binder_not_found" : "collection_not_found";
    default:
      return "unknown";
  }
}

/**
 * O PostgreSQL respondeu com erro de comando (inclusive XX000) ou o PostgREST
 * recusou antes de executar (PGRST202): a transação da 5344 foi desfeita por
 * inteiro, nada foi gravado. `uncertain` (transporte, perda de conexão,
 * servidor interrompido) e `invalid_response` (sucesso ilegível, a RPC pode
 * ter gravado) deixam o resultado em aberto: revalidar só por leitura.
 */
export function writeDefinitelyNotApplied(reason: AutoArrangeFailure): boolean {
  return reason !== "uncertain" && reason !== "invalid_response";
}

/** Próximo passo da interface. Nenhum deles repete a escrita sozinho. */
export type FailureNextStep =
  /** 40001: nova prévia automática (só leitura) e nova confirmação explícita. */
  | "fresh_preview"
  /** 55P03 / 40P01 / 57014: oferecer "Tentar novamente", que começa por revalidação. */
  | "offer_retry"
  /** Sem resposta: revalidar (leitura) e interpretar com `interpretRevalidation`. */
  | "revalidate"
  /** 54000: a nova prévia mostra o estado LIMIT_EXCEEDED. */
  | "show_limit"
  /** 28000: entrar de novo. */
  | "reauthenticate"
  /** Estado que a interface não resolve: fechar o fluxo com a mensagem. */
  | "close";

export function failureNextStep(reason: AutoArrangeFailure): FailureNextStep {
  switch (reason) {
    case "plan_changed":
      return "fresh_preview";
    case "lock_timeout":
    case "deadlock":
    case "statement_timeout":
      return "offer_retry";
    case "uncertain":
    case "invalid_response":
      return "revalidate";
    case "limit_exceeded":
      return "show_limit";
    case "not_authenticated":
      return "reauthenticate";
    default:
      return "close";
  }
}

/** Erros depois dos quais a confirmação só volta após uma prévia nova. */
export function needsFreshPreview(reason: AutoArrangeFailure): boolean {
  const step = failureNextStep(reason);
  return step === "fresh_preview" || step === "offer_retry" || step === "revalidate" || step === "show_limit";
}

export function failureMessage(reason: AutoArrangeFailure): string {
  switch (reason) {
    case "plan_changed":
      return "O fichário mudou desde a prévia. Veja a prévia atualizada e confirme de novo.";
    case "lock_timeout":
      return "O fichário está sendo alterado agora. Tente de novo em instantes — nada foi posicionado.";
    case "deadlock":
      return "Não foi possível concluir agora por um conflito temporário. Nada foi posicionado; tente de novo.";
    case "statement_timeout":
      return "A organização demorou demais e foi cancelada. Nada foi posicionado; tente de novo.";
    case "limit_exceeded":
      return `São mais de ${NUMBER.format(AUTO_ARRANGE_LIMIT)} cartas de uma vez. Nada foi posicionado.`;
    case "unsupported":
      return "A organização automática vale só para coleções de Set, Master Set e Pokédex.";
    case "not_owner":
      return "Só a coleção dona deste fichário organiza as cartas automaticamente.";
    case "forbidden":
      return "Você não tem permissão para organizar este fichário.";
    case "archived":
      return "A coleção está arquivada. Reative-a para organizar o fichário.";
    case "collection_not_found":
      return "Não encontramos esta coleção. Recarregue a página.";
    case "binder_not_found":
      return "Esta coleção ainda não tem fichário digital.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre de novo para continuar.";
    case "invalid_argument":
      return "Não foi possível usar esta prévia. Gere uma nova.";
    case "unavailable":
      return "A organização automática ainda não está disponível.";
    case "invalid_response":
      return "Recebemos uma resposta inesperada. Vamos conferir o fichário antes de qualquer nova tentativa.";
    case "uncertain":
      return "Não conseguimos confirmar o resultado. Vamos conferir o fichário antes de qualquer nova tentativa.";
    case "unknown":
      return "Não foi possível organizar agora. Nada foi posicionado.";
  }
}

// ---------------------------------------------------------------------------
// Resultado incerto → revalidação (contrato v1.4 §4/§7)
// ---------------------------------------------------------------------------

export type RevalidationVerdict =
  /** Mesmo token: a época não mudou, logo a confirmação NÃO foi aplicada. Pode confirmar de novo, por ação explícita. */
  | "not_applied_same_plan"
  /** Token diferente: a confirmação pode ter sido aplicada, ou o fichário mudou. Mostrar a prévia revista e o Histórico; nova confirmação explícita. */
  | "changed_or_applied"
  /** Prévia nova não pôde ser lida: manter o fluxo bloqueado para escrita. */
  | "unknown";

/**
 * Toda aplicação grava um evento e muda a época do token (5342), então um
 * token IGUAL na revalidação prova que nada foi aplicado. Um token diferente
 * não prova o contrário — só que o plano atual é outro.
 */
export function interpretRevalidation(previousToken: string, fresh: AutoArrangePreview | null): RevalidationVerdict {
  if (!fresh || !isPlanToken(previousToken)) return "unknown";
  return fresh.planToken === previousToken ? "not_applied_same_plan" : "changed_or_applied";
}

export function revalidationMessage(verdict: RevalidationVerdict): string {
  switch (verdict) {
    case "not_applied_same_plan":
      return "Conferimos: nada foi posicionado e o plano continua o mesmo. Confirme de novo quando quiser.";
    case "changed_or_applied":
      return "O fichário mudou — a organização pode ter sido concluída. Confira o Histórico e a prévia atualizada antes de confirmar de novo.";
    case "unknown":
      return "Ainda não conseguimos conferir o fichário. Tente abrir a prévia de novo.";
  }
}
