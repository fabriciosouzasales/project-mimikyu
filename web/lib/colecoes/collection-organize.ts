import { formatCount, pluralize } from "./acervo.ts";

/**
 * WHERE-05A — organizar fisicamente os exemplares de uma coleção no local
 * padrão dela (regras puras; sem banco, sem React — testável com `node --test`).
 *
 * Contratos (LIVE, canônicos em database/schema/):
 *  - `5221 get_my_collection_storage_plan(collection, destino)` — prévia: uma
 *    linha com as contagens dos exemplares ALOCADOS à coleção e o `plan_token`;
 *  - `5222 organize_my_collection_storage(collection, destino, modalidade,
 *    quantidade esperada, plan_token)` — tudo ou nada; recalcula sob trava e
 *    recusa (`PLAN_CHANGED`) se algo mudou desde a prévia.
 *
 * Princípios (NS-13, NS-15, D1–D6):
 *  - trocar o local padrão NUNCA move exemplar; mover exige escolha e
 *    confirmação explícitas;
 *  - a contagem vem da 5221 (exemplares físicos), nunca da galeria;
 *  - `UNLOCATED` é a modalidade conservadora e a pré-selecionada; `ALL` nunca
 *    entra no lugar dela em silêncio;
 *  - o navegador não monta lista de exemplares nem divide em lotes.
 */

export type OrganizeMode = "UNLOCATED" | "ALL";

/** Uma linha da 5221 em camelCase. */
export type OrganizePlan = {
  collectionId: string;
  storageContainerId: string;
  collectionActive: boolean;
  targetIsDefault: boolean;
  totalCount: number;
  unlocatedCount: number;
  atTargetCount: number;
  elsewhereCount: number;
  eligibleUnlocated: number;
  eligibleAll: number;
  maxPerOperation: number;
  planToken: string;
};

export const PLAN_TOKEN = /^v1:[0-9a-f]{32}$/;

function count(value: unknown): number | null {
  const n = typeof value === "string" ? Number(value) : value;
  return typeof n === "number" && Number.isInteger(n) && n >= 0 ? n : null;
}

/** Converte a linha da 5221 — `null` se o formato não bate (nunca adivinha números). */
export function parseOrganizePlan(row: unknown): OrganizePlan | null {
  if (!row || typeof row !== "object") return null;
  const r = row as Record<string, unknown>;
  const nums = {
    totalCount: count(r.total_count),
    unlocatedCount: count(r.unlocated_count),
    atTargetCount: count(r.at_target_count),
    elsewhereCount: count(r.elsewhere_count),
    eligibleUnlocated: count(r.eligible_unlocated),
    eligibleAll: count(r.eligible_all),
    maxPerOperation: count(r.max_per_operation),
  };
  if (Object.values(nums).some((n) => n === null)) return null;
  if (
    typeof r.collection_id !== "string" ||
    typeof r.storage_container_id !== "string" ||
    typeof r.collection_active !== "boolean" ||
    typeof r.target_is_default !== "boolean" ||
    typeof r.plan_token !== "string" ||
    !PLAN_TOKEN.test(r.plan_token)
  ) {
    return null;
  }
  return {
    collectionId: r.collection_id,
    storageContainerId: r.storage_container_id,
    collectionActive: r.collection_active,
    targetIsDefault: r.target_is_default,
    planToken: r.plan_token,
    ...(nums as Record<keyof typeof nums, number>),
  };
}

/**
 * Situação da prévia, em ordem de precedência:
 *  - `archived` — coleção arquivada (a 5222 recusaria);
 *  - `not_default` — o destino deixou de ser o local padrão (D2);
 *  - `too_large` — mais exemplares alocados que o teto por operação (D6:
 *    a 5222 recusa pelo TOTAL, antes de olhar a modalidade);
 *  - `empty` — nenhum exemplar vinculado à coleção;
 *  - `all_at_target` — todos já estão no destino;
 *  - `ready` — há o que organizar.
 */
export type PlanVerdict = "archived" | "not_default" | "too_large" | "empty" | "all_at_target" | "ready";

export function planVerdict(plan: OrganizePlan): PlanVerdict {
  if (!plan.collectionActive) return "archived";
  if (!plan.targetIsDefault) return "not_default";
  if (plan.totalCount > plan.maxPerOperation) return "too_large";
  if (plan.totalCount === 0) return "empty";
  if (plan.eligibleAll === 0) return "all_at_target";
  return "ready";
}

/**
 * Proposta automática logo após salvar o local padrão: só quando há o que
 * organizar. Coleção vazia, tudo no destino, arquivada ou destino divergente
 * → nada aparece (o salvamento já foi confirmado). Acima do teto → só um
 * aviso discreto (ver `limitNotice`), nunca a proposta.
 */
export function autoProposalKind(plan: OrganizePlan): "propose" | "limit_notice" | "none" {
  const verdict = planVerdict(plan);
  if (verdict === "ready") return "propose";
  if (verdict === "too_large") return "limit_notice";
  return "none";
}

export function eligibleFor(plan: OrganizePlan, mode: OrganizeMode): number {
  return mode === "UNLOCATED" ? plan.eligibleUnlocated : plan.eligibleAll;
}

/** Quantos exemplares sairão de OUTRO local (só a modalidade `ALL` retira). */
export function leavingOtherPlaces(plan: OrganizePlan, mode: OrganizeMode): number {
  return mode === "ALL" ? plan.elsewhereCount : 0;
}

export type ModeOption = {
  mode: OrganizeMode;
  title: string;
  description: string;
  count: number;
  available: boolean;
  /** Por que está indisponível (só quando `available` é falso). */
  unavailableReason: string | null;
};

export function modeOptions(plan: OrganizePlan): ModeOption[] {
  return [
    {
      mode: "UNLOCATED",
      title: "Apenas cartas sem localização",
      description: "Organiza os exemplares ainda sem localização física, preservando aqueles que já estão guardados em outros locais.",
      count: plan.eligibleUnlocated,
      available: plan.eligibleUnlocated > 0,
      unavailableReason: plan.eligibleUnlocated > 0 ? null : "Todos os exemplares desta coleção já têm um local definido.",
    },
    {
      mode: "ALL",
      title: "Todas as cartas desta coleção",
      description:
        "Organiza no local escolhido todos os exemplares vinculados à coleção que ainda não estão nele, inclusive os guardados em outros locais.",
      count: plan.eligibleAll,
      available: plan.eligibleAll > 0,
      unavailableReason: plan.eligibleAll > 0 ? null : "Todas as cartas desta coleção já estão neste local.",
    },
  ];
}

/**
 * Modalidade pré-selecionada: sempre a conservadora (`UNLOCATED`) quando
 * disponível. Sem exemplares sem localização → nenhuma pré-seleção: `ALL`
 * só vale se o colecionador escolher.
 */
export function defaultMode(plan: OrganizePlan): OrganizeMode | null {
  return plan.eligibleUnlocated > 0 ? "UNLOCATED" : null;
}

/** Após uma nova prévia: mantém a escolha se ainda fizer sentido; senão volta ao padrão. */
export function reconcileMode(plan: OrganizePlan, previous: OrganizeMode | null): OrganizeMode | null {
  if (previous && eligibleFor(plan, previous) > 0) return previous;
  return defaultMode(plan);
}

// ---------------------------------------------------------------------------
// Textos do colecionador
// ---------------------------------------------------------------------------

/** "neste fichário", "nesta caixa"… — pelo tipo do local (5212); sem tipo → "neste local". */
export function placePhrase(kindCode: string | null | undefined): string {
  switch (kindCode) {
    case "BINDER":
      return "neste fichário";
    case "BOX":
      return "nesta caixa";
    case "FOLDER":
      return "nesta pasta";
    case "DECK_BOX":
      return "neste deck box";
    case "ETB":
      return "neste ETB";
    case "CASE":
      return "nesta maleta";
    case "SAFE":
      return "neste cofre";
    default:
      return "neste local";
  }
}

export function proposalTitle(kindCode: string | null | undefined): string {
  return `Organizar cartas ${placePhrase(kindCode)}?`;
}

/** Ação posterior em Ajustes → Onde guardo. */
export function laterActionLabel(kindCode: string | null | undefined): string {
  return `Organizar cartas ${placePhrase(kindCode)}`;
}

export type ProposalOrigin = "after_save" | "later";

export function proposalSubtitle(origin: ProposalOrigin): string {
  return origin === "after_save"
    ? "O local padrão da coleção foi atualizado."
    : "Guarde no local padrão da coleção os exemplares que você escolher.";
}

export function exemplares(n: number): string {
  return pluralize(n, "exemplar", "exemplares");
}

/** "Você está prestes a organizar 42 exemplares em F001 — Fichário ME5.5." */
export function confirmationSentence(count: number, targetName: string): string {
  return `Você está prestes a organizar ${exemplares(count)} em ${targetName}.`;
}

/** Só para `ALL` com saídas: "Destes, 12 serão retirados de outros locais físicos." */
export function leavingSentence(leaving: number): string | null {
  if (leaving <= 0) return null;
  return leaving === 1
    ? "Destes, 1 será retirado de outro local físico."
    : `Destes, ${formatCount(leaving)} serão retirados de outros locais físicos.`;
}

/** Resultado com o número DEVOLVIDO pela 5222 (nunca o esperado). */
export function resultSentence(moved: number, targetName: string): string {
  if (moved === 0) return `Nenhum exemplar precisou mudar de lugar — tudo já estava em ${targetName}.`;
  return moved === 1
    ? `1 exemplar agora está guardado em ${targetName}.`
    : `${formatCount(moved)} exemplares agora estão guardados em ${targetName}.`;
}

/** "6 de 6 exemplares desta coleção estão neste local." */
export function atTargetSentence(atTarget: number, total: number): string {
  return `${formatCount(atTarget)} de ${exemplares(total)} desta coleção ${atTarget === 1 ? "está" : "estão"} neste local.`;
}

export function verdictMessage(verdict: Exclude<PlanVerdict, "ready">, plan: Pick<OrganizePlan, "maxPerOperation">): string {
  switch (verdict) {
    case "empty":
      return "Nenhuma carta vinculada a esta coleção.";
    case "all_at_target":
      return "Todas as cartas desta coleção já estão neste local.";
    case "archived":
      return "Esta coleção está arquivada. Reative-a para organizar as cartas.";
    case "not_default":
      return "Este local não é mais o padrão da coleção. Confira o destino em Onde guardo antes de organizar.";
    case "too_large":
      return limitNotice(plan.maxPerOperation);
  }
}

export function limitNotice(max: number): string {
  return `A organização em lote não está disponível para esta coleção: ela tem mais de ${exemplares(max)} vinculados. Você ainda pode definir o local de cada carta no Meu acervo.`;
}

// ---------------------------------------------------------------------------
// Erros contratuais (5221/5222) — o texto cru do banco nunca chega ao usuário
// ---------------------------------------------------------------------------

export type OrganizeFailure =
  | "plan_changed"
  | "default_changed"
  | "lock_busy"
  | "too_large"
  | "archived"
  | "not_found"
  | "not_authenticated"
  | "invalid"
  /** Resultado desconhecido (timeout, rede, resposta sem forma): não presumir sucesso nem falha. */
  | "unknown";

export function classifyOrganizeFailure(code: string | null | undefined, message: string | null | undefined): OrganizeFailure {
  const text = message ?? "";
  if (text === "PLAN_CHANGED") return "plan_changed";
  if (text === "DEFAULT_CHANGED") return "default_changed";
  // NOWAIT na trava de exemplar (LOCK_BUSY) ou lock_timeout de 5 s na trava da coleção/destino.
  if (code === "55P03" || text === "LOCK_BUSY") return "lock_busy";
  if (code === "54000" || text === "COLLECTION_TOO_LARGE") return "too_large";
  if (text === "COLLECTION_ARCHIVED") return "archived";
  if (text === "COLLECTION_NOT_FOUND" || text === "STORAGE_NOT_FOUND" || code === "P0002") return "not_found";
  if (code === "28000" || code === "42501" || text === "not_authenticated") return "not_authenticated";
  if (code === "22023" || text === "INVALID_MODE" || text === "INVALID_ARGUMENT") return "invalid";
  return "unknown";
}

/** O que a interface faz depois de cada falha da 5222. */
export type OrganizeRecovery =
  /** Nova prévia e nova confirmação com os números atualizados (nunca repete a escrita). */
  | "refresh_plan"
  /** O padrão mudou: encerra o fluxo e relê "Onde guardo". */
  | "reload_destination"
  /** Mantém a confirmação; o colecionador decide tentar de novo. */
  | "retry_allowed"
  /** Nada a fazer além de explicar. */
  | "stop";

export function recoveryFor(reason: OrganizeFailure): OrganizeRecovery {
  switch (reason) {
    case "plan_changed":
    case "too_large":
    case "archived":
    case "unknown":
      return "refresh_plan";
    case "default_changed":
      return "reload_destination";
    case "lock_busy":
      return "retry_allowed";
    default:
      return "stop";
  }
}

export function organizeFailureMessage(reason: OrganizeFailure): string {
  switch (reason) {
    case "plan_changed":
      return "As cartas desta coleção mudaram desde a prévia. Nada foi movido — confira os números atualizados e confirme de novo.";
    case "default_changed":
      return "O local padrão desta coleção mudou. Nada foi movido — confira o destino antes de organizar.";
    case "lock_busy":
      return "Algumas cartas desta coleção estão sendo alteradas agora. Nada foi movido — aguarde um instante e tente novamente.";
    case "too_large":
      return "Esta coleção passou do limite da organização em lote. Nada foi movido.";
    case "archived":
      return "Esta coleção não está ativa. Nada foi movido.";
    case "not_found":
      return "Esta coleção ou este local não está mais disponível. Nada foi movido.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "invalid":
      return "Algo no pedido não está certo. Nada foi movido — revise e tente de novo.";
    case "unknown":
      return "Não conseguimos confirmar se a organização foi concluída. Conferimos o estado atual das cartas abaixo antes de qualquer nova tentativa.";
  }
}

/** Falha ao montar a prévia (5221): a preferência já salva continua valendo. */
export function planFailureMessage(reason: OrganizeFailure, origin: ProposalOrigin): string {
  if (reason === "not_authenticated") return organizeFailureMessage(reason);
  if (reason === "not_found") return "Esta coleção ou este local não está mais disponível.";
  const base = "Não conseguimos preparar a organização agora. Nenhuma carta foi movida.";
  return origin === "after_save" ? `O local padrão foi salvo. ${base}` : base;
}
