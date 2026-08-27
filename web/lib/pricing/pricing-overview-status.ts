import type { PricingAdminOverview } from "./queries";
import type { PricingSyncRunDailyPoint } from "./queries";

/**
 * Status executivo (Saudável/Atenção/Crítico) da Visão Geral v2 de Valores
 * de Mercado — pedido por Fabrício em 2026-08-23 ("dashboard gerencial de
 * verdade"). Regra explícita dada por ele DURANTE a implementação, corrigindo
 * uma leitura inicial equivocada: a mera existência de PENDING/NOT_FOUND em
 * `pricing_card_mapping` NÃO deve, por si só, tornar o módulo "não
 * saudável" — são backlog administrável, mostrado em "Atenções e Ações",
 * não um sinal de saúde operacional. O status prioriza sinais de que a
 * MÁQUINA (Atualização Automática/Sets/sincronizações) está funcionando:
 *
 *   1. Atualização Automática (dispatcher) ativa
 *   2. Sets com problema/pausados
 *   3. Falhas recentes de sincronização
 *   4. Atraso de sincronização (next_due_at já vencido)
 *   5. Cobertura de preços vs. limiar mínimo (não o backlog em si — a
 *      COBERTURA RESULTANTE, que é um sinal de saúde diferente de "quantos
 *      itens estão na fila de revisão")
 *
 * Limiares (`COVERAGE_ATTENTION_THRESHOLD_PCT`/`OVERDUE_GRACE_MS`) são
 * arbitrários e ajustáveis — não vieram de um pedido numérico específico de
 * Fabrício, documentados aqui para poderem ser revistos.
 */

const COVERAGE_ATTENTION_THRESHOLD_PCT = 95;
/** Margem de tolerância antes de tratar `next_due_at` vencido como sinal de atraso — evita falso positivo por atraso de poucos minutos entre execuções do dispatcher (que roda a cada 5 minutos, ver ADR-032). */
const OVERDUE_GRACE_MS = 60 * 60 * 1000;

export type PricingOverviewStatusLevel = "SAUDAVEL" | "ATENCAO" | "CRITICO";

export type PricingOverviewStatus = {
  level: PricingOverviewStatusLevel;
  label: string;
  badgeVariant: "success" | "warning" | "destructive";
  reasons: string[];
};

export function computePricingOverviewStatus(
  overview: PricingAdminOverview,
  syncRunDaily: PricingSyncRunDailyPoint[] | null,
): PricingOverviewStatus {
  const criticalReasons: string[] = [];
  const attentionReasons: string[] = [];

  const dispatcherAtivo = overview.dispatcher?.active ?? false;
  if (!dispatcherAtivo) {
    criticalReasons.push("Atualização Automática está inativa.");
  }

  if (overview.sets.problem > 0) {
    criticalReasons.push(
      `${overview.sets.problem} ${overview.sets.problem === 1 ? "Set com problema" : "Sets com problema"} de sincronização.`,
    );
  }

  // P16.4.1 (migration 3952) — Set recém-confirmado que ainda não passou pela primeira janela
  // do dispatcher (`last_outcome = 'NEVER_RUN'`) é onboarding normal, nunca falha operacional.
  // Antes desta correção, esse estado era contado dentro de `sets.problem` e tornava a Visão
  // Geral CRÍTICA por engano — aqui vira apenas um sinal de Atenção, nunca Crítico.
  if (overview.sets.onboarding_pending > 0) {
    attentionReasons.push(
      `${overview.sets.onboarding_pending} ${overview.sets.onboarding_pending === 1 ? "Set aguardando" : "Sets aguardando"} primeira sincronização.`,
    );
  }

  const ultimoDiaComExecucoes = syncRunDaily?.length ? syncRunDaily[syncRunDaily.length - 1]?.day : null;
  const falhasRecentes =
    syncRunDaily?.filter((ponto) => ponto.day === ultimoDiaComExecucoes && ponto.status === "FAILED") ?? [];
  const totalFalhasRecentes = falhasRecentes.reduce((soma, ponto) => soma + ponto.count, 0);
  if (totalFalhasRecentes > 0) {
    criticalReasons.push(
      `${totalFalhasRecentes} ${totalFalhasRecentes === 1 ? "falha" : "falhas"} de sincronização no último dia com execuções.`,
    );
  }

  if (overview.sets.paused > 0) {
    attentionReasons.push(
      `${overview.sets.paused} ${overview.sets.paused === 1 ? "Set pausado" : "Sets pausados"}.`,
    );
  }

  // Texto revisado (2026-08-23, coerência com o tile "Atualização
  // pendente"/"Atualização atrasada" de `pricing-overview-stats.tsx`): um
  // `next_due_at` levemente no passado é backlog NORMAL com o dispatcher
  // ativo (processado no próximo ciclo de 5 minutos, ADR-032) — por isso só
  // este bloco, com a margem de 1h de `OVERDUE_GRACE_MS`, vira sinal de
  // Atenção. "Fila de atualização" deixa claro que é o mesmo atraso do
  // tile, só que persistente além do esperado — não confundir com o rótulo
  // benigno "Atualização pendente", que aparece mesmo sem esse atraso maior.
  if (overview.sets.next_due_at) {
    const atraso = Date.now() - new Date(overview.sets.next_due_at).getTime();
    if (atraso > OVERDUE_GRACE_MS) {
      attentionReasons.push("Fila de atualização atrasada há mais de 1 hora.");
    }
  }

  // P16.1 (2026-08-24): texto revisado de "Cobertura de preços em X%" para
  // "Confirmação de mapeamentos de carta em X%" — `mappings.coverage_pct` mede confirmação de
  // `pricing_card_mapping`, conceito distinto da nova Cobertura de Sets (`overview.coverage`,
  // migration 3950) exibida no Hero. Mesmo limiar/regra de negócio, só o rótulo mudou, para não
  // colidir semanticamente com a palavra "Cobertura" usada em outro sentido na mesma tela.
  if (overview.mappings.coverage_pct !== null && overview.mappings.coverage_pct < COVERAGE_ATTENTION_THRESHOLD_PCT) {
    attentionReasons.push(`Confirmação de mapeamentos de carta em ${overview.mappings.coverage_pct}%, abaixo do esperado.`);
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
    // P16.1 microcorreção de copy (2026-08-25): "sem Sets com problema" podia soar contraditório
    // com o tile "Sets aguardando configuração" (SWSH8) — Set sem mapeamento ainda não é falha
    // operacional, é pendência cadastral (ver Atenções e Ações). Nenhuma lógica de status mudou,
    // só o texto: Hero = saúde operacional, Cobertura = alcance do Pricing.
    reasons: ["Atualização Automática ativa, sincronizações em dia e sem problemas operacionais nos Sets configurados."],
  };
}
