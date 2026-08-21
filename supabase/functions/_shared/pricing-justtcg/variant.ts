// Project Mimikyu — supabase/functions/_shared/pricing-justtcg/variant.ts
// Parsing puro do campo `printing` de uma JustTcgVariant — extraído de
// scripts/sync-justtcg-pricing.ts para o Incremento de Atualização Diária JustTCG
// (2026-08-21), item A.
//
// v1 documenta sufixo " - <Idioma>" em `printing` (removido só na v2). Sem sufixo ->
// idiomaCodigo null, nunca presumir inglês nem qualquer outro idioma. Usado tanto pelo
// CLI (persistBatchedResults, ao montar pricing_product.source_printing_label) quanto
// pelo núcleo de refresh (_shared/pricing-justtcg-refresh/extract.ts, mesmo campo).
export function splitPrintingLanguage(
  printingRaw: string | null | undefined,
): { printingTipo: string | null; idiomaCodigo: string | null } {
  if (!printingRaw || !printingRaw.trim()) {
    return { printingTipo: null, idiomaCodigo: null };
  }
  const match = printingRaw.match(/^(.+?)\s*-\s*([A-Za-z]+)$/);
  if (match) {
    return {
      printingTipo: match[1].trim(),
      idiomaCodigo: match[2].trim().toLowerCase(),
    };
  }
  return { printingTipo: printingRaw.trim(), idiomaCodigo: null };
}
