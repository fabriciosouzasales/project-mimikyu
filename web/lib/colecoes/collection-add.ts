/**
 * Cadastrar cartas novas a partir da coleção (V1-06 — Fluxos 1.6, 2 e 5).
 * Regras puras de apresentação; sem banco, sem React (testável com `node --test`).
 */

/** `?cadastrar=cartas|set` — abre o cadastro ao chegar (continuidade após criar a coleção, Fluxo 1.6). */
export const REGISTER_PARAM = "cadastrar";

export type RegisterMode = "cards" | "set";

type Params = Record<string, string | string[] | undefined>;

export function wantsRegister(params: Params): RegisterMode | null {
  const raw = params[REGISTER_PARAM];
  const value = Array.isArray(raw) ? raw[0] : raw;
  if (value === "cartas") return "cards";
  if (value === "set") return "set";
  return null;
}

export function registerHref(collectionHref: string, mode: RegisterMode): string {
  const sep = collectionHref.includes("?") ? "&" : "?";
  return `${collectionHref}${sep}${REGISTER_PARAM}=${mode === "set" ? "set" : "cartas"}`;
}

/**
 * Set inteiro só existe em coleção de Set (inclui Master Set): NS Fluxo 5.1.
 * Livre e Pokédex recebem só "escolher cartas"; um pedido de `set` nelas vira cartas.
 */
export function effectiveRegisterMode(mode: RegisterMode, hasReferenceSet: boolean): RegisterMode {
  return mode === "set" && !hasReferenceSet ? "cards" : mode;
}
