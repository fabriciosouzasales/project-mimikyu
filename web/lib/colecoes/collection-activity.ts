import type { ActivityEvent, ActivityIcon } from "./binder-activity.ts";

/**
 * V1-13 · E3 / F3-4 — histórico da Pokédex da coleção (5395 `get_collection_activity`),
 * regras puras de leitura e apresentação. Distinto do histórico do fichário (5269/5388):
 * aqui só mudanças de posições e representantes da Pokédex.
 *
 * Contrato conferido no SQL implantado (database/schema/5395, 2026-11-27):
 *   get_collection_activity(p_collection_id uuid, p_before_id bigint = null, p_limit int = 50)
 *   → event_id bigint, occurred_at timestamptz, event_type text, origin text,
 *     actor_role text, actor_display_name text, summary jsonb
 *   - barreira primeiro: CLOSED → CAPABILITY_NOT_ENABLED (42501);
 *   - p_limit fora de 1–100 → INVALID_PAGE (22023);
 *   - titular ou participante ACTIVE (EDITOR lê como VIEWER, 5302); removido, pendente ou
 *     recusado, coleção nula ou cursor de outra coleção → ZERO linhas;
 *   - ordem occurred_at desc, id desc; cursor = id do último evento (keyset na mesma coleção);
 *   - nome público do autor resolvido na leitura (user_profile); sem ids de usuário,
 *     exemplar, alocação, local, condição ou valores.
 * Resumos gravados pela 5394 (`collection_activity_record_pokedex` / captura derivada):
 *   ASSIGNED {to, card, basis} · MOVED {from, to, card, basis, representative_cleared} ·
 *   REMOVED {from, card, representative_cleared} · REPRESENTATIVE_SET {position, card} ·
 *   REPLACED {position, card, previous_card} · RESTORED {position, previous_card} ·
 *   POSITIONS_CHANGED (DERIVED) {assigned, removed, representatives_set, representatives_cleared};
 *   posição = {number, species}; carta = {name, number, set, variant?}.
 */

export const POKEDEX_ACTIVITY_TYPES = [
  "POKEDEX_POSITION_ASSIGNED",
  "POKEDEX_POSITION_MOVED",
  "POKEDEX_POSITION_REMOVED",
  "POKEDEX_REPRESENTATIVE_SET",
  "POKEDEX_REPRESENTATIVE_REPLACED",
  "POKEDEX_REPRESENTATIVE_RESTORED",
  "POKEDEX_POSITIONS_CHANGED",
] as const;
export type PokedexActivityType = (typeof POKEDEX_ACTIVITY_TYPES)[number];

export const COLLECTION_ACTIVITY_PAGE_SIZE = 20;
export const COLLECTION_ACTIVITY_RPC = "get_collection_activity";

export type PokedexActorRole = "OWNER" | "EDITOR" | "SYSTEM";

export function isPokedexActivityType(type: string): type is PokedexActivityType {
  return (POKEDEX_ACTIVITY_TYPES as readonly string[]).includes(type);
}

/** Colunas exatas da 5395: qualquer outra (id de usuário, exemplar…) invalida a linha. */
const COLUMNS = ["actor_display_name", "actor_role", "event_id", "event_type", "occurred_at", "origin", "summary"];
const POS_KEYS = ["number", "species"];
const CARD_KEYS = ["name", "number", "set", "variant"];

function obj(v: unknown): Record<string, unknown> | null {
  return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
}

function txt(v: unknown): string | null {
  return typeof v === "string" && v.trim() !== "" ? v : null;
}

function nat(v: unknown): number | null {
  return typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null;
}

type Pos = { number: number; species: string };
type Card = { name: string; number: string | null; set: string | null; variant: string | null };

function pos(v: unknown): Pos | null {
  const o = obj(v);
  if (!o || Object.keys(o).some((k) => !POS_KEYS.includes(k))) return null;
  const number = nat(o.number);
  const species = txt(o.species);
  return number !== null && number > 0 && species ? { number, species } : null;
}

function card(v: unknown): Card | null {
  const o = obj(v);
  if (!o || Object.keys(o).some((k) => !CARD_KEYS.includes(k))) return null;
  const name = txt(o.name);
  return name ? { name, number: txt(o.number), set: txt(o.set), variant: txt(o.variant) } : null;
}

/** Só as chaves conhecidas de cada tipo, já validadas; o que sobrar é descartado (nunca exibido). */
function cleanSummary(type: PokedexActivityType, raw: Record<string, unknown>): Record<string, unknown> | null {
  const basis = raw.basis === "SPECIES_MATCH" || raw.basis === "USER_OVERRIDE" ? raw.basis : null;
  const cleared = typeof raw.representative_cleared === "boolean" ? raw.representative_cleared : null;
  switch (type) {
    case "POKEDEX_POSITION_ASSIGNED": {
      const to = pos(raw.to), c = card(raw.card);
      return to && c && basis ? { to, card: c, basis } : null;
    }
    case "POKEDEX_POSITION_MOVED": {
      const from = pos(raw.from), to = pos(raw.to), c = card(raw.card);
      return from && to && c && basis && cleared !== null ? { from, to, card: c, basis, representative_cleared: cleared } : null;
    }
    case "POKEDEX_POSITION_REMOVED": {
      const from = pos(raw.from), c = card(raw.card);
      return from && c && cleared !== null ? { from, card: c, representative_cleared: cleared } : null;
    }
    case "POKEDEX_REPRESENTATIVE_SET": {
      const p = pos(raw.position), c = card(raw.card);
      return p && c ? { position: p, card: c } : null;
    }
    case "POKEDEX_REPRESENTATIVE_REPLACED": {
      const p = pos(raw.position), c = card(raw.card), prev = card(raw.previous_card);
      return p && c && prev ? { position: p, card: c, previous_card: prev } : null;
    }
    case "POKEDEX_REPRESENTATIVE_RESTORED": {
      const p = pos(raw.position), prev = card(raw.previous_card);
      return p && prev ? { position: p, previous_card: prev } : null;
    }
    case "POKEDEX_POSITIONS_CHANGED": {
      const a = nat(raw.assigned), r = nat(raw.removed), s = nat(raw.representatives_set), c = nat(raw.representatives_cleared);
      return a !== null && r !== null && s !== null && c !== null ? { assigned: a, removed: r, representatives_set: s, representatives_cleared: c } : null;
    }
  }
}

/**
 * Uma linha da 5395 → evento da lista de atividades. Fora do contrato → null (a página
 * inteira é recusada pelo chamador: nunca exibe dados parciais).
 */
export function parseCollectionActivityEvent(value: unknown): ActivityEvent | null {
  const r = obj(value);
  if (!r) return null;
  const keys = Object.keys(r).sort();
  if (keys.length !== COLUMNS.length || keys.some((k, i) => k !== COLUMNS[i])) return null;
  const id = r.event_id;
  if (typeof id !== "number" || !Number.isSafeInteger(id) || id < 1) return null;
  if (typeof r.occurred_at !== "string" || Number.isNaN(Date.parse(r.occurred_at))) return null;
  const type = r.event_type;
  if (typeof type !== "string" || !isPokedexActivityType(type)) return null;
  const derived = type === "POKEDEX_POSITIONS_CHANGED";
  if (r.origin !== (derived ? "DERIVED" : "EXPLICIT")) return null;
  const role = r.actor_role;
  if (role !== "OWNER" && role !== "EDITOR" && role !== "SYSTEM") return null;
  if (role === "SYSTEM" && (!derived || r.actor_display_name !== null)) return null;
  if (r.actor_display_name !== null && typeof r.actor_display_name !== "string") return null;
  const raw = obj(r.summary);
  const summary = raw ? cleanSummary(type, raw) : null;
  if (!summary) return null;
  return {
    id,
    occurredAt: r.occurred_at,
    type,
    category: null,
    source: "POKEDEX",
    legacy: false,
    collectionName: null,
    binderName: null,
    summary,
    itemCount: 0,
    items: [],
    truncated: false,
    attribution: { role: role === "OWNER" ? "OWNER" : role === "EDITOR" ? "PARTICIPANT" : null, displayName: role === "SYSTEM" ? null : txt(r.actor_display_name) },
    pokedexActor: role,
  };
}

export function parseCollectionActivityPage(data: unknown): ActivityEvent[] | null {
  if (!Array.isArray(data) || data.length > 100) return null;
  const out: ActivityEvent[] = [];
  let prev: ActivityEvent | null = null;
  for (const row of data) {
    const e = parseCollectionActivityEvent(row);
    if (!e) return null;
    // Ordem do servidor: (occurred_at, id) estritamente decrescente.
    if (prev) {
      const a = Date.parse(e.occurredAt), b = Date.parse(prev.occurredAt);
      if (!(a < b || (a === b && e.id < prev.id))) return null;
    }
    out.push(e);
    prev = e;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Apresentação (frases do colecionador, sem enums nem ids)

const dexOf = (p: unknown) => {
  const o = obj(p);
  return o ? `#${String(o.number).padStart(4, "0")} ${String(o.species)}` : "uma posição";
};
const cardOf = (c: unknown) => txt(obj(c)?.name) ?? "Carta";

export function fullPokedexCard(c: unknown): string {
  const o = obj(c);
  if (!o) return "Carta";
  return [txt(o.name), txt(o.number), txt(o.set)?.toUpperCase(), txt(o.variant)].filter(Boolean).join(" · ");
}

function n(value: number, one: string, many: string): string {
  return `${value.toLocaleString("pt-BR")} ${value === 1 ? one : many}`;
}

export type PokedexView = { title: string; headline: string; context: string | null; icon: ActivityIcon };

export function describePokedexEvent(e: ActivityEvent): PokedexView {
  const s = e.summary;
  switch (e.type as PokedexActivityType) {
    case "POKEDEX_POSITION_ASSIGNED":
      return { icon: "card", title: `${cardOf(s.card)} colocada em ${dexOf(s.to)}`, headline: `${cardOf(s.card)} colocada`, context: s.basis === "USER_OVERRIDE" ? "Exceção: o catálogo registra outro Pokémon" : null };
    case "POKEDEX_POSITION_MOVED":
      return {
        icon: "move",
        title: `${cardOf(s.card)} movida de ${dexOf(s.from)} para ${dexOf(s.to)}`,
        headline: `${cardOf(s.card)} movida`,
        context: [s.representative_cleared ? "Deixou de representar a posição anterior" : null, s.basis === "USER_OVERRIDE" ? "Exceção: o catálogo registra outro Pokémon" : null].filter(Boolean).join(" · ") || null,
      };
    case "POKEDEX_POSITION_REMOVED":
      return { icon: "remove", title: `${cardOf(s.card)} retirada de ${dexOf(s.from)}`, headline: `${cardOf(s.card)} retirada`, context: s.representative_cleared ? "A posição voltou à representante automática" : null };
    case "POKEDEX_REPRESENTATIVE_SET":
      return { icon: "link", title: `${cardOf(s.card)} escolhida para representar ${dexOf(s.position)}`, headline: "Representante escolhida", context: null };
    case "POKEDEX_REPRESENTATIVE_REPLACED":
      return { icon: "transfer", title: `${cardOf(s.card)} passou a representar ${dexOf(s.position)}`, headline: "Representante trocada", context: `Antes: ${cardOf(s.previous_card)}` };
    case "POKEDEX_REPRESENTATIVE_RESTORED":
      return { icon: "unlink", title: `${dexOf(s.position)} voltou à representante automática`, headline: "Representante automática", context: `Antes: ${cardOf(s.previous_card)}` };
    case "POKEDEX_POSITIONS_CHANGED": {
      const parts = [
        nat(s.assigned) ? n(s.assigned as number, "carta colocada", "cartas colocadas") : null,
        nat(s.removed) ? n(s.removed as number, "carta retirada", "cartas retiradas") : null,
        nat(s.representatives_set) ? n(s.representatives_set as number, "representante definida", "representantes definidas") : null,
        nat(s.representatives_cleared) ? n(s.representatives_cleared as number, "representante desfeita", "representantes desfeitas") : null,
      ].filter(Boolean);
      return { icon: "activity", title: "Posições da Pokédex atualizadas pelo acervo", headline: "Pokédex atualizada pelo acervo", context: parts.join(" · ") || null };
    }
    default:
      return { icon: "activity", title: "Atividade na Pokédex", headline: "Atividade na Pokédex", context: null };
  }
}

/** Papel do autor como o colecionador entende (C-241). SYSTEM: efeito de alocar/desalocar, sem autor. */
export function pokedexActorLabel(role: PokedexActorRole | undefined): string {
  return role === "OWNER" ? "Titular" : role === "EDITOR" ? "Pode organizar" : "Registro automático";
}

/** Campos de "Ver detalhes" (sem "Quando", acrescentado pelo chamador). */
export function pokedexDetailFields(e: ActivityEvent): { label: string; value: string }[] {
  const v = describePokedexEvent(e);
  const s = e.summary;
  const f: { label: string; value: string }[] = [{ label: "Ação", value: v.title }];
  if (s.card) f.push({ label: "Carta", value: fullPokedexCard(s.card) });
  if (s.previous_card) f.push({ label: "Antes", value: fullPokedexCard(s.previous_card) });
  if (s.from) f.push({ label: "De", value: dexOf(s.from) });
  if (s.to) f.push({ label: "Para", value: dexOf(s.to) });
  if (s.position) f.push({ label: "Posição", value: dexOf(s.position) });
  if (e.type === "POKEDEX_POSITIONS_CHANGED" && v.context) f.push({ label: "Mudanças", value: v.context });
  else if (v.context && !v.context.startsWith("Antes:")) f.push({ label: "Observação", value: v.context });
  const role = e.pokedexActor;
  if (role === "SYSTEM") f.push({ label: "Por", value: "Registro automático (cartas alocadas ou retiradas da coleção)" });
  else {
    f.push({ label: "Por", value: e.attribution?.displayName ?? pokedexActorLabel(role) });
    f.push({ label: "Papel", value: pokedexActorLabel(role) });
  }
  return f;
}

export type CollectionActivityFailure = "unavailable" | "not_authenticated" | "invalid" | "unknown";

/** Só código e nome da exceção. Barreira fechada e função ausente: "ainda não disponível". */
export function classifyCollectionActivityFailure(code?: string | null, message?: string | null): CollectionActivityFailure {
  const text = (message ?? "").trim();
  if (text === "CAPABILITY_NOT_ENABLED" || code === "PGRST202" || code === "42883") return "unavailable";
  if (code === "28000" || text === "not_authenticated") return "not_authenticated";
  if (text === "INVALID_PAGE" || code === "22023") return "invalid";
  return "unknown";
}

export function collectionActivityFailureMessage(reason: CollectionActivityFailure): string {
  switch (reason) {
    case "unavailable":
      return "O histórico da Pokédex ainda não está disponível.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre de novo para ver o histórico.";
    case "invalid":
      return "Não foi possível carregar o histórico da Pokédex.";
    default:
      // Comunicação ou resposta inválida: não prova que não há atividades.
      return "Não foi possível carregar o histórico da Pokédex agora. Tente de novo em instantes.";
  }
}

/** Zero linhas não prova que nada aconteceu (também pode ser falta de acesso): texto neutro. */
export function collectionActivityEmptyMessage(): string {
  return "Nenhuma atividade da Pokédex aparece aqui por enquanto.";
}

export const COLLECTION_ACTIVITY_NOTE = "Aparecem só as mudanças de posições e representantes registradas pelo histórico da Pokédex.";
