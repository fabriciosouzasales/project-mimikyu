import { Activity, AlertTriangle, Clock, ShieldAlert, ShieldCheck, ShieldX } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { Panel } from "@/components/catalogo/panel";
import { Badge } from "@/components/ui/badge";
import { HeroFact } from "@/components/pricing/hero-fact";
import type { PricingSourceHealth } from "@/lib/pricing/queries";
import type { PricingSourceHealthStatus } from "@/lib/pricing/pricing-source-health-status";
import { cn, formatManagerialDateTime, formatNumber } from "@/lib/utils";

const STATUS_ICON: Record<PricingSourceHealthStatus["level"], LucideIcon> = {
  SAUDAVEL: ShieldCheck,
  ATENCAO: ShieldAlert,
  CRITICO: ShieldX,
};

const HEADLINE_ADJETIVO: Record<PricingSourceHealthStatus["level"], string> = {
  SAUDAVEL: "saudáveis",
  ATENCAO: "em atenção",
  CRITICO: "críticas",
};

/** Mesma paleta semântica do Hero de Valor de Mercado (`pricing-overview-hero.tsx`) — halo do ícone de status escalado ao tamanho de destaque do Hero. */
const STATUS_HALO: Record<PricingSourceHealthStatus["level"], string> = {
  SAUDAVEL: "bg-success/10 text-success",
  ATENCAO: "bg-warning/10 text-warning",
  CRITICO: "bg-destructive/10 text-destructive dark:text-destructive-foreground",
};

/**
 * Hero Gerencial de Saúde das Fontes (2026-08-23) — retomada do refinamento
 * visual logo após o encerramento do P0 de performance de `/pricing`
 * (Fabrício: "retomar imediatamente o refinamento visual... Próxima tela:
 * Saúde das Fontes"), com "tratamento Hero completo" explicitamente
 * escolhido por ele diante de duas opções (o outro era polimento leve dos
 * cards por fonte, mantidos como estão logo abaixo deste bloco).
 *
 * Mesma gramática visual do Hero da Visão Geral (`pricing-overview-hero.tsx`,
 * mesmo `Panel`/`HeroFact` — agora extraído em `hero-fact.tsx` para os dois
 * Heros compartilharem, ver esse arquivo) — headline grande + selo de ícone
 * por status + motivos como texto de apoio + faixa de 4 fatos-chave.
 *
 * Os 4 fatos são um ROLL-UP agregado dos mesmos 4 campos que cada card de
 * `SaudeFontesList` já mostra por fonte (Cobertura / Sets / Última
 * sincronização / Erros recentes) — nenhum dado novo, nenhuma RPC nova, só
 * soma/média sobre o array que `admin_get_pricing_source_health()`
 * (migration 3941) já devolve. Fontes inativas não entram nos agregados de
 * cobertura/Sets/erros (mesmo racional de `computePricingSourceHealthStatus`,
 * ver `pricing-source-health-status.ts`), mas ainda contam para "Última
 * sincronização" — uma fonte desativada recentemente ainda teve uma
 * sincronização real que vale mostrar.
 */
export function PricingFontesHero({
  sources,
  status,
}: {
  sources: PricingSourceHealth[];
  status: PricingSourceHealthStatus;
}) {
  const Icon = STATUS_ICON[status.level];
  const ativas = sources.filter((source) => source.isActive);

  const mappingsConfirmedTotal = ativas.reduce((soma, source) => soma + source.mappings.confirmed, 0);
  const mappingsTotal = ativas.reduce((soma, source) => soma + source.mappings.total, 0);
  const coveragePct = mappingsTotal > 0 ? Math.round((mappingsConfirmedTotal / mappingsTotal) * 1000) / 10 : null;

  const setsHealthyTotal = ativas.reduce((soma, source) => soma + source.sets.healthy, 0);
  const setsTotal = ativas.reduce((soma, source) => soma + source.sets.total, 0);

  const ultimaSincronizacao = sources
    .map((source) => source.lastRun?.finishedAt)
    .filter((value): value is string => Boolean(value))
    .sort()
    .at(-1);

  const errosRecentesTotal = ativas.reduce((soma, source) => soma + source.recentFailedRuns, 0);

  return (
    <Panel className="p-4 sm:p-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:gap-4">
        <span
          className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-full", STATUS_HALO[status.level])}
          aria-hidden="true"
        >
          <Icon className="h-5 w-5" />
        </span>
        <div className="min-w-0 flex-1 space-y-1">
          <div className="flex flex-wrap items-center gap-2.5">
            <h2 className="font-heading text-xl font-semibold text-foreground sm:text-2xl">
              Fontes de preço estão {HEADLINE_ADJETIVO[status.level]}
            </h2>
            <Badge variant={status.badgeVariant}>{status.label}</Badge>
          </div>
          <ul className="space-y-0.5">
            {status.reasons.map((motivo) => (
              <li key={motivo} className="text-sm text-muted-foreground">
                {motivo}
              </li>
            ))}
          </ul>
        </div>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3 border-t border-border pt-4 sm:grid-cols-4 sm:gap-4">
        <HeroFact
          icon={Activity}
          label="Cobertura"
          value={coveragePct !== null ? `${coveragePct}%` : "—"}
          progressPct={coveragePct ?? undefined}
        />
        <HeroFact icon={ShieldCheck} label="Sets saudáveis" value={`${formatNumber(setsHealthyTotal)}/${formatNumber(setsTotal)}`} />
        <HeroFact
          icon={Clock}
          label="Última sincronização"
          value={ultimaSincronizacao ? formatManagerialDateTime(ultimaSincronizacao) : "—"}
        />
        <HeroFact
          icon={AlertTriangle}
          label="Erros recentes (7 dias)"
          value={`${formatNumber(errosRecentesTotal)} ${errosRecentesTotal === 1 ? "execução falha" : "execuções falhas"}`}
          valueClassName={errosRecentesTotal > 0 ? "text-warning" : undefined}
        />
      </div>
    </Panel>
  );
}
