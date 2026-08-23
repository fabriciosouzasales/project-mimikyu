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

  if (overview.sets.next_due_at) {
    const atraso = Date.now() - new Date(overview.sets.next_due_at).getTime();
    if (atraso > OVERDUE_GRACE_MS) {
      attentionReasons.push("Próxima execução prevista já está atrasada.");
    }
  }

  if (overview.mappings.coverage_pct !== null && overview.mappings.coverage_pct < COVERAGE_ATTENTION_THRESHOLD_PCT) {
    attentionReasons.push(`Cobertura de preços em ${overview.mappings.coverage_pct}%, abaixo do esperado.`);
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
    reasons: ["Atualização Automática ativa, sincronizações em dia e sem Sets com problema."],
  };
}
