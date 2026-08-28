import { Info, RefreshCw } from "lucide-react";
import { StateBadge } from "@/components/catalogo/state-badge";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { formatDateTimeParts } from "@/lib/utils";
import type { PricingAdminOverview } from "@/lib/pricing/queries";

/**
 * Traduz a expressão cron do dispatcher (`dispatcher.schedule`, hoje sempre
 * `"*​/5 * * * *"` — ver `database/migrations/3939_create_get_pricing_admin_overview.sql`)
 * para uma descrição amigável (pedido explícito de Fabrício, 2026-08-28: não
 * exibir o cron cru diretamente na tela, só como informação técnica
 * secundária em tooltip). Cobre apenas o padrão de passo em minutos
 * (`*​/N * * * *`), que é o único já usado neste dispatcher — para qualquer
 * outro padrão, cai de volta no próprio cron como "amigável" em vez de
 * arriscar uma tradução errada.
 */
function describeCronSchedule(schedule: string): string {
  const stepMatch = /^\*\/(\d+) \* \* \* \*$/.exec(schedule);
  if (stepMatch) {
    const minutes = Number(stepMatch[1]);
    return `a cada ${minutes} min`;
  }
  return schedule;
}

/**
 * Status do Dispatcher — bloco só-leitura (constraint explícita de
 * Fabrício: sem disparo manual nesta V1, sem mexer em cron nem recalcular
 * `next_due_at` em massa). Reusa `overview.dispatcher`/`overview.sets` já
 * buscados por `get_pricing_admin_overview()` (Bloco 1) — nenhuma RPC nova
 * só para este bloco.
 *
 * Rodada de refinamento visual (2026-08-28, pedido explícito de Fabrício):
 * "Próxima execução" vira o dado tipográfico dominante do card (duas linhas,
 * data em destaque/hora secundária — nunca formato relativo "há X min" como
 * substituto principal); os três totais (saudável/problema/pausado) viram
 * chips (`StateBadge`, mesma taxonomia de tom já usada na tabela de Estado
 * dos Sets); a agenda cron técnica (`dispatcher.schedule`) desce para uma
 * legenda monoespaçada de hierarquia secundária. O aviso de que não há
 * disparo manual permanece como texto curto sempre visível — reduzido, mas
 * deliberadamente NÃO escondido só atrás do tooltip do ícone de informação,
 * por instrução explícita de Fabrício ("não esconder informação operacional
 * importante exclusivamente em tooltip se isso puder gerar expectativa
 * errada"); o tooltip só acrescenta o detalhe (recálculo em massa também
 * indisponível), não substitui o aviso.
 *
 * Ajuste pontual (2026-08-28, pedido explícito de Fabrício, Sincronizações
 * já fechada visualmente antes deste): a expressão cron crua
 * (`dispatcher.schedule`) deixa de aparecer diretamente na legenda — vira
 * `describeCronSchedule()` ("Agenda automática · a cada 5 min") como texto
 * principal, e o cron original só existe agora dentro do `TooltipContent`
 * do ícone de informação, como detalhe técnico secundário. Não altera o
 * agendamento real nem nenhuma regra de negócio — puramente exibição;
 * `dispatcher.schedule` continua lido ao vivo da RPC, nada hardcoded exceto
 * a tradução textual do padrão de cron.
 *
 * Microajuste final (2026-08-28, pedido explícito de Fabrício — tela
 * aprovada visualmente, único ajuste permitido): `pt-2` → `pt-2.5` no rodapé
 * do card, dando um pouco mais de respiro vertical à linha "Agenda
 * automática · a cada 5 min — sem disparo manual" antes do divisor. Nenhuma
 * outra alteração de estrutura, conteúdo, hierarquia, chips, tabela ou dado.
 * Sincronizações considerada VISUALMENTE ENCERRADA a partir deste ajuste.
 */
export function DispatcherStatusPanel({ overview }: { overview: PricingAdminOverview }) {
  const { dispatcher, sets } = overview;
  const nextDue = formatDateTimeParts(sets.next_due_at);

  return (
    <Panel>
      <PanelHeader className="flex-row items-center justify-between">
        <PanelTitle>Dispatcher</PanelTitle>
        {dispatcher && <StateBadge tone={dispatcher.active ? "success" : "warning"}>{dispatcher.active ? "Ativo" : "Inativo"}</StateBadge>}
      </PanelHeader>
      <PanelContent className="space-y-3">
        <div>
          <p className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-muted-foreground">
            <RefreshCw className="h-3 w-3" aria-hidden="true" />
            Próxima execução
          </p>
          {nextDue ? (
            <p className="mt-0.5 leading-tight">
              <span className="block text-lg font-semibold tabular-nums text-foreground">{nextDue.date}</span>
              <span className="text-xs tabular-nums text-muted-foreground">{nextDue.time}</span>
            </p>
          ) : (
            <p className="mt-0.5 text-sm text-muted-foreground">—</p>
          )}
        </div>

        <div className="flex flex-wrap items-center gap-1.5">
          <StateBadge tone="success">{sets.healthy} saudáveis</StateBadge>
          <StateBadge tone="danger">{sets.problem} com problema</StateBadge>
          <StateBadge tone="muted">{sets.paused} pausados</StateBadge>
          <span className="text-[10px] text-muted-foreground">de {sets.total} Sets</span>
        </div>

        <div className="flex items-center justify-between gap-2 border-t border-border pt-2.5">
          <span className="flex items-center gap-1 text-[11px] text-muted-foreground">
            {dispatcher ? `Agenda automática · ${describeCronSchedule(dispatcher.schedule)}` : "Agenda automática"} — sem disparo manual
            <Tooltip>
              <TooltipTrigger asChild>
                <button
                  type="button"
                  aria-label="Mais detalhes sobre a agenda automática"
                  className="text-muted-foreground/70 transition-colors hover:text-foreground"
                >
                  <Info className="h-3 w-3" aria-hidden="true" />
                </button>
              </TooltipTrigger>
              <TooltipContent className="max-w-[220px] space-y-1">
                <p>
                  Disparo manual e recálculo em massa não estão disponíveis nesta tela — o dispatcher roda apenas pela
                  agenda abaixo.
                </p>
                {dispatcher && <code className="block text-[10px] text-muted-foreground">{dispatcher.schedule}</code>}
              </TooltipContent>
            </Tooltip>
          </span>
        </div>
      </PanelContent>
    </Panel>
  );
}
