import {
  type CopiesPage,
  type CopyToken,
  type EditorPokedexCopy,
  type EditorPokedexFailure,
  type FailurePolicy,
  failurePolicy,
  isCopyToken,
  isUuid,
  seenRepresentative,
} from "./editor-pokedex.ts";

/**
 * V1-13 · E3 / F3-2 — painel da posição da Pokédex compartilhada para o EDITOR.
 * Regras puras do painel (sem rede): quem pode abrir, o que cada ação envia
 * como estado esperado (sempre tirado da ÚLTIMA leitura da 5391, nunca
 * inventado), prevenção de ações duplicadas e reação às recusas da 5392.
 */

export type PanelRole = "EDITOR" | "VIEWER" | null;

/** A grade abre o painel? Só a configuração D1 ligada + EDITOR + coleção ativa. VIEWER: grade de sempre. */
export function editorPokedexPanelOpenable(i: { flagOn: boolean; role: PanelRole; archived: boolean }): boolean {
  return i.flagOn === true && i.role === "EDITOR" && i.archived === false;
}

/**
 * Intenção que o cliente envia à server action. Só tokens opacos e posições do
 * catálogo; a action monta e revalida a chamada com os construtores da F3-1.
 */
export type WriteIntent =
  | { kind: "move"; collectionId: string; copyToken: CopyToken; targetPositionId: string; expectedPositionId: string | null; confirmOverride: boolean }
  | { kind: "unassign"; collectionId: string; copyToken: CopyToken; expectedPositionId: string }
  | { kind: "choose"; collectionId: string; copyToken: CopyToken; expectedPositionId: string; expectedRepresentativeToken: CopyToken | null }
  | { kind: "restore"; collectionId: string; positionId: string; expectedRepresentativeToken: CopyToken };

export type IntentKind = WriteIntent["kind"];

function fromPage(page: CopiesPage | null, collectionId: string, positionId: string): boolean {
  return !!page && page.collectionId === collectionId.toLowerCase() && page.positionId === positionId.toLowerCase();
}

function inPage(page: CopiesPage, copy: EditorPokedexCopy): boolean {
  return page.items.some((i) => i.token === copy.token);
}

/** Colocar ou mover para esta posição: o estado esperado é a posição atual da carta COMO A LISTA A MOSTROU. */
export function moveIntent(collectionId: string, positionId: string, assignable: CopiesPage | null, copy: EditorPokedexCopy, confirmOverride = false): WriteIntent | null {
  if (!fromPage(assignable, collectionId, positionId) || assignable!.scope !== "ASSIGNABLE" || !inPage(assignable!, copy)) return null;
  if (copy.currentPositionId !== null && copy.currentPositionId === positionId.toLowerCase()) return null;
  return { kind: "move", collectionId: collectionId.toLowerCase(), copyToken: copy.token, targetPositionId: positionId.toLowerCase(), expectedPositionId: copy.currentPositionId, confirmOverride };
}

/** Retirar desta posição: só cartas listadas em AT_POSITION. */
export function unassignIntent(collectionId: string, positionId: string, here: CopiesPage | null, copy: EditorPokedexCopy): WriteIntent | null {
  if (!fromPage(here, collectionId, positionId) || here!.scope !== "AT_POSITION" || !inPage(here!, copy)) return null;
  return { kind: "unassign", collectionId: collectionId.toLowerCase(), copyToken: copy.token, expectedPositionId: positionId.toLowerCase() };
}

/**
 * Escolher a representante. Estado esperado da representante: o token da escolhida
 * se a tela viu CHOSEN; NULL se viu a escolha AUTOMÁTICA (contrato da 5392). Exige a
 * 1ª página de AT_POSITION (é ela que traz a representante efetiva).
 */
export function chooseIntent(collectionId: string, positionId: string, here: CopiesPage | null, copy: EditorPokedexCopy): WriteIntent | null {
  if (!fromPage(here, collectionId, positionId) || here!.scope !== "AT_POSITION" || here!.offset !== 0 || !inPage(here!, copy)) return null;
  const seen = seenRepresentative(here!);
  if (!seen) return null;
  if (seen.mode === "CHOSEN" && seen.token === copy.token) return null; // já é a escolhida
  return {
    kind: "choose",
    collectionId: collectionId.toLowerCase(),
    copyToken: copy.token,
    expectedPositionId: positionId.toLowerCase(),
    expectedRepresentativeToken: seen.mode === "CHOSEN" ? seen.token : null,
  };
}

/** Voltar à escolha automática: só quando a tela viu uma representante ESCOLHIDA (o servidor exige o token dela). */
export function restoreIntent(collectionId: string, positionId: string, here: CopiesPage | null): WriteIntent | null {
  if (!fromPage(here, collectionId, positionId) || here!.scope !== "AT_POSITION" || here!.offset !== 0) return null;
  const seen = seenRepresentative(here!);
  if (!seen || seen.mode !== "CHOSEN") return null;
  return { kind: "restore", collectionId: collectionId.toLowerCase(), positionId: positionId.toLowerCase(), expectedRepresentativeToken: seen.token };
}

/** Revalidação estrutural da intenção recebida pela server action (o cliente nunca é confiável). */
export function isWriteIntent(v: unknown): v is WriteIntent {
  if (!v || typeof v !== "object" || Array.isArray(v)) return false;
  const i = v as Record<string, unknown>;
  const keys = Object.keys(i).sort().join(",");
  if (!isUuid(i.collectionId)) return false;
  switch (i.kind) {
    case "move":
      return keys === "collectionId,confirmOverride,copyToken,expectedPositionId,kind,targetPositionId" && isCopyToken(i.copyToken) && isUuid(i.targetPositionId)
        && (i.expectedPositionId === null || isUuid(i.expectedPositionId)) && typeof i.confirmOverride === "boolean";
    case "unassign":
      return keys === "collectionId,copyToken,expectedPositionId,kind" && isCopyToken(i.copyToken) && isUuid(i.expectedPositionId);
    case "choose":
      return keys === "collectionId,copyToken,expectedPositionId,expectedRepresentativeToken,kind" && isCopyToken(i.copyToken) && isUuid(i.expectedPositionId)
        && (i.expectedRepresentativeToken === null || isCopyToken(i.expectedRepresentativeToken));
    case "restore":
      return keys === "collectionId,expectedRepresentativeToken,kind,positionId" && isUuid(i.positionId) && isCopyToken(i.expectedRepresentativeToken);
    default:
      return false;
  }
}

// ---------------------------------------------------------------------------
// Uma ação por vez no painel inteiro

export type Busy = { kind: "idle" } | { kind: "reading" } | { kind: "writing"; intent: IntentKind; token: CopyToken | null };

export function isBusy(b: Busy): boolean {
  return b.kind !== "idle";
}

/** Começa uma escrita; null = já há uma ação em andamento (o clique é ignorado). */
export function beginWrite(b: Busy, intent: WriteIntent): Busy | null {
  if (isBusy(b)) return null;
  return { kind: "writing", intent: intent.kind, token: intent.kind === "restore" ? null : intent.copyToken };
}

// ---------------------------------------------------------------------------
// Reação à resposta

export type PanelReaction = {
  /** Mensagem para o colecionador (sem ids nem tokens). */
  message: string;
  tone: "success" | "neutral" | "warning" | "error";
  /** Reler as duas listas (fresca: novos tokens e novo estado esperado). */
  reload: boolean;
  /** Descartar tokens/listas anteriores ANTES de reler. */
  dropTokens: boolean;
  /** Pedir confirmação explícita da exceção de espécie e só então reenviar. */
  askConfirmation: boolean;
  /** Ações ficam indisponíveis no painel. */
  disable: boolean;
  /** Houve escrita confirmada pelo servidor (a grade precisa ser atualizada ao fechar). */
  changed: boolean;
};

export function reactToSuccess(changed: boolean, message: string): PanelReaction {
  return { message, tone: changed ? "success" : "neutral", reload: true, dropTokens: true, askConfirmation: false, disable: false, changed };
}

export function reactToFailure(reason: EditorPokedexFailure): PanelReaction & { policy: FailurePolicy } {
  const policy = failurePolicy(reason);
  return {
    policy,
    message: policy.message,
    tone: policy.requireConfirmation ? "warning" : "error",
    reload: policy.reloadState,
    dropTokens: policy.invalidateTokens,
    askConfirmation: policy.requireConfirmation,
    disable: policy.disables,
    changed: false,
  };
}

/** Mensagem neutra de lista vazia (zero linhas também pode ser falta de acesso; nunca afirma "nenhuma"). */
export function emptyListMessage(scope: "AT_POSITION" | "ASSIGNABLE", searching: boolean): string {
  if (scope === "AT_POSITION") return "Nenhuma carta aparece nesta posição agora.";
  return searching ? "Nenhuma carta da coleção corresponde a esta busca." : "Nenhuma outra carta da coleção aparece para esta posição agora.";
}

/** Rótulo do botão de uma carta disponível: colocar (sem posição) ou mover (vem de outra posição). */
export function moveLabel(copy: EditorPokedexCopy): string {
  return copy.currentPositionId === null ? "Colocar aqui" : "Mover para cá";
}

/** Linha de contexto da carta disponível: de onde ela sai. */
export function originLine(copy: EditorPokedexCopy): string {
  if (copy.currentPositionId === null) return "Sem posição na Pokédex";
  return copy.currentPositionNumber !== null ? `Hoje na posição nº ${String(copy.currentPositionNumber).padStart(4, "0")}` : "Hoje em outra posição";
}

// ---------------------------------------------------------------------------
// F3-3 — consistência e concorrência. Um único fluxo para painel e grade:
// toda resposta passa por `planAfter`, que decide reler o painel, descartar
// tokens e atualizar a grade (página do servidor); nada é otimista.

/** Junta a próxima página de ASSIGNABLE à lista mostrada, para que TODA carta visível tenha intenção válida. */
export function mergeCopiesPages(prev: CopiesPage, next: CopiesPage): CopiesPage | null {
  if (prev.scope !== next.scope || prev.collectionId !== next.collectionId || prev.positionId !== next.positionId) return null;
  if (next.offset !== prev.offset + prev.items.length) return null;
  const known = new Set(prev.items.map((i) => i.token));
  if (next.items.some((i) => known.has(i.token))) return null; // a ordem mudou entre as páginas: reler
  return { ...prev, items: [...prev.items, ...next.items], total: next.total, hasMore: next.hasMore };
}

/** Confirmação de exceção de espécie: congelada na intenção ORIGINAL (mesmo estado esperado) e na geração da lista. */
export type PendingConfirmation = { intent: Extract<WriteIntent, { kind: "move" }>; generation: number; cardName: string; fromLine: string };

export function prepareConfirmation(
  collectionId: string,
  positionId: string,
  assignable: CopiesPage | null,
  refused: WriteIntent,
  generation: number,
): PendingConfirmation | null {
  if (refused.kind !== "move" || refused.confirmOverride || !assignable) return null;
  const copy = assignable.items.find((i) => i.token === refused.copyToken);
  if (!copy || copy.currentPositionId !== refused.expectedPositionId) return null;
  const again = moveIntent(collectionId, positionId, assignable, copy, true);
  if (!again || again.kind !== "move" || again.expectedPositionId !== refused.expectedPositionId || again.targetPositionId !== refused.targetPositionId) return null;
  return { intent: again, generation, cardName: copy.cardName, fromLine: originLine(copy) };
}

/** A confirmação só vale na MESMA geração da lista em que foi pedida; depois de qualquer releitura, é descartada. */
export function confirmationUsable(pc: PendingConfirmation | null, generation: number): pc is PendingConfirmation {
  return !!pc && pc.generation === generation && pc.intent.confirmOverride === true;
}

export type Outcome = { ok: true; changed: boolean } | { ok: false; reason: EditorPokedexFailure };

export type AfterPlan = {
  /** Reler as duas listas do painel (tokens e estado esperado novos). */
  reloadPanel: boolean;
  /** Descartar tokens/listas e a confirmação pendente ANTES de reler. */
  dropTokens: boolean;
  /** Atualizar a grade pela página do servidor (posições de origem e destino incluídas). */
  refreshGrid: boolean;
  /** Alteração confirmada pelo servidor. */
  confirmed: boolean;
  /** Pode ter sido gravado (resposta ilegível). */
  uncertain: boolean;
  /** Pedir confirmação explícita (sem reler: nada foi gravado). */
  askConfirmation: boolean;
  /** Ações indisponíveis no painel. */
  disable: boolean;
};

export function planAfter(o: Outcome): AfterPlan {
  if (o.ok) return { reloadPanel: true, dropTokens: true, refreshGrid: o.changed, confirmed: o.changed, uncertain: false, askConfirmation: false, disable: false };
  const p = failurePolicy(o.reason);
  // F3-5: posição fora da Pokédex desta coleção (ex.: gerações mudaram) também bloqueia as ações do painel.
  const positionGone = o.reason === "position_not_found";
  // Conflito, token obsoleto ou resultado incerto: outra pessoa (ou esta escrita) pode ter mudado a
  // coleção — o painel e a grade voltam ao estado do servidor, e o usuário decide de novo.
  const concurrent = o.reason === "state_changed" || o.reason === "copy_not_found" || o.reason === "position_not_found" || o.reason === "unknown";
  return {
    reloadPanel: concurrent,
    dropTokens: p.invalidateTokens || concurrent,
    refreshGrid: concurrent,
    confirmed: false,
    uncertain: p.uncertain,
    askConfirmation: p.requireConfirmation,
    disable: p.disables || positionGone,
  };
}

/**
 * Estado visual depois da releitura: "confirmada, visual pendente" nunca vira fracasso.
 * - synced: listas relidas;
 * - confirmed_stale: a escrita foi confirmada, mas a releitura falhou (ações suspensas até atualizar);
 * - stale: a releitura falhou sem escrita confirmada.
 */
export type SyncState = "synced" | "confirmed_stale" | "stale";

export function syncAfterReload(confirmed: boolean, reloadOk: boolean): SyncState {
  if (reloadOk) return "synced";
  return confirmed ? "confirmed_stale" : "stale";
}

export function syncMessage(s: SyncState): string | null {
  switch (s) {
    case "confirmed_stale":
      return "A alteração foi confirmada, mas não conseguimos atualizar as cartas agora. Atualize para ver o estado atual antes de continuar.";
    case "stale":
      return "Não conseguimos atualizar as cartas agora. Atualize antes de continuar.";
    default:
      return null;
  }
}

/** Ações do painel liberadas? Nunca durante escrita, com o painel desligado ou com a visualização desatualizada. */
export function actionsEnabled(i: { busy: Busy; disabled: boolean; sync: SyncState; loading: boolean }): boolean {
  return !isBusy(i.busy) && !i.disabled && i.sync === "synced" && !i.loading;
}

// ---------------------------------------------------------------------------
// F3-5 — estados excepcionais: classe da falha, título, leitura e bloqueio.

/**
 * A: acesso (sessão, permissão, arquivada, barreira, coleção/posição fora do alcance) — sem repetição;
 * B: conflito recuperável (estado mudou, token obsoleto) — reler e decidir de novo;
 * C: incerto (resposta ilegível ou sem resposta) — conferir antes de qualquer nova escrita;
 * D: recusa sem escrita (confirmação, trava ocupada, pedido inválido).
 */
export type FailureClass = "access" | "conflict" | "uncertain" | "refused";

export function failureClass(reason: EditorPokedexFailure): FailureClass {
  switch (reason) {
    case "barrier_closed":
    case "unavailable":
    case "not_authenticated":
    case "access_lost":
    case "archived":
    case "not_pokedex":
    case "position_not_found":
      return "access";
    case "state_changed":
    case "copy_not_found":
      return "conflict";
    case "unknown":
      return "uncertain";
    default:
      return "refused";
  }
}

/** Título do aviso de uma escrita recusada: nunca "Nada foi alterado" quando o resultado é incerto. */
export function writeNoticeTitle(reason: EditorPokedexFailure): string {
  switch (failureClass(reason)) {
    case "access":
      return "Ação indisponível";
    case "conflict":
      return "A posição mudou";
    case "uncertain":
      return "Resultado não confirmado";
    default:
      return reason === "confirmation_required" ? "Confirme antes de continuar" : "Nada foi alterado";
  }
}

export type ReadFailure = { message: string; retry: boolean; blocks: boolean };

const READ_FAILED = "Não conseguimos carregar as cartas agora. Tente de novo em instantes.";

/**
 * Falha de LEITURA (5391): nunca vira "nenhuma carta". Bloqueios de acesso desligam o painel e
 * escondem os dados anteriores; falhas transitórias (comunicação, resposta inválida, trava) permitem
 * nova consulta — que é só leitura, nunca uma escrita repetida.
 */
export function readFailure(reason: EditorPokedexFailure | "disabled"): ReadFailure {
  const r: EditorPokedexFailure = reason === "disabled" ? "unavailable" : reason;
  if (failureClass(r) === "access") return { message: failurePolicy(r).message, retry: false, blocks: true };
  if (r === "invalid") return { message: "Não conseguimos carregar as cartas desta posição.", retry: false, blocks: false };
  return { message: READ_FAILED, retry: true, blocks: false };
}

/** Linha de estado do topo do painel, sem afirmar "Falta" quando zero linhas podem ser falta de acesso. */
export function positionStateLine(here: { status: "loading" } | { status: "error" | "blocked" } | { status: "ready"; total: number }): string {
  if (here.status === "loading") return "Conferindo as cartas desta posição…";
  if (here.status !== "ready") return "Não conseguimos conferir as cartas desta posição agora.";
  if (here.total === 0) return "Nenhuma carta aparece nesta posição agora.";
  return here.total === 1 ? "1 carta nesta posição" : `${here.total.toLocaleString("pt-BR")} cartas nesta posição`;
}
