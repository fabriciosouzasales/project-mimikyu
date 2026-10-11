import { Gauge } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import type { PricingAdminOverview } from "@/lib/pricing/queries";
import { cn, formatNumber } from "@/lib/utils";

/**
 * Orçamento da API — PRICING-MODULE-RECOVERY-01 Fase 5 (migration 3984, 2026-10-10).
 *
 * Responde "vamos caber no plano este mês?" sem obrigar ninguém a somar o gráfico diário. Faixa
 * única de largura total, abaixo da linha de 3 gráficos (que permanece intocada): consumido no mês,
 * projeção até o fim do mês e consumo de hoje × limite diário, mais UMA barra contra o limite mensal
 * (consumido sólido + projeção restante em tom claro). Tudo vem pronto do servidor
 * (`get_pricing_admin_overview().api_budget`) — este componente só apresenta, não calcula regra.
 *
 * Cor semântica só quando significa algo: projeção acima do limite → warning (barra e número);
 * dentro do limite → acento neutro da marca (`primary`, mesmo tom do progresso de Cobertura no Hero).
 * Server Component: nenhum estado/interação.
 */

const fimDoMesFormatter = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", timeZone: "UTC" });

export function PricingApiBudget({ budget }: { budget: NonNullable<PricingAdminOverview["api_budget"]> }) {
  const limite = budget.monthly_limit;
  const excede = limite !== null && budget.projected_month > limite;
  const perto = limite !== null && !excede && budget.projected_month > limite * 0.9;

  // Barra: escala = max(limite, projeção) para a projeção excedente continuar visível.
  const escala = Math.max(limite ?? 0, budget.projected_month, 1);
  const consumidoPct = (budget.month_to_date / escala) * 100;
  const projetadoPct = (Math.max(budget.projected_month - budget.month_to_date, 0) / escala) * 100;
  const limitePct = limite !== null ? (limite / escala) * 100 : null;

  const hoje = new Date();
  const fimDoMes = new Date(Date.UTC(hoje.getUTCFullYear(), hoje.getUTCMonth(), budget.days_in_month));

  const resumoAcessivel =
    `Consumidas ${formatNumber(budget.month_to_date)} requisições no mês; projeção de ${formatNumber(budget.projected_month)}` +
    (limite !== null ? ` para um limite de ${formatNumber(limite)}.` : ".");

  return (
    <Card density="compact">
      <CardContent density="compact" className="space-y-3 pt-4">
        <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1">
          <span className="inline-flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
            <Gauge className="h-3.5 w-3.5" aria-hidden="true" />
            Orçamento da API
          </span>
          <span className="text-xs tabular-nums text-muted-foreground">
            {budget.pricing_source_code === "JUSTTCG" ? "JustTCG" : budget.pricing_source_code}
            {limite !== null ? <> · plano {formatNumber(limite)}/mês</> : null}
            {budget.daily_limit !== null ? <> · {formatNumber(budget.daily_limit)}/dia</> : null}
          </span>
        </div>

        <dl className="grid grid-cols-2 gap-3 sm:grid-cols-3 sm:gap-6">
          <div className="min-w-0 space-y-0.5">
            <dt className="text-xs text-muted-foreground">Consumido no mês</dt>
            <dd className="text-lg font-semibold tabular-nums text-foreground">{formatNumber(budget.month_to_date)}</dd>
          </div>
          <div className="min-w-0 space-y-0.5">
            <dt className="text-xs text-muted-foreground">Projeção até {fimDoMesFormatter.format(fimDoMes)}</dt>
            <dd className={cn("text-lg font-semibold tabular-nums", excede ? "text-warning" : "text-foreground")}>
              ≈ {formatNumber(budget.projected_month)}
              {limite !== null ? (
                <span className="ml-1.5 text-xs font-normal text-muted-foreground">
                  {Math.round((budget.projected_month / limite) * 100)}% do plano
                </span>
              ) : null}
            </dd>
          </div>
          <div className="min-w-0 space-y-0.5">
            <dt className="text-xs text-muted-foreground">Hoje</dt>
            <dd className="text-lg font-semibold tabular-nums text-foreground">
              {formatNumber(budget.today)}
              {budget.daily_limit !== null ? (
                <span className="ml-1 text-xs font-normal text-muted-foreground">de {formatNumber(budget.daily_limit)}</span>
              ) : null}
            </dd>
          </div>
        </dl>

        <div className="space-y-1.5">
          <div role="img" aria-label={resumoAcessivel} className="relative h-2 w-full overflow-hidden rounded-full bg-surface-muted">
            <div
              className={cn("absolute inset-y-0 left-0", excede ? "bg-warning" : "bg-primary/70")}
              style={{ width: `${Math.min(100, consumidoPct)}%` }}
            />
            <div
              className={cn("absolute inset-y-0", excede ? "bg-warning/35" : perto ? "bg-warning/25" : "bg-primary/25")}
              style={{ left: `${Math.min(100, consumidoPct)}%`, width: `${Math.min(100 - Math.min(100, consumidoPct), projetadoPct)}%` }}
            />
            {limitePct !== null && limitePct < 100 ? (
              <div className="absolute inset-y-0 w-px bg-foreground/60" style={{ left: `${limitePct}%` }} aria-hidden="true" />
            ) : null}
          </div>
          <p className="text-[11px] leading-snug text-muted-foreground">
            Projeção = consumido + ≈ {formatNumber(budget.steady_daily_estimate)}/dia em regime até o fim do mês
            {budget.onboarding_remaining > 0 ? <> + {formatNumber(budget.onboarding_remaining)} da implantação de Sets</> : null}.
            Mês civil (UTC).
          </p>
        </div>
      </CardContent>
    </Card>
  );
}
