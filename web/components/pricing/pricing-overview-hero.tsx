import { Activity, Clock, RefreshCw, ShieldAlert, ShieldCheck, ShieldX } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import type { ReactNode } from "react";
import { Panel } from "@/components/catalogo/panel";
import type { PricingAdminOverview } from "@/lib/pricing/queries";
import type { PricingOverviewStatus } from "@/lib/pricing/pricing-overview-status";
import { cn, formatDateTimeParts, formatNumber } from "@/lib/utils";

const STATUS_ICON: Record<PricingOverviewStatus["level"], LucideIcon> = {
  SAUDAVEL: ShieldCheck,
  ATENCAO: ShieldAlert,
  CRITICO: ShieldX,
};

/**
 * v4 (2026-10-12) — a manchete deixou de ser a frase "Valor de Mercado está
 * em atenção" + badge "Atenção" (o mesmo estado dito duas vezes). Agora é o
 * nome do módulo como título curto + um único chip de estado, com a
 * pendência principal (`status.reasons`) como subtítulo. `status.label`
 * continua sendo o texto do chip — nenhuma regra de status mudou.
 */
const STATUS_CHIP: Record<PricingOverviewStatus["level"], string> = {
  SAUDAVEL: "bg-success/10 text-success ring-success/25",
  ATENCAO: "bg-warning/15 text-warning-foreground ring-warning/35 dark:text-warning",
  CRITICO: "bg-destructive/10 text-destructive ring-destructive/30 dark:text-destructive-foreground",
};

const STATUS_DOT: Record<PricingOverviewStatus["level"], string> = {
  SAUDAVEL: "bg-success",
  ATENCAO: "bg-warning",
  CRITICO: "bg-destructive",
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
  SAUDAVEL: "bg-success/10 text-success ring-success/20",
  ATENCAO: "bg-warning/10 text-warning ring-warning/25",
  CRITICO: "bg-destructive/10 text-destructive ring-destructive/25 dark:text-destructive-foreground",
};

/**
 * v4 (2026-10-12) — mini-card de KPI do Hero da Visão Geral. Local a este
 * arquivo de propósito: `HeroFact` continua servindo `pricing-fontes-hero.tsx`
 * sem nenhuma mudança (a reformulação vale só para a Visão Geral).
 * Semântica: `<dt>` = rótulo, `<dd>` = valor + contexto; a barra é decorativa
 * (`aria-hidden`), o número ao lado já diz o mesmo.
 */
function KpiTile({
  icon: Icon,
  label,
  children,
  detail,
  progressPct,
  progressTone = "primary",
}: {
  icon: LucideIcon;
  label: string;
  children: ReactNode;
  detail?: ReactNode;
  progressPct?: number;
  progressTone?: "primary" | "success" | "warning";
}) {
  return (
    <div className="flex min-w-0 flex-col gap-2.5 rounded-lg border border-border/70 bg-background/60 p-4 dark:bg-surface-muted/40 sm:p-5">
      <dt className="flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-[0.08em] text-muted-foreground">
        <Icon className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
        <span className="truncate">{label}</span>
      </dt>
      <dd className="flex min-w-0 flex-1 flex-col gap-2.5">
        <div className="font-heading text-[26px] font-semibold leading-none tracking-tight tabular-nums text-foreground sm:text-[28px]">
          {children}
        </div>
        {progressPct !== undefined && (
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-surface-muted dark:bg-border/60" aria-hidden="true">
            <div
              className={cn(
                "h-full rounded-full motion-safe:transition-[width] motion-safe:duration-500",
                progressTone === "success" && "bg-success",
                progressTone === "warning" && "bg-warning",
                progressTone === "primary" && "bg-primary",
              )}
              style={{ width: `${Math.min(100, Math.max(0, progressPct))}%` }}
            />
          </div>
        )}
        {detail ? <div className="mt-auto space-y-0.5 text-xs leading-snug text-muted-foreground">{detail}</div> : null}
      </dd>
    </div>
  );
}

/** Fração "N/M" com o denominador recuado — o numerador é o dado; leitores de tela ouvem "N de M". */
function Fraction({ value, total }: { value: number; total: number }) {
  return (
    <>
      {formatNumber(value)}
      <span className="text-lg font-medium text-muted-foreground sm:text-xl" aria-hidden="true">
        /{formatNumber(total)}
      </span>
      <span className="sr-only"> de {formatNumber(total)}</span>
    </>
  );
}

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
  // Migration 3978: Expansões com frequência própria (ex.: ME/SV/SWSH/SM diárias, demais a cada 3 dias).
  const dailyExpansions = (policyPrincipal?.expansion_overrides ?? [])
    .filter((o) => o.frequency_days === 1)
    .map((o) => o.expansion_code);
  const frequencyLabel = (days: number) => `${days} ${days === 1 ? "dia" : "dias"}`;
  const Icon = STATUS_ICON[status.level];
  const coveragePct = coverage.eligible_total > 0 ? (coverage.covered / coverage.eligible_total) * 100 : undefined;
  // 3984: "Cobertura" continua medindo Sets com tratamento explícito; o hint separa os que têm
  // fonte de preço dos que a fonte não publica (NOT_FOUND), para 100% não parecer "tudo com preço".
  const semFonte = coverage.not_found ?? 0;
  const coverageHint =
    semFonte > 0 && coverage.confirmed !== undefined
      ? `${formatNumber(coverage.confirmed)} com preço · ${formatNumber(semFonte)} sem fonte`
      : undefined;
  // 3984: Set em implantação ainda não tem refresh — fica fora do denominador da saúde, com hint.
  const emImplantacao = sets.onboarding_pending;
  const setsEmOperacao = Math.max(0, sets.total - emImplantacao);
  const saudeHint = emImplantacao > 0 ? `+${formatNumber(emImplantacao)} em implantação` : undefined;

  const saudeCompleta = setsEmOperacao > 0 && sets.healthy >= setsEmOperacao;
  const saudePct = setsEmOperacao > 0 ? (sets.healthy / setsEmOperacao) * 100 : undefined;
  const lastSync = formatDateTimeParts(last_sync_run?.finished_at ?? null);
  const atualizacaoAtiva = dispatcher?.active ?? false;

  return (
    <Panel className="p-5 sm:p-6">
      <div className="flex items-start gap-4">
        <span
          className={cn("flex h-11 w-11 shrink-0 items-center justify-center rounded-xl ring-1 ring-inset", STATUS_HALO[status.level])}
          aria-hidden="true"
        >
          <Icon className="h-5 w-5" />
        </span>
        <div className="min-w-0 flex-1 space-y-1.5">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
            <h2 className="font-heading text-xl font-semibold tracking-tight text-foreground sm:text-2xl">
              Valor de Mercado
            </h2>
            <span
              className={cn(
                "inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold ring-1 ring-inset",
                STATUS_CHIP[status.level],
              )}
            >
              <span className={cn("h-1.5 w-1.5 rounded-full", STATUS_DOT[status.level])} aria-hidden="true" />
              {status.label}
            </span>
          </div>
          {status.reasons.length > 0 || status.notes.length > 0 ? (
            <ul className="space-y-0.5">
              {status.reasons.map((motivo) => (
                <li key={motivo} className="text-sm text-foreground/80">
                  {motivo}
                </li>
              ))}
              {/* 3984: contexto neutro (implantação em andamento) — não muda o nível, por isso sem cor semântica. */}
              {status.notes.map((nota) => (
                <li key={nota} className="text-sm text-muted-foreground">
                  {nota}
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted-foreground">Sem pendências operacionais.</p>
          )}
        </div>
      </div>

      <dl className="mt-5 grid grid-cols-2 gap-2.5 sm:gap-3 lg:grid-cols-4">
        <KpiTile
          icon={Activity}
          label="Cobertura"
          progressPct={coveragePct}
          detail={coverageHint ? <p>{coverageHint}</p> : null}
        >
          <Fraction value={coverage.covered} total={coverage.eligible_total} />
        </KpiTile>

        <KpiTile
          icon={ShieldCheck}
          label="Saúde dos Sets"
          progressPct={saudePct}
          progressTone={saudeCompleta ? "success" : "warning"}
          detail={saudeHint ? <p>{saudeHint}</p> : null}
        >
          <Fraction value={sets.healthy} total={setsEmOperacao} />
        </KpiTile>

        <KpiTile
          icon={RefreshCw}
          label="Atualização automática"
          detail={
            atualizacaoAtiva && policyPrincipal ? (
              dailyExpansions.length > 0 && policyPrincipal.frequency_days !== 1 ? (
                <>
                  <p>
                    <span className="font-medium text-foreground/80">Diária</span> · {dailyExpansions.join(", ")}
                  </p>
                  <p>
                    <span className="font-medium text-foreground/80">Demais</span> · a cada {frequencyLabel(policyPrincipal.frequency_days)}
                  </p>
                </>
              ) : (
                <p>A cada {frequencyLabel(policyPrincipal.frequency_days)}</p>
              )
            ) : null
          }
        >
          <span className={cn("inline-flex items-center gap-2", atualizacaoAtiva ? "text-success" : "text-warning-foreground dark:text-warning")}>
            <span
              className={cn("h-2 w-2 shrink-0 rounded-full", atualizacaoAtiva ? "bg-success" : "bg-warning")}
              aria-hidden="true"
            />
            {atualizacaoAtiva ? "Ativa" : "Inativa"}
          </span>
        </KpiTile>

        <KpiTile icon={Clock} label="Última sincronização" detail={lastSync ? <p>em {lastSync.date}</p> : null}>
          {lastSync ? (
            <time dateTime={last_sync_run?.finished_at ?? undefined}>{lastSync.time}</time>
          ) : (
            "—"
          )}
        </KpiTile>
      </dl>
    </Panel>
  );
}
