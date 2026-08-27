// Project Mimikyu — supabase/functions/justtcg-set-bootstrap/auth.ts
// Validação do segredo dedicado da Edge Function justtcg-set-bootstrap — dispatcher de
// bootstrap de Set (CARD_SYNC, P16.5.4, 2026-08-26).
//
// Cópia literal de supabase/functions/justtcg-price-refresh-set/auth.ts (mesmo modelo de
// identidade — verify_jwt=false, autorização via segredo dedicado no header "apikey",
// comparação em tempo constante). Decisão desta rodada: REAPROVEITA o mesmo Function
// Secret JUSTTCG_PRICE_REFRESH_SECRET já provisionado para justtcg-price-refresh/
// justtcg-price-refresh-set — as três funções servem o mesmo propósito operacional
// (integração com a JustTCG), só mudando a granularidade/fase (wave -> Set -> bootstrap
// inicial de Set), e um segredo dedicado novo não traz benefício de segurança adicional
// (mesmo chamador confiável — o operador/agendador, ainda não criado nesta rodada). Se um
// dia coexistirem em produção simultaneamente, nada impede migrar para um segredo próprio
// depois.
//
// 100% livre de Deno.env — a origem do segredo esperado é responsabilidade exclusiva do
// chamador (index.ts), nunca deste módulo.

export function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const bytesA = encoder.encode(a);
  const bytesB = encoder.encode(b);
  const maxLen = Math.max(bytesA.length, bytesB.length);

  let diff = bytesA.length ^ bytesB.length;
  for (let i = 0; i < maxLen; i++) {
    const byteA = i < bytesA.length ? bytesA[i] : 0;
    const byteB = i < bytesB.length ? bytesB[i] : 0;
    diff |= byteA ^ byteB;
  }
  return diff === 0;
}

export function extractProvidedSecret(req: Request): string | null {
  return req.headers.get("apikey");
}

export function isAuthorized(
  providedSecret: string | null,
  expectedSecret: string | null,
): boolean {
  if (!expectedSecret) return false;
  if (!providedSecret) return false;
  return timingSafeEqual(providedSecret, expectedSecret);
}
