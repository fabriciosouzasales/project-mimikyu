// Project Mimikyu — supabase/functions/justtcg-price-refresh/auth.ts
// Validação do segredo dedicado da Edge Function justtcg-price-refresh — Incremento de
// Atualização Diária JustTCG (2026-08-21), item C.
//
// Cópia quase literal de supabase/functions/ptax-fx-refresh/auth.ts (mesmo modelo de
// identidade, ADR-031): verify_jwt=false (chaves sb_secret_.../sb_publishable_... não são
// JWT) — a autorização é um segredo dedicado desta função (JUSTTCG_PRICE_REFRESH_SECRET,
// nunca a publishable key), enviado no header "apikey" (nunca "Authorization: Bearer") e
// validado aqui por comparação manual em tempo constante. Mesma razão para não usar
// @supabase/server (auth: 'secret:<nome>'): pacote em Public Beta sem versão corrigida
// confirmada.
//
// 100% livre de Deno.env — a origem do segredo esperado é responsabilidade exclusiva do
// chamador (index.ts), nunca deste módulo. timingSafeEqual/isAuthorized permanecem puros e
// testáveis offline sem nenhum runtime Deno.

// Comparação byte a byte em tempo constante — SEM early return em nenhum ponto do laço.
// Sempre itera até o maior comprimento entre os dois valores, e o próprio comprimento (via
// XOR de a.length ^ b.length antes do laço) entra na acumulação de diferença, para que uma
// string do tamanho errado nunca termine mais rápido que uma do tamanho certo. Os únicos
// early returns do módulo estão em isAuthorized(), e são sobre AUSÊNCIA de dado (nunca
// sobre o conteúdo do segredo em si) — não vazam informação sobre o segredo esperado.
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

// Extrai o segredo apresentado pelo chamador — sempre o header "apikey", nunca
// "Authorization" (reservado a um eventual JWT real, que esta função não usa).
export function extractProvidedSecret(req: Request): string | null {
  return req.headers.get("apikey");
}

// Decide autorização. expectedSecret ausente (função mal configurada, sem
// JUSTTCG_PRICE_REFRESH_SECRET no ambiente) ou providedSecret ausente NUNCA autorizam —
// estes dois `if` são guardas sobre a AUSÊNCIA do dado, não uma comparação de conteúdo,
// então não reintroduzem um vazamento de timing sobre o valor do segredo esperado.
export function isAuthorized(
  providedSecret: string | null,
  expectedSecret: string | null,
): boolean {
  if (!expectedSecret) return false;
  if (!providedSecret) return false;
  return timingSafeEqual(providedSecret, expectedSecret);
}
