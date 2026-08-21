// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/observation-decision.ts
// Decisão pura de escrita de pricing_observation — Incremento de Atualização Diária
// JustTCG (2026-08-21), item B, regra 14: "Observação nova somente quando o preço
// realmente mudar."
//
// Mesma semântica já validada em persistBatchedResults() (Fase 3) do CLI — reproduzida
// aqui como função pura e isolada (o CLI nunca a extraiu como função própria, está
// embutida no laço de persistência em lote). Compara SEMPRE contra a última observação
// conhecida do grupo (produto+condição), nunca contra uma janela de tempo — preço
// idêntico ao último conhecido nunca gera uma linha nova, independente de quando a
// checagem ocorreu (evita ruído de "mesma cotação, dia novo").

export type ObservationDecision =
  | { kind: "FIRST_OBSERVATION" } // grupo nunca observado antes -> grava
  | { kind: "SAME_PRICE_SKIP" } // preço idêntico ao último conhecido -> reaproveita, zero escrita
  | { kind: "PRICE_CHANGED_WRITE" } // preço mudou de fato -> grava nova observação real
  | {
    kind: "DIVERGENT_SAME_TIMESTAMP_PRESERVED";
    existingPrice: number;
  }; // mesmo observed_at exato já tem outro preço gravado — nunca sobrescreve, só sinaliza

export function decideObservationWrite(
  latest: { price: number; observedAt: string } | null,
  candidate: { price: number; observedAt: string },
): ObservationDecision {
  if (latest === null) return { kind: "FIRST_OBSERVATION" };
  if (latest.price === candidate.price) return { kind: "SAME_PRICE_SKIP" };
  if (latest.observedAt === candidate.observedAt) {
    return {
      kind: "DIVERGENT_SAME_TIMESTAMP_PRESERVED",
      existingPrice: latest.price,
    };
  }
  return { kind: "PRICE_CHANGED_WRITE" };
}
