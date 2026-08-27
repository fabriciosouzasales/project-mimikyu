import { AlertTriangle, ChevronRight, Clock, Globe, RefreshCw, ScrollText, Activity, Settings2 } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";
import { Badge } from "@/components/ui/badge";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { PricingApiUsageChart } from "@/components/pricing/pricing-api-usage-chart";
import { PricingCoverageTrendChart } from "@/components/pricing/pricing-coverage-trend-chart";
import { PricingOverviewHero } from "@/components/pricing/pricing-overview-hero";
import { PricingSyncRunChart } from "@/components/pricing/pricing-sync-run-chart";
import { computePricingOverviewStatus } from "@/lib/pricing/pricing-overview-status";
import type {
  PricingAdminOverview,
  PricingApiUsagePoint,
  PricingCoverageTrendPoint,
  PricingSyncRunDailyPoint,
} from "@/lib/pricing/queries";
import { cn, formatManagerialDateTime, formatNumber } from "@/lib/utils";

/**
 * Visão Geral v3 — REDESENHO VISUAL PURO (2026-08-23, rejeição explícita de
 * Fabrício da v2: "funcionalmente correta, mas VISUALMENTE REPROVADA").
 * Nenhuma RPC, regra de cálculo ou dado novo nesta rodada — `status` segue
 * vindo, intocado, de `computePricingOverviewStatus()`; `trend`/`syncDaily`/
 * `overview` são os mesmos objetos já buscados em `page.tsx`.
 *
 * Ajuste v3.1 (mesmo dia, correção pós-revisão de Fabrício: "os gráficos
 * atuais estão grandes demais e dominando a página", com
 * `log-atualizacoes-resumo.tsx` apontado como referência direta): a v3
 * inicial tinha colocado os 3 gráficos em 2 linhas assimétricas (2/3+1/3
 * cada) com áreas grandes — revertido para 1 única linha de 3 colunas
 * iguais, na mesma densidade da referência. "Atenções e Ações" saiu da
 * grade de gráficos e virou sua própria linha, largura total, como faixa
 * horizontal de 4 blocos clicáveis (`AcaoTile`). Composição final:
 *
 * 1. HERO GERENCIAL (`PricingOverviewHero`) — bloco dominante, substitui o
 *    banner estreito da v2.
 * 2. 1 linha de 3 gráficos iguais — Evolução das Confirmações, Execuções de
 *    Sincronização, Consumo da API — cada um compacto (ver os componentes
 *    individuais para o detalhe de redução de altura/grid/legenda).
 * 3. Atenções e Ações — linha própria, largura total, 4 blocos clicáveis
 *    hierarquizados (backlog primeiro, depois estado do scheduler).
 * 4. Inventário técnico — rodapé com régua própria (`border-t`), claramente
 *    separado do conteúdo gerencial acima.
 *
 * Ajuste v3.2 (2026-08-23, mesmo dia): Fabrício pediu 2 correções pontuais
 * na captura da v3.1 — bordas arredondadas nas barras de "Execuções de
 * Sincronização" (removidas, ver `pricing-sync-run-chart.tsx`) e espaço em
 * branco sobrando na parte inferior daquele card (corrigido tornando Panel/
 * PanelContent flex, para que o conteúdo reaja à altura real da linha) — e
 * uma troca de conteúdo: "Saúde dos Sets" saiu da faixa de gráficos (já
 * suficientemente representada no Hero e no KPI dedicado) e entrou "Consumo
 * da API" (`PricingApiUsageChart`, migration 3947), mostrando requests/dia
 * para apoiar decisão sobre plano contratado/frequência de atualização.
 *
 * Ajuste v3.3 (2026-08-23, mesmo dia): a faixa de 4 KPIs (item 2 da lista
 * acima até então) foi REMOVIDA por completo — Fabrício apontou que os 4
 * fatos que ela mostrava (Cobertura, Saúde dos Sets, Atualização Automática,
 * Última Sincronização) já estavam representados no Hero, e a duplicação
 * consumia espaço sem agregar valor gerencial. O Hero passou a ser a única
 * síntese executiva do topo — o fato "Atualização Automática" do Hero ganhou
 * a frequência embutida (`Ativa · a cada N dias`) para não perder a
 * informação que só existia no KPI removido ("Frequência de Atualização").
 * Nenhum card substituto foi adicionado nesta faixa, por instrução explícita
 * ("não substituir os cards removidos por novos cards"). `pricing-kpi-card.tsx`
 * não foi apagado — fica disponível para reuso futuro, só não é mais chamado
 * aqui.
 *
 * Ajuste v3.4 (2026-08-23, mesmo dia): Fabrício rejeitou visualmente as
 * rodadas v3/v3.1/v3.2/v3.3 em bloco ("ainda VISUALMENTE FORA DO PADRÃO
 * aprovado") e pediu propagação EXATA do padrão visual de
 * `log-atualizacoes-resumo.tsx` (Catálogo Editorial > Log de Atualizações)
 * para os 3 gráficos — explicitamente "não uma interpretação nova". Cada
 * gráfico passou a renderizar seu próprio `Card density="compact"` (mesmo
 * componente de superfície do Log de Atualizações, não mais `Panel`), com
 * cabeçalho de uma linha só, barras estreitas centralizadas por coluna e
 * altura de 56px — ver o JSDoc de cada componente de gráfico para o detalhe
 * completo. Nenhuma RPC/regra/dado mudou; `PricingOverviewHero` e o painel
 * "Atenções e Ações" também ficaram intocados nesta rodada (restrição
 * explícita de Fabrício, item 9 do pedido).
 *
 * `trend`/`syncDaily`/`apiUsage` podem ser `null` (falha de rede/RPC) sem
 * quebrar o resto da página — cada componente de gráfico trata `null` como
 * lista vazia e degrada para sua própria mensagem "Sem dados disponíveis".
 *
 * Ajuste v3.6 (2026-08-23): rodada de refinamentos finais pedida por
 * Fabrício após validar v3.5 em `next dev` real — só UI/UX, zero RPC/dado
 * novo. Nesta função: "Próximo refresh" passou a usar
 * `formatManagerialDateTime()` (`lib/utils.ts`) em vez de
 * `toLocaleString("pt-BR")` cru (remove segundos, formato "às HH:mm"); os 4
 * tiles de `AcaoTile` ganharam `enfase` (backlog acionável vs. estado
 * operacional, ver JSDoc de `AcaoTile`). O resto do desenho (Hero, grid de
 * gráficos, inventário técnico) está documentado nos próprios componentes
 * tocados — ver `pricing-overview-hero.tsx`, `pricing-sync-run-chart.tsx` e
 * `pricing-api-usage-chart.tsx`.
 */
/**
 * `sets.next_due_at` (RPC `get_pricing_admin_overview`, migration 3939) é o
 * `min(pricing_set_refresh_state.next_due_at)` entre Sets NÃO pausados —
 * ver `queries.ts`. Esse valor pode legitimamente ficar no passado mesmo
 * com o scheduler saudável: é só o instante em que o Set mais atrasado da
 * fila ficou elegível, não uma previsão futura — o dispatcher roda a cada 5
 * minutos (ADR-032) e processa esse backlog de forma assíncrona.
 *
 * Regra final (2026-08-23, revisão pedida por Fabrício após o primeiro
 * ajuste: "nunca devemos exibir 'Próxima atualização' com `next_due_at` no
 * passado, independentemente do dispatcher") — correção só de apresentação,
 * `next_due_at`/scheduler/RPC intocados, nenhuma regra de negócio nova:
 * 1. `next_due_at` no futuro → "Próxima atualização" / data-hora formatada.
 * 2. `next_due_at` no passado E dispatcher ATIVO → "Atualização pendente" /
 *    "Aguardando processamento" — backlog normal, o dispatcher já vai
 *    processar no próximo ciclo de 5 minutos.
 * 3. `next_due_at` no passado E dispatcher INATIVO → "Atualização atrasada"
 *    / a própria data-hora vencida — aqui SIM é sinal real de atraso (nada
 *    está processando o backlog sozinho), diferente do caso 2.
 * 4. `next_due_at` ausente → tratamento neutro original ("—"), independente
 *    do dispatcher.
 * Em nenhum dos 4 casos o rótulo "Próxima atualização" aparece com uma data
 * já vencida — só nos casos 1 (sempre futuro) e 4 (sem data nenhuma).
 */
function deriveProximaAtualizacaoTile(
  nextDueAt: string | null,
  dispatcherAtivo: boolean,
): { label: string; valor: string } {
  if (!nextDueAt) {
    return { label: "Próxima atualização", valor: "—" };
  }
  if (new Date(nextDueAt).getTime() > Date.now()) {
    return { label: "Próxima atualização", valor: formatManagerialDateTime(nextDueAt) };
  }
  if (dispatcherAtivo) {
    return { label: "Atualização pendente", valor: "Aguardando processamento" };
  }
  return { label: "Atualização atrasada", valor: formatManagerialDateTime(nextDueAt) };
}

export function PricingOverviewStats({
  overview,
  trend,
  syncDaily,
  apiUsage,
}: {
  overview: PricingAdminOverview;
  trend: PricingCoverageTrendPoint[] | null;
  syncDaily: PricingSyncRunDailyPoint[] | null;
  apiUsage: PricingApiUsagePoint[] | null;
}) {
  const { sources, mappings, products_count, observations_count, sets, dispatcher, coverage } = overview;

  const status = computePricingOverviewStatus(overview, syncDaily);
  const proximaAtualizacao = deriveProximaAtualizacaoTile(sets.next_due_at, Boolean(dispatcher?.active));
  // P16.1 (2026-08-24): Sets elegíveis do Catálogo ainda sem nenhum tratamento em
  // `pricing_set_mapping` (nem CONFIRMED, nem PENDING, nem NOT_FOUND — a linha nem existe).
  // Só aparece quando `coverage.covered < coverage.eligible_total`; hoje (SWSH8) = 1. É uma
  // pendência CADASTRAL/operacional de onboarding, não uma falha de sincronização — por isso
  // aponta para Mapeamentos de Sets, nunca para Sincronizações/Saúde.
  const setsAguardandoConfiguracao = coverage.eligible_total - coverage.covered;
  const temSetsAguardandoConfiguracao = setsAguardandoConfiguracao > 0;

  return (
    <div className="space-y-6">
      <PricingOverviewHero overview={overview} status={status} />

      {/*
        1 linha de 3 gráficos iguais — v3.4 (2026-08-23): Fabrício rejeitou
        visualmente as rodadas anteriores e pediu propagação EXATA do padrão
        de `log-atualizacoes-resumo.tsx` (Catálogo Editorial > Log de
        Atualizações), "não uma interpretação nova". Cada gráfico agora
        renderiza seu próprio `Card density="compact"` (em vez de um `Panel`
        externo aqui envolvendo o conteúdo) — mesmo cabeçalho de uma linha só
        (ícone + rótulo à esquerda, resumo à direita), mesma altura de barra
        (56px), mesma barra estreita centralizada por coluna. Como nenhum dos
        3 tem mais rodapé (o resumo de "Consumo da API" migrou para o
        cabeçalho, ver `pricing-api-usage-chart.tsx`), as 3 colunas têm
        estrutura idêntica e o grid (`items-stretch`) as mantém na mesma
        altura por construção — nenhum truque de flex necessário aqui.
      */}
      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
        <PricingCoverageTrendChart points={trend} currentTotal={mappings.total} />
        <PricingSyncRunChart points={syncDaily} />
        <PricingApiUsageChart points={apiUsage} />
      </div>

      {/*
        Atenções e Ações — linha própria, largura total, 4 blocos clicáveis
        (era pareada com o gráfico de Execuções na v3 inicial). v3.6
        (2026-08-23): reforço visual pedido por Fabrício — os 2 primeiros
        tiles são backlog acionável (Pendentes/Não encontrados), os 2
        últimos são estado operacional (Atualização Automática/Próximo
        refresh); `enfase` em `AcaoTile` diferencia os dois grupos sem virar
        cards separados (mesmo grid "gap vira borda" de sempre) — ver
        JSDoc de `AcaoTile`.

        P16.1 (2026-08-24): 5º tile condicional "Sets aguardando configuração"
        — só renderiza quando `coverage.covered < coverage.eligible_total`
        (hoje, com SWSH8 sem mapeamento: 1). Reusa o mesmo `AcaoTile`
        `enfase="acionavel"` dos tiles de backlog (é pendência cadastral, não
        falha operacional), aponta para `/pricing/mapeamentos-sets`, e o grid
        vira `lg:grid-cols-5` só quando ele existe — sem essa condição, layout
        idêntico ao anterior (4 colunas).
      */}
      <Panel>
        <PanelHeader>
          <PanelTitle>Atenções e Ações</PanelTitle>
        </PanelHeader>
        <PanelContent className="overflow-hidden rounded-b-lg p-0">
          <div
            className={cn(
              "grid grid-cols-1 gap-px bg-border sm:grid-cols-2",
              temSetsAguardandoConfiguracao ? "lg:grid-cols-5" : "lg:grid-cols-4",
            )}
          >
            {temSetsAguardandoConfiguracao ? (
              <AcaoTile
                enfase="acionavel"
                href="/pricing/mapeamentos-sets"
                icone={<Settings2 className="h-3.5 w-3.5 text-warning" aria-hidden="true" />}
                label="Sets aguardando configuração"
                valor={formatNumber(setsAguardandoConfiguracao)}
              />
            ) : null}
            <AcaoTile
              enfase="acionavel"
              href="/pricing/mapeamentos-cartas?status=PENDING"
              icone={<AlertTriangle className={mappings.pending > 0 ? "h-3.5 w-3.5 text-warning" : "h-3.5 w-3.5 text-muted-foreground/50"} aria-hidden="true" />}
              label="Pendentes"
              valor={formatNumber(mappings.pending)}
            />
            <AcaoTile
              enfase="acionavel"
              href="/pricing/mapeamentos-cartas?status=NOT_FOUND"
              icone={<AlertTriangle className={mappings.not_found > 0 ? "h-3.5 w-3.5 text-warning" : "h-3.5 w-3.5 text-muted-foreground/50"} aria-hidden="true" />}
              label="Não encontrados"
              valor={formatNumber(mappings.not_found)}
            />
            <AcaoTile
              enfase="operacional"
              href="/pricing/sincronizacoes"
              icone={<RefreshCw className="h-3.5 w-3.5 text-muted-foreground" aria-hidden="true" />}
              label="Atualização Automática"
              valor={<Badge variant={dispatcher?.active ? "success" : "warning"}>{dispatcher?.active ? "Ativa" : "Inativa"}</Badge>}
            />
            <AcaoTile
              enfase="operacional"
              href="/pricing/sincronizacoes"
              icone={<Clock className="h-3.5 w-3.5 text-muted-foreground" aria-hidden="true" />}
              label={proximaAtualizacao.label}
              valor={proximaAtualizacao.valor}
            />
          </div>
        </PanelContent>
      </Panel>

      {/* Inventário técnico secundário — separado por régua própria, sem competir com o conteúdo gerencial acima. */}
      <div className="flex flex-wrap items-center gap-x-5 gap-y-1 border-t border-border px-1 pt-3 text-[11px] text-muted-foreground/70">
        <Link href="/pricing/fontes" className="inline-flex items-center gap-1 hover:text-foreground hover:underline">
          <Globe className="h-3 w-3" aria-hidden="true" />
          {formatNumber(sources.active)} de {formatNumber(sources.total)} fontes ativas
        </Link>
        <span className="inline-flex items-center gap-1">
          <ScrollText className="h-3 w-3" aria-hidden="true" />
          {formatNumber(products_count)} produtos precificados
        </span>
        <span className="inline-flex items-center gap-1">
          <Activity className="h-3 w-3" aria-hidden="true" />
          {formatNumber(observations_count)} observações de preço
        </span>
      </div>
    </div>
  );
}

/**
 * Bloco acionável do painel "Atenções e Ações" — v3.1 (era `AcaoRow`, linha
 * inteira empilhada verticalmente dentro de uma coluna 1/3; virou tile
 * horizontal porque o painel passou a ocupar a largura inteira da página,
 * numa faixa de até 4 colunas). Separador entre tiles via o truque de grid
 * "gap vira borda" (container com `gap-px bg-border`, cada tile opaco
 * `bg-surface`) — evita ter que calcular manualmente qual tile fica na
 * borda direita/inferior em cada breakpoint (1/2/4 colunas).
 *
 * `enfase` (v3.6, 2026-08-23) — Fabrício pediu para reforçar visualmente que
 * Pendentes/Não encontrados são backlog acionável, enquanto Atualização
 * Automática/Próximo refresh são só estado operacional — sem virar cards
 * separados (mesmo grid único de sempre). `"acionavel"` ganha uma barra de
 * acento à esquerda (`border-l-warning/40`, mesma cor semântica já usada no
 * ícone condicional) e o valor em `font-semibold`; `"operacional"` mantém o
 * tratamento neutro anterior (`border-l-transparent`, `font-medium`). O
 * `ChevronRight` reage a hover via `group-hover` nos dois casos — reforça
 * que a linha inteira é clicável, não só um detalhe visual do canto.
 */
function AcaoTile({
  href,
  icone,
  label,
  valor,
  enfase,
}: {
  href: string;
  icone: ReactNode;
  label: string;
  valor: ReactNode;
  enfase: "acionavel" | "operacional";
}) {
  const acionavel = enfase === "acionavel";
  return (
    <Link
      href={href}
      className={cn(
        "group flex flex-col gap-1.5 border-l-2 bg-surface px-4 py-3.5 transition-colors hover:bg-surface-muted",
        acionavel ? "border-l-warning/40" : "border-l-transparent",
      )}
    >
      <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
        {icone}
        {label}
      </span>
      <span className="flex items-center justify-between gap-2">
        <span className={cn("tabular-nums text-foreground", acionavel ? "text-sm font-semibold" : "text-sm font-medium")}>{valor}</span>
        <ChevronRight
          className="h-3.5 w-3.5 shrink-0 text-muted-foreground/60 transition-colors group-hover:text-foreground"
          aria-hidden="true"
        />
      </span>
    </Link>
  );
}
