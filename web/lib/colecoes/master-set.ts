/**
 * Objetivo da coleção de Set — Set padrão ↔ Master Set
 * (MASTER-SET-FRONTEND-PHASE-01). Regras puras de apresentação: sem banco,
 * sem React, testáveis com `node --test`.
 *
 * Master Set é uma POLÍTICA de completude da coleção de Set (NS-18, C-23),
 * nunca um tipo de coleção. O colecionador escolhe os acabamentos (C-188);
 * as posições, as contagens e a regra das cartas secretas (C-189) vêm só do
 * banco (5191 opções, 5192 prévia, 5194/5195 gravação, 5081 volta ao padrão).
 * Esta camada só decide o que a interface mostra e qual contrato chamar —
 * nenhuma conta de posição é feita aqui.
 *
 * Nenhuma das ações altera exemplares, vínculos, locais ou fichário: isso é
 * garantido pelos contratos (LDM-194) e repetido na interface.
 */

/**
 * Objetivo Set padrão ↔ Master Set (criação e Ajustes). Publicado
 * (autorização do proprietário, 2026-10-19): a grade Master Set (5189/5198),
 * "fora do objetivo" (5196) e o fluxo de acabamentos (5191–5195) estão no LIVE
 * e foram homologados (H1–H14, 2026-10-18).
 */
export const MASTER_SET_OBJECTIVE_RELEASED: boolean = true;

/**
 * Homologação local (5199-CLOSEOUT): liga as duas funções SÓ quando o app roda
 * com `next dev` (NODE_ENV = development) E `.env.local` tem
 * `NEXT_PUBLIC_MASTER_SET_LOCAL_HOMOLOGATION=1`. Qualquer build de produção
 * (Vercel, `next build`) tem NODE_ENV = production e ignora a variável —
 * usuários finais nunca veem. Publicar = trocar os `*_RELEASED` para `true`.
 */
export const MASTER_SET_LOCAL_HOMOLOGATION: boolean =
  process.env.NODE_ENV === "development" && process.env.NEXT_PUBLIC_MASTER_SET_LOCAL_HOMOLOGATION === "1";

export const MASTER_SET_OBJECTIVE_ENABLED: boolean = MASTER_SET_OBJECTIVE_RELEASED || MASTER_SET_LOCAL_HOMOLOGATION;

/** Sugestão inicial (C-188): só sugestão, o colecionador muda à vontade. */
export const SUGGESTED_FINISH_CODES: readonly string[] = ["STANDARD", "HOLO", "REVERSE_HOLO"];

/** Teto do contrato (5190): até 64 acabamentos por objetivo. */
export const MAX_FINISHES = 64;

export type CompletionObjective = "STANDARD_SET" | "MASTER_SET";

/** Um acabamento existente no Set (5191, `row_kind = 'FINISH'`). */
export type FinishOption = {
  id: string;
  /** Código interno — usado só para a sugestão inicial, nunca exibido. */
  code: string;
  name: string;
  order: number;
  /** Cartas do Set nesse acabamento (contagem do banco). */
  positions: number;
  /** Dessas, quantas a coleção já satisfaz. */
  ownedPositions: number;
  /** Gravado no objetivo (também em Set padrão: é o que será restaurado). */
  saved: boolean;
};

/** Bloco de cartas secretas (5191, `row_kind = 'SECRET_CARDS'`): sempre no objetivo. */
export type SecretCards = { positions: number; ownedPositions: number };

export type ObjectiveState = {
  policy: CompletionObjective;
  finishes: FinishOption[];
  secrets: SecretCards | null;
};

export type ObjectivePreview = {
  currentPolicy: CompletionObjective;
  currentTotal: number;
  currentSatisfied: number;
  proposedTotal: number;
  proposedSatisfied: number;
  /** Posições de carta secreta que nenhum acabamento escolhido contempla. */
  proposedSecretPositions: number;
  positionsAdded: number;
  positionsRemoved: number;
  copiesInCollection: number;
  /** Exemplares que continuariam na coleção sem contar para o objetivo. */
  copiesOutsideAfter: number;
};

/** O que a confirmação vai pedir ao banco. */
export type ObjectivePlan =
  | { kind: "none" }
  | { kind: "to_standard" }
  /** `finishIds = null` → restaura a seleção guardada (5194 com NULL). */
  | { kind: "activate"; finishIds: string[] | null }
  | { kind: "replace"; finishIds: string[] }
  | { kind: "invalid"; reason: "empty_selection" | "too_many" };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isFinishId(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

export function isCompletionObjective(value: unknown): value is CompletionObjective {
  return value === "STANDARD_SET" || value === "MASTER_SET";
}

type OptionRow = {
  row_kind?: unknown;
  variant_type_id?: unknown;
  variant_type_code?: unknown;
  variant_type_name?: unknown;
  display_order?: unknown;
  positions?: unknown;
  owned_positions?: unknown;
  is_selected?: unknown;
};

function count(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

/**
 * Linhas de 5191 → acabamentos (na ordem do catálogo) e bloco de secretas.
 * Linha malformada é descartada — nunca vira opção clicável.
 */
export function parseObjectiveOptions(rows: readonly OptionRow[]): Pick<ObjectiveState, "finishes" | "secrets"> {
  const finishes: FinishOption[] = [];
  let secrets: SecretCards | null = null;
  for (const row of rows) {
    if (row.row_kind === "SECRET_CARDS") {
      const positions = count(row.positions);
      if (positions > 0) secrets = { positions, ownedPositions: Math.min(count(row.owned_positions), positions) };
      continue;
    }
    if (row.row_kind !== "FINISH" || !isFinishId(row.variant_type_id)) continue;
    const name = typeof row.variant_type_name === "string" ? row.variant_type_name.trim() : "";
    if (!name) continue;
    const positions = count(row.positions);
    finishes.push({
      id: row.variant_type_id.toLowerCase(),
      code: typeof row.variant_type_code === "string" ? row.variant_type_code : "",
      name,
      order: Number.isFinite(Number(row.display_order)) ? Number(row.display_order) : Number.MAX_SAFE_INTEGER,
      positions,
      ownedPositions: Math.min(count(row.owned_positions), positions),
      saved: row.is_selected === true,
    });
  }
  finishes.sort((a, b) => a.order - b.order || a.name.localeCompare(b.name, "pt-BR"));
  return { finishes, secrets };
}

/** Acabamentos gravados que ainda existem no Set. */
export function savedSelection(finishes: readonly FinishOption[]): string[] {
  return finishes.filter((finish) => finish.saved).map((finish) => finish.id);
}

/**
 * Seleção com que o colecionador começa: a gravada (restauração, C-23/LDM-22);
 * sem gravação, a sugestão Padrão + Holográfica + Holográfica Reversa entre as
 * que existem no Set; se nenhuma existir, o primeiro acabamento do catálogo.
 */
export function initialSelection(finishes: readonly FinishOption[]): string[] {
  const saved = savedSelection(finishes);
  if (saved.length > 0) return saved;
  const suggested = finishes.filter((finish) => SUGGESTED_FINISH_CODES.includes(finish.code)).map((finish) => finish.id);
  if (suggested.length > 0) return suggested;
  return finishes[0] ? [finishes[0].id] : [];
}

/** Sem a seleção gravada, a interface mostra "sugestão"; com ela, "restaurado". */
export function selectionOrigin(finishes: readonly FinishOption[]): "saved" | "suggested" {
  return savedSelection(finishes).length > 0 ? "saved" : "suggested";
}

export function sameSelection(a: readonly string[], b: readonly string[]): boolean {
  if (a.length !== b.length) return false;
  const set = new Set(a.map((id) => id.toLowerCase()));
  return b.every((id) => set.has(id.toLowerCase()));
}

/** Liga/desliga um acabamento, preservando a ordem do catálogo. */
export function toggleFinish(selection: readonly string[], id: string, finishes: readonly FinishOption[]): string[] {
  const next = new Set(selection);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  return finishes.filter((finish) => next.has(finish.id)).map((finish) => finish.id);
}

/**
 * Qual contrato a confirmação chama.
 *
 * - Mesmo objetivo e (em Master Set) mesmos acabamentos → nada a gravar.
 * - Voltar ao Set padrão → 5081 (os acabamentos ficam guardados).
 * - Ativar com exatamente a seleção guardada → 5194 com NULL: restaura
 *   inclusive acabamentos guardados que hoje não aparecem como opção
 *   (LDM-195), em vez de apagá-los por omissão.
 * - Ativar com outra seleção → 5194 com a lista; editar em Master Set → 5195.
 */
export function planObjectiveChange(
  state: Pick<ObjectiveState, "policy" | "finishes">,
  target: CompletionObjective,
  selection: readonly string[],
): ObjectivePlan {
  const saved = savedSelection(state.finishes);
  if (target === "STANDARD_SET") return state.policy === "STANDARD_SET" ? { kind: "none" } : { kind: "to_standard" };
  if (state.policy === "MASTER_SET" && sameSelection(selection, saved)) return { kind: "none" };
  if (selection.length === 0) return { kind: "invalid", reason: "empty_selection" };
  if (selection.length > MAX_FINISHES) return { kind: "invalid", reason: "too_many" };
  const ids = [...selection];
  if (state.policy === "STANDARD_SET") {
    return { kind: "activate", finishIds: saved.length > 0 && sameSelection(ids, saved) ? null : ids };
  }
  return { kind: "replace", finishIds: ids };
}

/** Os ids que a prévia (5192) recebe para o plano — a restauração prevê a seleção guardada. */
export function previewFinishIds(plan: ObjectivePlan, state: Pick<ObjectiveState, "finishes">): string[] | null {
  if (plan.kind === "activate") return plan.finishIds ?? savedSelection(state.finishes);
  if (plan.kind === "replace") return plan.finishIds;
  return null;
}

type PreviewRow = {
  current_policy?: unknown;
  current_total?: unknown;
  current_satisfied?: unknown;
  proposed_total?: unknown;
  proposed_satisfied?: unknown;
  proposed_secret_positions?: unknown;
  positions_added?: unknown;
  positions_removed?: unknown;
  copies_in_collection?: unknown;
  copies_outside_after?: unknown;
};

export function parsePreview(row: PreviewRow | undefined): ObjectivePreview | null {
  if (!row || !isCompletionObjective(row.current_policy)) return null;
  return {
    currentPolicy: row.current_policy,
    currentTotal: count(row.current_total),
    currentSatisfied: count(row.current_satisfied),
    proposedTotal: count(row.proposed_total),
    proposedSatisfied: count(row.proposed_satisfied),
    proposedSecretPositions: count(row.proposed_secret_positions),
    positionsAdded: count(row.positions_added),
    positionsRemoved: count(row.positions_removed),
    copiesInCollection: count(row.copies_in_collection),
    copiesOutsideAfter: count(row.copies_outside_after),
  };
}

/** Rótulos oficiais (N8/N9) — nunca o enum. */
export function objectiveTitle(objective: CompletionObjective): string {
  return objective === "MASTER_SET" ? "Master Set" : "Set padrão";
}

export function objectiveSubtitle(objective: CompletionObjective): string {
  return objective === "MASTER_SET" ? "os acabamentos que você escolher" : "uma de cada carta";
}

/** "+12 posições" / "−3 posições" / null quando zero. */
export function positionsDelta(value: number, sign: "+" | "−"): string | null {
  if (value <= 0) return null;
  return `${sign}${value.toLocaleString("pt-BR")} ${value === 1 ? "posição" : "posições"}`;
}

// ---------------------------------------------------------------------------
// Falhas — o texto cru do banco nunca chega ao colecionador
// ---------------------------------------------------------------------------

export type ObjectiveFailure =
  | "not_authenticated"
  | "not_found"
  | "archived"
  /** O Set ou a seleção guardada mudou desde a leitura: reler as opções. */
  | "stale"
  | "empty_objective"
  | "invalid"
  | "disabled"
  | "unavailable";

/**
 * Classifica pelo código estável de cada contrato: 5191/5192/5194/5195 usam
 * mensagens em maiúsculas; 5081 usa frases fixas em inglês (v2.0).
 */
export function classifyObjectiveFailure(code: string | null | undefined, message: string | null | undefined): ObjectiveFailure {
  const text = message ?? "";
  if (code === "28000" || code === "42501" || text === "not_authenticated" || text === "authentication required") {
    return "not_authenticated";
  }
  if (text === "COLLECTION_NOT_FOUND" || text.startsWith("collection not found") || code === "P0002") return "not_found";
  if (text === "COLLECTION_ARCHIVED" || text.startsWith("collection is archived")) return "archived";
  if (
    text === "FINISH_NOT_IN_SET" ||
    text === "NO_SAVED_FINISHES" ||
    text === "MASTER_SET_NOT_ACTIVE" ||
    text === "MASTER_SET_REQUIRES_SET_COLLECTION" ||
    text.startsWith("set_collection_completion_policy_to_standard_set requires")
  ) {
    return "stale";
  }
  if (text === "EMPTY_OBJECTIVE") return "empty_objective";
  if (text === "INVALID_FINISHES" || code === "22023" || code === "22P02") return "invalid";
  return "unavailable";
}

export function objectiveFailureMessage(reason: ObjectiveFailure): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "not_found":
      return "Esta coleção não está disponível.";
    case "archived":
      return "Esta coleção está arquivada. Reative-a para mudar o objetivo — nada foi alterado.";
    case "stale":
      return "Os acabamentos deste Set mudaram desde que você abriu os Ajustes. Atualizamos as opções — revise e confirme de novo.";
    case "empty_objective":
      return "Com essa escolha o objetivo ficaria sem nenhuma carta. Escolha outro acabamento — nada foi alterado.";
    case "invalid":
      return "Algo na escolha não está certo. Revise os acabamentos e tente de novo.";
    case "disabled":
      return "O Master Set ainda não está disponível. Nada foi alterado.";
    default:
      return "Não foi possível concluir agora. Nada foi alterado — tente novamente em instantes.";
  }
}

// ---------------------------------------------------------------------------
// Grade do Master Set (MASTER-SET-FRONTEND-PHASE-02) — 5189/5198, 5196, 5199
// ---------------------------------------------------------------------------

/**
 * "Adicionar do acervo" por posição. Usa `5199 get_my_master_set_position_copies`
 * (exemplares livres que satisfazem a posição; LIVE e canônica desde
 * 2026-10-18, 5842 30/30) e vincula pela 5046; o lote usa a 5200 (LIVE,
 * 5843 25/25). Publicado (autorização do proprietário, 2026-10-19).
 */
export const MASTER_SET_ADD_FROM_ACERVO_RELEASED: boolean = true;

export const MASTER_SET_ADD_FROM_ACERVO_ENABLED: boolean =
  MASTER_SET_ADD_FROM_ACERVO_RELEASED || MASTER_SET_LOCAL_HOMOLOGATION;

/** Posições por página da grade (contrato aceita até 500). */
export const MASTER_SET_PAGE_SIZE = 120;

/** Exemplares fora do objetivo por leitura (contrato aceita até 500). */
export const OUT_OF_SCOPE_PAGE_SIZE = 50;

/** Exemplares livres listados por posição (5199 aceita até 100). */
export const POSITION_COPIES_LIMIT = 50;

/** Uma posição do Master Set: carta + acabamento, ou carta secreta genérica. */
export type MasterSetPosition = {
  /** Único na página: carta + acabamento (ou "secreta"). */
  key: string;
  cardId: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardName: string;
  /** `null` = posição genérica de carta secreta (qualquer acabamento vale). */
  variantTypeId: string | null;
  variantTypeName: string | null;
  isSecret: boolean;
  imagePath: string | null;
  isSatisfied: boolean;
  copiesInCollection: number;
  copiesAvailable: number;
};

export type MasterSetPositionsPage = { items: MasterSetPosition[]; total: number };

type PositionRow = {
  card_id?: unknown;
  collector_number?: unknown;
  collector_total?: unknown;
  card_name?: unknown;
  variant_type_id?: unknown;
  variant_type_name?: unknown;
  is_secret?: unknown;
  image_path?: unknown;
  is_satisfied?: unknown;
  copies_in_collection?: unknown;
  copies_available?: unknown;
  total_count?: unknown;
};

export function positionKey(cardId: string, variantTypeId: string | null): string {
  return `${cardId.toLowerCase()}:${variantTypeId ? variantTypeId.toLowerCase() : "secreta"}`;
}

/** Linhas de 5189/5198 → posições. Linha malformada é descartada. */
export function parseMasterSetPositions(rows: readonly PositionRow[]): MasterSetPositionsPage {
  const items: MasterSetPosition[] = [];
  let total = 0;
  for (const row of rows) {
    if (!isFinishId(row.card_id)) continue;
    const variantTypeId = isFinishId(row.variant_type_id) ? row.variant_type_id.toLowerCase() : null;
    if (row.variant_type_id != null && variantTypeId === null) continue;
    const name = typeof row.variant_type_name === "string" ? row.variant_type_name.trim() : "";
    const totalSet = Number(row.collector_total);
    items.push({
      key: positionKey(row.card_id, variantTypeId),
      cardId: row.card_id.toLowerCase(),
      collectorNumber: typeof row.collector_number === "string" ? row.collector_number : "",
      collectorTotal: Number.isFinite(totalSet) && row.collector_total !== null ? totalSet : null,
      cardName: typeof row.card_name === "string" ? row.card_name : "",
      variantTypeId,
      variantTypeName: variantTypeId && name ? name : null,
      isSecret: row.is_secret === true,
      imagePath: typeof row.image_path === "string" && row.image_path !== "" ? row.image_path : null,
      isSatisfied: row.is_satisfied === true,
      copiesInCollection: count(row.copies_in_collection),
      copiesAvailable: count(row.copies_available),
    });
    total = Math.max(total, count(row.total_count));
  }
  return { items, total };
}

/** Rótulo discreto do acabamento na carta. */
export function finishBadge(position: Pick<MasterSetPosition, "variantTypeName" | "variantTypeId">): string {
  if (position.variantTypeId === null) return "Qualquer acabamento";
  return position.variantTypeName ?? "Acabamento";
}

/** Texto para leitor de tela: o que a posição é e em que estado está. */
export function positionStatusText(position: Pick<MasterSetPosition, "isSatisfied" | "copiesAvailable">): string {
  if (position.isSatisfied) return "na coleção";
  return position.copiesAvailable > 0 ? "falta na coleção, mas você tem no acervo" : "falta";
}

/** Página pedida na URL (`?pagina=`), limitada ao que existe. */
export function parseMasterSetPage(raw: string | string[] | undefined): number {
  const value = Array.isArray(raw) ? raw[0] : raw;
  const page = value && /^\d{1,4}$/.test(value) ? Number(value) : 1;
  return Math.max(page, 1);
}

export function masterSetTotalPages(total: number, pageSize = MASTER_SET_PAGE_SIZE): number {
  return Math.max(1, Math.ceil(Math.max(0, total) / pageSize));
}

/** Uma entrada por carta para o hero: tem a carta se qualquer posição dela está satisfeita. */
export function heroCardsFromMasterSet(positions: readonly MasterSetPosition[]): {
  cardId: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  imagePath: string | null;
  isSatisfied: boolean;
  copiesInCollection: number;
  copiesAvailable: number;
}[] {
  const byCard = new Map<string, ReturnType<typeof heroCardsFromMasterSet>[number]>();
  for (const position of positions) {
    const current = byCard.get(position.cardId);
    if (!current) {
      byCard.set(position.cardId, {
        cardId: position.cardId,
        cardName: position.cardName,
        collectorNumber: position.collectorNumber,
        collectorTotal: position.collectorTotal,
        imagePath: position.imagePath,
        isSatisfied: position.isSatisfied,
        copiesInCollection: position.copiesInCollection,
        copiesAvailable: position.copiesAvailable,
      });
      continue;
    }
    current.isSatisfied = current.isSatisfied || position.isSatisfied;
    current.imagePath = current.imagePath ?? position.imagePath;
    current.copiesInCollection = Math.max(current.copiesInCollection, position.copiesInCollection);
  }
  return [...byCard.values()];
}

// ---- exemplares fora do objetivo (5196) ----

export type OutOfScopeReason = "CARD_INACTIVE" | "PAIR_NOT_IN_CATALOG" | "FINISH_NOT_SELECTED";

export type OutOfScopeCopy = {
  physicalCardId: string;
  cardName: string;
  collectorNumber: string;
  finishName: string | null;
  reason: OutOfScopeReason;
};

export type OutOfScopePage = { items: OutOfScopeCopy[]; total: number };

type OutOfScopeRow = {
  physical_card_id?: unknown;
  card_name?: unknown;
  collector_number?: unknown;
  variant_type_name?: unknown;
  reason?: unknown;
  total_count?: unknown;
};

const REASONS: readonly OutOfScopeReason[] = ["CARD_INACTIVE", "PAIR_NOT_IN_CATALOG", "FINISH_NOT_SELECTED"];

export function parseOutOfScope(rows: readonly OutOfScopeRow[]): OutOfScopePage {
  const items: OutOfScopeCopy[] = [];
  let total = 0;
  for (const row of rows) {
    if (!isFinishId(row.physical_card_id)) continue;
    const reason = REASONS.find((known) => known === row.reason);
    if (!reason) continue;
    const finish = typeof row.variant_type_name === "string" ? row.variant_type_name.trim() : "";
    items.push({
      physicalCardId: row.physical_card_id.toLowerCase(),
      cardName: typeof row.card_name === "string" ? row.card_name : "",
      collectorNumber: typeof row.collector_number === "string" ? row.collector_number : "",
      finishName: finish || null,
      reason,
    });
    total = Math.max(total, count(row.total_count));
  }
  return { items, total };
}

/** Motivo em linguagem de colecionador (nunca o código). */
export function outOfScopeReasonText(reason: OutOfScopeReason): string {
  if (reason === "FINISH_NOT_SELECTED") return "Este acabamento não faz parte do seu objetivo.";
  if (reason === "PAIR_NOT_IN_CATALOG") return "O catálogo não lista mais esta carta neste acabamento.";
  return "Esta carta saiu do catálogo ativo do Set.";
}

// ---- exemplares livres de uma posição (5199, proposta) ----

export type PositionCopy = {
  physicalCardId: string;
  variantLabel: string | null;
  isDefaultVariant: boolean;
  languageName: string;
  storageName: string | null;
  addedAt: string;
};

type PositionCopyRow = {
  physical_card_id?: unknown;
  variant_label?: unknown;
  is_default_variant?: unknown;
  language_code?: unknown;
  language_name?: unknown;
  storage_name?: unknown;
  added_at?: unknown;
  total_count?: unknown;
};

export function parsePositionCopies(rows: readonly PositionCopyRow[]): { items: PositionCopy[]; total: number } {
  const items: PositionCopy[] = [];
  let total = 0;
  for (const row of rows) {
    if (!isFinishId(row.physical_card_id)) continue;
    const language =
      typeof row.language_name === "string" && row.language_name.trim()
        ? row.language_name.trim()
        : typeof row.language_code === "string"
          ? row.language_code
          : "";
    items.push({
      physicalCardId: row.physical_card_id.toLowerCase(),
      variantLabel: typeof row.variant_label === "string" && row.variant_label.trim() ? row.variant_label.trim() : null,
      isDefaultVariant: row.is_default_variant === true,
      languageName: language,
      storageName: typeof row.storage_name === "string" && row.storage_name.trim() ? row.storage_name.trim() : null,
      addedAt: typeof row.added_at === "string" ? row.added_at : "",
    });
    total = Math.max(total, count(row.total_count));
  }
  return { items, total };
}

/** "Holográfica Reversa · 1ª Edição · Português" — versão + idioma. */
export function positionCopyLabel(copy: Pick<PositionCopy, "variantLabel" | "isDefaultVariant" | "languageName">): string {
  const variant = copy.variantLabel ?? (copy.isDefaultVariant ? "Versão padrão" : "Outra versão");
  return copy.languageName ? `${variant} · ${copy.languageName}` : variant;
}

// ---------------------------------------------------------------------------
// "Adicionar cartas" em lote — um exemplar livre por posição faltante (5200)
// ---------------------------------------------------------------------------

/**
 * Teto por leitura/lote: o mesmo da 5046 (`allocate_physical_cards_to_collection`)
 * e o limite máximo aceito pela 5200.
 */
export const MASTER_SET_LINK_BATCH_SIZE = 500;

/** Uma posição faltante com o exemplar do acervo que entraria nela. */
export type MasterSetLinkCandidate = {
  /** Carta + acabamento (ou "secreta") — o mesmo `positionKey` da grade. */
  key: string;
  physicalCardId: string;
  cardId: string;
  variantTypeId: string | null;
  collectorNumber: string;
  cardName: string;
  variantTypeName: string | null;
  isSecret: boolean;
  languageCode: string | null;
  imagePath: string | null;
};

type LinkCandidateRow = {
  physical_card_id?: unknown;
  card_id?: unknown;
  variant_type_id?: unknown;
  collector_number?: unknown;
  card_name?: unknown;
  variant_type_name?: unknown;
  is_secret?: unknown;
  language_code?: unknown;
  image_path?: unknown;
  total_count?: unknown;
};

/**
 * Linhas da 5200 → candidatos. Linha malformada é descartada; posição ou
 * exemplar repetido (não deveria acontecer — contrato da 5200) fica só na
 * primeira ocorrência, para nunca enviar o mesmo exemplar duas vezes à 5046.
 */
export function parseMasterSetLinkCandidates(rows: readonly LinkCandidateRow[]): {
  items: MasterSetLinkCandidate[];
  total: number;
} {
  const items: MasterSetLinkCandidate[] = [];
  const seenKeys = new Set<string>();
  const seenCopies = new Set<string>();
  let total = 0;
  for (const row of rows) {
    if (!isFinishId(row.physical_card_id) || !isFinishId(row.card_id)) continue;
    const variantTypeId = isFinishId(row.variant_type_id) ? row.variant_type_id.toLowerCase() : null;
    if (row.variant_type_id != null && variantTypeId === null) continue;
    const key = positionKey(row.card_id, variantTypeId);
    const physicalCardId = row.physical_card_id.toLowerCase();
    total = Math.max(total, count(row.total_count));
    if (seenKeys.has(key) || seenCopies.has(physicalCardId)) continue;
    seenKeys.add(key);
    seenCopies.add(physicalCardId);
    const name = typeof row.variant_type_name === "string" ? row.variant_type_name.trim() : "";
    items.push({
      key,
      physicalCardId,
      cardId: row.card_id.toLowerCase(),
      variantTypeId,
      collectorNumber: typeof row.collector_number === "string" ? row.collector_number : "",
      cardName: typeof row.card_name === "string" ? row.card_name : "",
      variantTypeName: variantTypeId && name ? name : null,
      isSecret: row.is_secret === true,
      languageCode: typeof row.language_code === "string" && row.language_code ? row.language_code : null,
      imagePath: typeof row.image_path === "string" && row.image_path !== "" ? row.image_path : null,
    });
  }
  return { items, total: Math.max(total, items.length) };
}

/** Chave de posição válida vinda do cliente (`<uuid>:<uuid>` ou `<uuid>:secreta`). */
export function isPositionKey(value: unknown): value is string {
  if (typeof value !== "string") return false;
  const [card, finish, ...rest] = value.split(":");
  return rest.length === 0 && isFinishId(card) && (finish === "secreta" || isFinishId(finish));
}

/**
 * Exemplares a vincular: só as posições marcadas que continuam faltando na
 * releitura (estado atual), na ordem do Set. Posição marcada que já foi
 * atendida (outro dispositivo, envio repetido) simplesmente não entra.
 */
export function pickLinkCopies(candidates: readonly MasterSetLinkCandidate[], wanted: ReadonlySet<string>): string[] {
  return candidates.filter((candidate) => wanted.has(candidate.key)).map((candidate) => candidate.physicalCardId);
}
