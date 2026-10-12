// Resolução dos três eixos de uma linha de importação de variantes (P3b).
//
// Contratos de leitura das RPCs da P3a — diagnóstico (Query 2271) e prévia
// (Query 2272) — e as regras puras que a interface aplica sobre eles. Nada
// aqui decide eixo: o banco diagnostica, o administrador classifica, a RPC
// grava. Este arquivo só traduz e protege a interface de estados obsoletos.
//
// Sem dependências de React/Next: testável com node:test
// (lib/catalogo/axis-resolution.test.ts).

export type ResolutionAxis = "FINISH" | "PRINTING" | "EDITION_CONTEXT";
export type MappingAxis = Exclude<ResolutionAxis, "FINISH">;
export type MappingScope = "GLOBAL" | "SOURCE_SET";
export type RawField = "type" | "foil" | "subtype" | "stamp";
export type ItemStatus = "PRINTING" | "EDITION_CONTEXT" | "FINISH" | "UNRECOGNIZED" | "NOT_EVALUATED";

export type NamedRef = { id: string; code: string; name: string };

export type ExplainItem = {
  field: RawField;
  raw: string;
  normalized: string;
  allowedAxes: ResolutionAxis[];
  printingMapping: { id: string; active: boolean; traits: NamedRef[] } | null;
  editionContextMapping: { id: string; active: boolean; scope: MappingScope; traits: NamedRef[] } | null;
  inFinishResidual: boolean | null;
  status: ItemStatus;
};

export type AxisState = {
  state: string;
  profile: (NamedRef & { isActive: boolean }) | null;
  traits: NamedRef[];
};

export type RowDiagnosis = {
  rowId: string;
  externalSetId: string | null;
  validationStatus: string;
  outcome: "A" | "B" | "C";
  printing: AxisState;
  editionContext: AxisState;
  finish: {
    evaluated: boolean;
    residual: { type: string | null; foil: string | null; subtype: string | null; stamp: string[] };
    variantType: NamedRef | null;
  };
  items: ExplainItem[];
};

type Json = Record<string, unknown>;

function str(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function refs(value: unknown): NamedRef[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((v): v is Json => typeof v === "object" && v !== null)
    .map((v) => ({ id: String(v.id), code: String(v.code ?? ""), name: String(v.name ?? "") }));
}

function axisState(value: unknown): AxisState {
  const v = (value ?? {}) as Json;
  const p = v.profile as Json | null | undefined;
  return {
    state: String(v.state ?? ""),
    profile: p
      ? { id: String(p.id), code: String(p.code ?? ""), name: String(p.name ?? ""), isActive: p.is_active === true }
      : null,
    traits: refs(v.traits),
  };
}

/** Converte o jsonb da Query 2271 no tipo da interface. Campos ausentes viram neutros, nunca inventados. */
export function parseRowDiagnosis(data: unknown): RowDiagnosis {
  const d = (data ?? {}) as Json;
  const finish = (d.finish ?? {}) as Json;
  const residual = (finish.residual ?? {}) as Json;
  const vt = finish.variant_type as Json | null | undefined;
  const items = Array.isArray(d.items) ? (d.items as Json[]) : [];
  return {
    rowId: String(d.row_id ?? ""),
    externalSetId: str(d.external_set_id),
    validationStatus: String(d.validation_status ?? ""),
    outcome: d.outcome === "A" || d.outcome === "C" ? d.outcome : "B",
    printing: axisState(d.printing),
    editionContext: axisState(d.edition_context),
    finish: {
      evaluated: finish.evaluated === true,
      residual: {
        type: str(residual.type),
        foil: str(residual.foil),
        subtype: str(residual.subtype),
        stamp: Array.isArray(residual.stamp) ? residual.stamp.map(String) : [],
      },
      variantType: vt ? { id: String(vt.id), code: String(vt.code ?? ""), name: String(vt.name ?? "") } : null,
    },
    items: items.map((i) => {
      const pm = i.printing_mapping as Json | null | undefined;
      const em = i.edition_context_mapping as Json | null | undefined;
      return {
        field: String(i.field) as RawField,
        raw: String(i.raw ?? ""),
        normalized: String(i.normalized ?? ""),
        allowedAxes: Array.isArray(i.allowed_axes) ? (i.allowed_axes as ResolutionAxis[]) : [],
        printingMapping: pm ? { id: String(pm.id), active: pm.active === true, traits: refs(pm.traits) } : null,
        editionContextMapping: em
          ? {
              id: String(em.id),
              active: em.active === true,
              scope: em.scope === "GLOBAL" ? "GLOBAL" : "SOURCE_SET",
              traits: refs(em.traits),
            }
          : null,
        inFinishResidual: typeof i.in_finish_residual === "boolean" ? i.in_finish_residual : null,
        status: String(i.status ?? "NOT_EVALUATED") as ItemStatus,
      };
    }),
  };
}

export type PreviewRow = {
  rowId: string;
  before: string | null;
  after: string;
  reason: string | null;
};

export type AxisPreview = {
  ok: boolean;
  error: string | null;
  scope: MappingScope;
  externalSetId: string | null;
  targetProfile: (NamedRef & { isActive: boolean }) | null;
  superseded: { id: string; scope: MappingScope; externalSetId: string | null } | null;
  scopedOverrides: string[];
  conflicts: { code: string; scopes: string[] }[];
  finishMappingsReferencingToken: number;
  impact: {
    rowsTouched: number;
    jobs: number;
    cardSets: number;
    resolved: number | null;
    pending: number | null;
    newlyResolved: number | null;
    regressed: number | null;
    pendingByReason: Record<string, number>;
  };
  rows: PreviewRow[];
  rowsTruncated: boolean;
};

function num(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : Number(value ?? 0) || 0;
}

function numOrNull(value: unknown): number | null {
  return value === undefined || value === null ? null : num(value);
}

/** Converte o jsonb da Query 2272. `error` é a mensagem crua do banco; traduza na action. */
export function parseAxisPreview(data: unknown): AxisPreview {
  const d = (data ?? {}) as Json;
  const target = ((d.target ?? {}) as Json).profile as Json | null | undefined;
  const sup = d.superseded as Json | null | undefined;
  const impact = (d.impact ?? {}) as Json;
  const byReason = (impact.pending_by_reason ?? {}) as Json;
  return {
    ok: d.ok === true,
    error: str(d.error),
    scope: d.scope === "SOURCE_SET" ? "SOURCE_SET" : "GLOBAL",
    externalSetId: str(d.external_set_id),
    targetProfile: target
      ? {
          id: String(target.id),
          code: String(target.code ?? ""),
          name: String(target.name ?? ""),
          isActive: target.is_active === true,
        }
      : null,
    superseded: sup
      ? {
          id: String(sup.id),
          scope: sup.scope === "SOURCE_SET" ? "SOURCE_SET" : "GLOBAL",
          externalSetId: str(sup.external_set_id),
        }
      : null,
    scopedOverrides: Array.isArray(d.scoped_overrides) ? d.scoped_overrides.map(String) : [],
    conflicts: Array.isArray(d.conflicts)
      ? (d.conflicts as Json[]).map((c) => ({
          code: String(c.code),
          scopes: Array.isArray(c.scopes) ? c.scopes.map(String) : [],
        }))
      : [],
    finishMappingsReferencingToken: num(d.finish_mappings_referencing_token),
    impact: {
      rowsTouched: num(impact.rows_touched),
      jobs: num(impact.jobs),
      cardSets: num(impact.card_sets),
      resolved: numOrNull(impact.resolved),
      pending: numOrNull(impact.pending),
      newlyResolved: numOrNull(impact.newly_resolved),
      regressed: numOrNull(impact.regressed),
      pendingByReason: Object.fromEntries(Object.entries(byReason).map(([k, v]) => [k, num(v)])),
    },
    rows: Array.isArray(d.rows)
      ? (d.rows as Json[]).map((r) => ({
          rowId: String(r.row_id),
          before: str(r.before),
          after: String(r.after ?? ""),
          reason: str(r.reason),
        }))
      : [],
    rowsTruncated: d.rows_truncated === true,
  };
}

// ---------------------------------------------------------------------------
// Linguagem do administrador
// ---------------------------------------------------------------------------

export const AXIS_LABEL: Record<ResolutionAxis, string> = {
  FINISH: "Acabamento",
  PRINTING: "Impressão",
  EDITION_CONTEXT: "Contexto de Edição",
};

export const FIELD_LABEL: Record<RawField, string> = {
  type: "Tipo",
  foil: "Foil",
  subtype: "Subtipo",
  stamp: "Selo",
};

/** Rótulo de status de um item. UNRECOGNIZED nunca sugere eixo. */
export function itemStatusLabel(status: ItemStatus): string {
  switch (status) {
    case "PRINTING":
      return "Impressão";
    case "EDITION_CONTEXT":
      return "Contexto de Edição";
    case "FINISH":
      return "Acabamento";
    case "UNRECOGNIZED":
      return "Não reconhecido";
    default:
      return "Não avaliado";
  }
}

const STATE_LABEL: Record<string, string> = {
  RESOLVED_NO_PRINTING: "Sem impressão especial",
  RESOLVED_WITH_PROFILE: "Resolvida",
  RESOLVED_NO_EDITION_CONTEXT: "Sem contexto especial",
  RESOLVED_WITH_EC_PROFILE: "Resolvido",
  NEEDS_REVIEW_NO_PROFILE: "Sem perfil para estas características",
  NEEDS_REVIEW_INACTIVE_PROFILE: "Perfil inativo",
  NEEDS_REVIEW_INACTIVE_TRAIT: "Característica inativa",
  NEEDS_REVIEW_INACTIVE_MAPPING: "Mapeamento inativo",
  NEEDS_REVIEW_INVALID_PRINTING_MAPPING: "Mapeamento inválido",
  NEEDS_REVIEW_NO_EC_PROFILE: "Sem perfil para estas características",
  NEEDS_REVIEW_INACTIVE_EC_PROFILE: "Perfil inativo",
  NEEDS_REVIEW_INACTIVE_EC_TRAIT: "Característica inativa",
  NEEDS_REVIEW_INACTIVE_EC_MAPPING: "Mapeamento inativo",
  NEEDS_REVIEW_INVALID_EC_MAPPING: "Mapeamento inválido",
  FINISH_NOT_MAPPED: "Acabamento sem mapeamento",
};

export function axisStateLabel(state: string): string {
  return STATE_LABEL[state] ?? state;
}

export function isAxisStateResolved(state: string): boolean {
  return state.startsWith("RESOLVED_");
}

const CONFLICT_LABEL: Record<string, string> = {
  PRINTING_ACTIVE:
    "Este item já está mapeado como Impressão. Um item não pode ser Impressão e Contexto de Edição ao mesmo tempo.",
  EDITION_CONTEXT_ACTIVE:
    "Este item já está mapeado como Contexto de Edição. Um item não pode ser Contexto de Edição e Impressão ao mesmo tempo.",
  NO_CHANGE: "O mapeamento ativo deste item, neste escopo, já tem exatamente estas características.",
};

export function conflictLabel(code: string): string {
  return CONFLICT_LABEL[code] ?? code;
}

// ---------------------------------------------------------------------------
// Regras da interface
// ---------------------------------------------------------------------------

/** Item que a interface oferece para classificar: tudo menos `type`, que só pode ser acabamento. */
export function isClassifiableItem(item: ExplainItem): boolean {
  return item.allowedAxes.some((axis) => axis !== "FINISH");
}

/** Eixo atual de um item já mapeado — usado para pré-selecionar, nunca para presumir um desconhecido. */
export function currentItemAxis(item: ExplainItem): ResolutionAxis | null {
  if (item.status === "PRINTING" || item.status === "EDITION_CONTEXT" || item.status === "FINISH") return item.status;
  return null;
}

export function sortedIds(ids: readonly string[]): string[] {
  return Array.from(new Set(ids)).sort();
}

export function sameIdSet(a: readonly string[], b: readonly string[]): boolean {
  const sa = sortedIds(a);
  const sb = sortedIds(b);
  return sa.length === sb.length && sa.every((v, i) => v === sb[i]);
}

export type AxisProfileOption = NamedRef & { displayOrder: number; traitIds: string[] };

/** Perfil ativo cuja composição é exatamente a escolhida (a composição é a identidade do perfil). */
export function findProfileBySignature(
  profiles: readonly AxisProfileOption[],
  traitIds: readonly string[],
): AxisProfileOption | null {
  if (traitIds.length === 0) return null;
  return profiles.find((p) => sameIdSet(p.traitIds, traitIds)) ?? null;
}

export function nextDisplayOrder(profiles: readonly AxisProfileOption[]): number {
  return profiles.reduce((max, p) => Math.max(max, p.displayOrder), 0) + 1;
}

export type MappingDraft = {
  axis: MappingAxis;
  field: RawField;
  token: string;
  traitIds: string[];
  scope: MappingScope;
};

/**
 * Impressão digital do que foi simulado. A prévia só vale para o rascunho que
 * a gerou: qualquer mudança de eixo, item, características ou escopo a torna
 * obsoleta e a confirmação volta a exigir nova simulação.
 */
export function draftFingerprint(draft: MappingDraft): string {
  return JSON.stringify([draft.axis, draft.field, draft.token, sortedIds(draft.traitIds), draft.scope]);
}

/** Impressão é sempre global; Contexto começa no Set e só vai a global por escolha explícita. */
export function effectiveScope(axis: MappingAxis, requested: MappingScope): MappingScope {
  return axis === "PRINTING" ? "GLOBAL" : requested;
}

/** Motivos de pendência que a criação do perfil novo resolve (a prévia roda antes do perfil existir). */
export function isMissingProfileReason(reason: string): boolean {
  return reason === "NEEDS_REVIEW_NO_PROFILE" || reason === "NEEDS_REVIEW_NO_EC_PROFILE";
}

const PROFILE_CODE_RE = /^[A-Z][A-Z0-9_]*$/;

export function normalizeProfileCode(code: string): string {
  return code.trim().toUpperCase();
}

export function isValidProfileCode(code: string): boolean {
  return PROFILE_CODE_RE.test(normalizeProfileCode(code));
}
