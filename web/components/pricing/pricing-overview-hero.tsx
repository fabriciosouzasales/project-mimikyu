import { Activity, Clock, RefreshCw, ShieldAlert, ShieldCheck, ShieldX } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { Panel } from "@/components/catalogo/panel";
import { Badge } from "@/components/ui/badge";
import { HeroFact } from "@/components/pricing/hero-fact";
import type { PricingAdminOverview } from "@/lib/pricing/queries";
import type { PricingOverviewStatus } from "@/lib/pricing/pricing-overview-status";
import { cn, formatManagerialDateTime, formatNumber } from "@/lib/utils";

const STATUS_ICON: Record<PricingOverviewStatus["level"], LucideIcon> = {
  SAUDAVEL: ShieldCheck,
  ATENCAO: ShieldAlert,
  CRITICO: ShieldX,
};

/**
 * Ajuste v3.5 (2026-08-23) — Fabrício aprovou o teste visual "Valores de
 * Mercado" → "Valor de Mercado" (singular) em toda a linguagem visível do
 * módulo, com a manchete alvo explícita "Valor de Mercado está saudável".
 * Reverte a concordância plural do ajuste v3.4 (que existia só porque o
 * sujeito era plural naquele momento — "Valores de Mercado estão
 * saudáveis") de volta ao singular, agora que o sujeito da frase também é
 * singular. `status.label` ("Saudável"/"Atenção"/"Crítico") é o rótulo do
 * badge — não muda, é um substantivo/adjetivo de status isolado, não parte
 * da frase.
 */
const HEADLINE_ADJETIVO: Record<PricingOverviewStatus["level"], string> = {
  SAUDAVEL: "saudável",
  ATENCAO: "em atenção",
  CRITICO: "crítico",
};

/**
 * v3.6 (2026-08-23) — refinamentos finais pedidos por Fabrício após validar
 * v3.5 em `next dev` real:
 * (1) altura do Hero reduzida ~15-20% — `Panel` `p-6 sm:p-8` → `p-4 sm:p-6`,
 * gaps `gap-4/gap-5` → `gap-3/gap-4`, selo de ícone `h-12 w-12`/`h-6 w-6` →
 * `h-10 w-10`/`h-5 w-5`, manchete `text-2xl sm:text-[28px]` → `text-xl
 * sm:text-2xl`, régua inferior `mt-6 pt-5` → `mt-4 pt-4`. Mantém os mesmos 4
 * fatos (Cobertura/Saúde dos Sets/Atualização Automática/Última
 * sincronização) e o protagonismo do bloco — só o "ar" ao redor encolheu.
 * (2) barra de progresso de Cobertura mais discreta em `HeroFact` — altura
 * `h-1.5` → `h-1`, preenchimento `bg-primary` → `bg-primary/60` (mesmo tom,
 * menos saturado), para apoiar a leitura do percentual sem competir
 * visualmente com a manchete.
 * (3) "Última sincronização" passou de `toLocaleString("pt-BR")` (formato
 * longo, com segundos e vírgula: "22/08/2026, 13:30:17") para
 * `formatManagerialDateTime()` (`lib/utils.ts`, novo) — "22/08/2026 às
 * 13:30".
 */

/** Classes de halo do ícone — mesma paleta semântica do `Badge`/`StatCard tone="danger"`, escaladas para o tamanho de destaque do Hero. */
const STATUS_HALO: Record<PricingOverviewStatus["level"], string> = {
  SAUDAVEL: "bg-success/10 text-success",
  ATENCAO: "bg-warning/10 text-warning",
  CRITICO: "bg-destructive/10 text-destructive dark:text-destructive-foreground",
};

/**
 * Bloco 1 da Visão Geral v3 — HERO GERENCIAL (2026-08-23). Substitui o
 * cabeçalho executivo estreito da v2 (`Panel className="p-4"` com uma linha
 * flex de texto pequeno) por pedido explícito de Fabrício: "Não usar o
 * banner estreito atual", precisava virar um bloco "visualmente dominante".
 *
 * ZERO dado novo, ZERO regra nova — consome exatamente `status` (já
 * calculado por `computePricingOverviewStatus`, intocado nesta rodada) e os
 * mesmos campos de `PricingAdminOverview` que já alimentavam o cabeçalho
 * antigo. A mudança é inteiramente de composição/tamanho/hierarquia:
 * headline grande (font-heading, mesma família de `PageTitle`) + selo de
 * ícone proporcional ao status + lista de motivos como texto de apoio,
 * separados por uma régua da faixa de 4 fatos-chave pedida na diretriz #1
 * (cobertura / saúde dos Sets / Atualização Automática / última
 * sincronização) — os mesmos 4 fatos que antes apareciam como spans de
 * 11px numa linha, agora com label+valor legíveis.
 *
 * Ajuste v3.3 (2026-08-23, mesmo dia): Fabrício removeu por completo a faixa
 * de 4 KPIs de `pricing-overview-stats.tsx` (redundante com este Hero — "a
 * duplicação está consumindo espaço sem agregar valor gerencial") e este
 * Hero passou a ser a ÚNICA síntese executiva do topo. Para compensar a
 * perda do KPI "Frequência de Atualização", o fato "Atualização Automática"
 * ganhou a frequência embutida no próprio valor ("Ativa · a cada 3 dias" em
 * vez de só "Ativa") — mesma fonte já usada pelo KPI removido
 * (`refresh_policy[0].frequency_days`, RPC `get_pricing_admin_overview`,
 * migration 3939), nenhuma RPC nova.
 */
/**
 * P16.1 (2026-08-24, Onboarding de Sets no Pricing — Cobertura e Visibilidade): o fato
 * "Cobertura" TROCOU de fonte de dado, MESMO SLOT visual, mesma composição do Hero — antes
 * `mappings.coverage_pct` (% de `pricing_card_mapping` CONFIRMED sobre o total, um número de
 * confirmação de CARTAS), agora `coverage.covered/coverage.eligible_total` (migration 3950),
 * uma FRAÇÃO de SETS elegíveis do Catálogo com qualquer tratamento no Pricing — mesmo formato
 * `N/N` de "Saúde dos Sets", ao lado. Decisão explícita de Fabrício (rodada de correção
 * conceitual do plano P16): o rótulo "Cobertura" nesta tela deve responder "o Pricing
 * conhece/administra todos os Sets elegíveis?", nunca "que fração das cartas já mapeadas está
 * confirmada?" — a métrica antiga (`mappings.coverage_pct`) continua existindo no contrato de
 * `PricingAdminOverview` e alimentando `computePricingOverviewStatus()` sem nenhuma mudança de
 * regra, só deixou de ocupar este slot do Hero (o sinal de confirmação de cartas continua
 * visível via os tiles "Pendentes"/"Não encontrados" de Atenções e Ações).
 */
export function PricingOverviewHero({ overview, status }: { overview: PricingAdminOverview; status: PricingOverviewStatus }) {
  const { coverage, sets, dispatcher, last_sync_run, refresh_policy } = overview;
  const policyPrincipal = refresh_policy[0] ?? null;
  const Icon = STATUS_ICON[status.level];
  const coveragePct = coverage.eligible_total > 0 ? (coverage.covered / coverage.eligible_total) * 100 : undefined;

  return (
    <Panel className="p-4 sm:p-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:gap-4">
        <span className={cn("flex h-10 w-10 shrink-0 items-center justify-center rounded-full", STATUS_HALO[status.level])} aria-hidden="true">
          <Icon className="h-5 w-5" />
        </span>
        <div className="min-w-0 flex-1 space-y-1">
          <div className="flex flex-wrap items-center gap-2.5">
            <h2 className="font-heading text-xl font-semibold text-foreground sm:text-2xl">
              Valor de Mercado está {HEADLINE_ADJETIVO[status.level]}
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
          value={`${formatNumber(coverage.covered)}/${formatNumber(coverage.eligible_total)}`}
          progressPct={coveragePct}
        />
        <HeroFact icon={ShieldCheck} label="Saúde dos Sets" value={`${formatNumber(sets.healthy)}/${formatNumber(sets.total)}`} />
        <HeroFact
          icon={RefreshCw}
          label="Atualização Automática"
          value={
            dispatcher?.active
              ? `Ativa${policyPrincipal ? ` · a cada ${policyPrincipal.frequency_days} ${policyPrincipal.frequency_days === 1 ? "dia" : "dias"}` : ""}`
              : "Inativa"
          }
          valueClassName={dispatcher?.active ? "text-success" : "text-warning"}
        />
        <HeroFact
          icon={Clock}
          label="Última sincronização"
          value={last_sync_run?.finished_at ? formatManagerialDateTime(last_sync_run.finished_at) : "—"}
        />
      </div>
    </Panel>
  );
}
