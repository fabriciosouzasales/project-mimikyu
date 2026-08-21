// Project Mimikyu — supabase/functions/_shared/pricing-justtcg/sanitize.ts
// Sanitização de texto/JSON antes de log ou persistência — extraída de
// scripts/sync-justtcg-pricing.ts (mesma disciplina já validada na prova técnica
// original, Protect-SensitiveText) para o Incremento de Atualização Diária JustTCG
// (2026-08-21), item A.
//
// Nunca deixa a JUSTTCG_API_KEY (prefixo "tcg_"), nem um header apikey/Authorization/
// Bearer, escapar para pricing_sync_run.error_summary, pricing_sync_run_call.error_detail
// ou qualquer resposta HTTP — mesmo padrão de sanitize.ts em _shared/pricing-ptax.

export function sanitize(text: string | null | undefined): string | null {
  if (!text) return text ?? null;
  let t = text;
  t = t.replace(/tcg_[A-Za-z0-9]+/g, "[REDACTED_KEY]");
  t = t.replace(/x-api-key\s*:\s*\S+/gi, "x-api-key: [REDACTED]");
  t = t.replace(/authorization\s*:\s*\S+/gi, "authorization: [REDACTED]");
  t = t.replace(/bearer\s+\S+/gi, "Bearer [REDACTED]");
  return t;
}

export function sanitizeJson(value: unknown): unknown {
  if (typeof value === "string") return sanitize(value);
  if (Array.isArray(value)) return value.map(sanitizeJson);
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = sanitizeJson(v);
    }
    return out;
  }
  return value;
}
