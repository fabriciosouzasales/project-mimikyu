/**
 * V1-13 — identidade opaca de exemplar para o EDITOR (5391; reutilizada no fichário pela 5397).
 * Token = 'pc1.' + HMAC-SHA256(alocação|participação|época), 64 hex minúsculos: muda com a
 * participação ou a época do papel e só é aceito pelo servidor na época vigente. Módulo neutro,
 * compartilhado pela Pokédex colaborativa (editor-pokedex.ts) e pelo fichário do EDITOR (editor-binder.ts).
 */

const TOKEN_RE = /^pc1\.[0-9a-f]{64}$/;

/** Chaves que nunca podem entrar nem sair das integrações do EDITOR (identidade física ou pessoal). */
const FORBIDDEN_KEY_RE = /physical|allocation|owner_user|user_id|membership|storage|location|condition|price/i;

export type CopyToken = string & { readonly __brand: "PokedexCopyToken" };

export function isCopyToken(value: unknown): value is CopyToken {
  return typeof value === "string" && TOKEN_RE.test(value);
}

/** Algum objeto (request ou linha) carrega chave de identidade física/pessoal? Recursivo. */
export function hasForbiddenKey(value: unknown, depth = 0): boolean {
  if (depth > 6 || value === null || typeof value !== "object") return false;
  if (Array.isArray(value)) return value.some((v) => hasForbiddenKey(v, depth + 1));
  return Object.entries(value as Record<string, unknown>).some(([k, v]) => FORBIDDEN_KEY_RE.test(k) || hasForbiddenKey(v, depth + 1));
}
