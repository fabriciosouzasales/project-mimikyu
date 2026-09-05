// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/sanitize.ts
// Mesma disciplina de sanitização já usada nos conectores JustTCG (P8) e PTAX (P9)
// — Seção 15 do contrato: "Nunca logar service key, headers sensíveis ou payload
// secreto". A PokéAPI em si é pública e sem credencial; esta defesa protege a
// Service Role Key do Supabase (usada pelo próprio caller para chamar as RPCs de
// sourcing) de aparecer em qualquer mensagem de erro propagada por qualquer camada
// deste módulo (ex.: erro do PostgREST/RPC, timeout, corpo de resposta HTTP).

const MAX_ERROR_BODY_CHARS = 500;

export function sanitize(text: string | null | undefined): string | null {
  if (!text) return text ?? null;
  let t = text;
  t = t.replace(
    /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g,
    "[REDACTED_JWT]",
  ); // service_role/anon key (JWT)
  // Consome até o fim da linha (nunca só a primeira palavra após ":") —
  // "Authorization: Bearer abc123" tem DOIS tokens de segredo em sequência;
  // um regex que para no primeiro \S+ deixaria "abc123" exposto.
  t = t.replace(/x-api-key\s*:\s*.+/gi, "x-api-key: [REDACTED]");
  t = t.replace(/authorization\s*:\s*.+/gi, "authorization: [REDACTED]");
  t = t.replace(/bearer\s+\S+/gi, "Bearer [REDACTED]");
  t = t.replace(/apikey\s*:\s*.+/gi, "apikey: [REDACTED]");
  t = t.replace(/service[_-]?role[A-Za-z0-9._-]*/gi, "[REDACTED_SERVICE_ROLE]");
  return t;
}

export function truncateForDiagnostics(text: string): string {
  if (text.length <= MAX_ERROR_BODY_CHARS) return text;
  return `${
    text.slice(0, MAX_ERROR_BODY_CHARS)
  }... [truncado — ${text.length} caracteres no total]`;
}
