import type { PricingSourceHealth } from "./queries";

/**
 * Status executivo (Saudável/Atenção/Crítico) da Saúde das Fontes — mesma
 * semântica de 3 níveis já usada em `pricing-overview-status.ts` para o Hero
 * da Visão Geral (2026-08-23, "tratamento Hero completo" pedido por
 * Fabrício ao retomar o refinamento visual pós-P0 de performance). Só
 * agrega sinais que já existem por fonte em `admin_get_pricing_source_health()`
 * (migration 3941) — nenhuma regra de negócio nova, nenhuma RPC nova.
 *
 * Fontes inativas (`isActive=false`) nunca contribuem para CRÍTICO/ATENÇÃO —
 * mesmo racional de `deriveSourceTone()` em `saude-fontes-list.tsx` (tom
 * `muted`, não `danger`): uma fonte desligada de propósito não é um defeito
 * a reportar aqui. Zero fonte ativa cadastrada também não é tratado como
 * crítico (nada para monitorar ainda é diferente de algo quebrado) — vira
 * SAUDÁVEL com motivo explícito, mesma cautela usada quando `sources.length
 * === 0` no `SaudeFontesList` (estado vazio, não erro).
 */

export type PricingSourceHealthStatusLevel = "SAUDAVEL" | "ATENCAO" | "CRITICO";

export type PricingSourceHealthStatus = {
  level: PricingSourceHealthStatusLevel;
  label: string;
  badgeVariant: "success" | "warning" | "destructive";
  reasons: string[];
};

export function computePricingSourceHealthStatus(sources: PricingSourceHealth[]): PricingSourceHealthStatus {
  const ativas = sources.filter((source) => source.isActive);

  const criticalReasons: string[] = [];
  const attentionReasons: string[] = [];

  const setsComProblema = ativas.reduce((soma, source) => soma + source.sets.problem, 0);
  if (setsComProblema > 0) {
    criticalReasons.push(`${setsComProblema} ${setsComProblema === 1 ? "Set com problema" : "Sets com problema"} de sincronização.`);
  }

  // Texto v1.1 (2026-08-23, feedback de Fabrício): a fórmula anterior ("N
  // execuções falharam") pesava mais do que a situação real justificava —
  // 45/45 Sets saudáveis e 98,7% de cobertura ao lado de uma frase que soava
  // como problema sistêmico. "sem impacto na saúde dos Sets" é seguro aqui
  // porque este bloco só é alcançado quando `criticalReasons` está vazio,
  // ou seja, `setsComProblema === 0` — nunca aparece junto de um cenário
  // onde Sets estejam de fato com problema (nesse caso o nível já teria
  // virado CRÍTICO acima e este texto nem seria montado).
  const execucoesFalhas = ativas.reduce((soma, source) => soma + source.recentFailedRuns, 0);
  if (execucoesFalhas > 0) {
    attentionReasons.push(
      `Foram registradas ${execucoesFalhas} ${execucoesFalhas === 1 ? "falha de execução" : "falhas de execução"} nos últimos 7 dias, sem impacto na saúde dos Sets.`,
    );
  }

  const setsPausados = ativas.reduce((soma, source) => soma + source.sets.paused, 0);
  if (setsPausados > 0) {
    attentionReasons.push(`${setsPausados} ${setsPausados === 1 ? "Set pausado" : "Sets pausados"}.`);
  }

  // P16.4.1 (migration 3952) — mesmo racional de `pricing-overview-status.ts`: Set confirmado
  // que ainda não teve sua primeira janela do dispatcher é onboarding, nunca falha. Nunca deve
  // elevar a fonte a CRÍTICO/"COM PROBLEMA" — apenas um sinal de Atenção à parte.
  const setsAguardandoOnboarding = ativas.reduce((soma, source) => soma + source.sets.onboardingPending, 0);
  if (setsAguardandoOnboarding > 0) {
    attentionReasons.push(
      `${setsAguardandoOnboarding} ${setsAguardandoOnboarding === 1 ? "Set aguardando" : "Sets aguardando"} primeira sincronização.`,
    );
  }

  if (ativas.length === 0 && sources.length > 0) {
    attentionReasons.push("Nenhuma fonte de preço está ativa no momento.");
  }

  if (criticalReasons.length > 0) {
    return { level: "CRITICO", label: "Crítico", badgeVariant: "destructive", reasons: criticalReasons };
  }

  if (attentionReasons.length > 0) {
    return { level: "ATENCAO", label: "Atenção", badgeVariant: "warning", reasons: attentionReasons };
  }

  return {
    level: "SAUDAVEL",
    label: "Saudável",
    badgeVariant: "success",
    reasons: ["Todas as fontes ativas sem Sets com problema ou falhas recentes."],
  };
}
