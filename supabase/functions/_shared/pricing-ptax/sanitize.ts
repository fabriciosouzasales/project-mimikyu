// Project Mimikyu — supabase/functions/_shared/pricing-ptax/sanitize.ts
// Mesma disciplina de sanitização já usada nos conectores JustTCG (P8) e PTAX (P9) —
// defesa em profundidade mesmo a API do BCB sendo pública e sem credencial (protege
// contra um eventual cabeçalho de autenticação de um proxy/gateway intermediário, e
// contra a Service Role Key do Supabase aparecer em qualquer mensagem de erro
// propagada até aqui pelo adapter).

const MAX_ERROR_BODY_CHARS = 500;

export function sanitize(text: string | null | undefined): string | null {
  if (!text) return text ?? null;
  let t = text;
  t = t.replace(/tcg_[A-Za-z0-9]+/g, "[REDACTED_KEY]");
  t = t.replace(
    /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g,
    "[REDACTED_JWT]",
  ); // service_role/anon key (JWT)
  t = t.replace(/x-api-key\s*:\s*\S+/gi, "x-api-key: [REDACTED]");
  t = t.replace(/authorization\s*:\s*\S+/gi, "authorization: [REDACTED]");
  t = t.replace(/bearer\s+\S+/gi, "Bearer [REDACTED]");
  t = t.replace(/apikey\s*:\s*\S+/gi, "apikey: [REDACTED]");
  return t;
}

export function truncateForDiagnostics(text: string): string {
  if (text.length <= MAX_ERROR_BODY_CHARS) return text;
  return `${
    text.slice(0, MAX_ERROR_BODY_CHARS)
  }... [truncado — ${text.length} caracteres no total]`;
}
