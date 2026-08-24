import { CreditCard } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { RelatorioPrintButton } from "@/components/catalogo/relatorio-print-button";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { CardPicker } from "@/components/pricing/card-picker";
import { PrecoPorCartaFiltros } from "@/components/pricing/preco-por-carta-filtros";
import { PrecoPorCartaPrintFolha, PrecoPorCartaReport } from "@/components/pricing/preco-por-carta-report";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getCardConditions, getPricingReportCard, type PricingReportCurrency } from "@/lib/pricing/queries";
import { getCardFrontImageUrl, getCardSetLogoUrlById } from "@/lib/catalogo/queries";

const DAY_PRESETS = [30, 90, 180, 365] as const;
const VALID_CURRENCIES = new Set(["BRL", "USD"]);

/**
 * Preço por Carta (Bloco 5, migration 3943) — busca/seleção de Carta,
 * condição (padrão NM), moeda (padrão BRL, opção USD), preço atual por
 * fonte/variante e série temporal. Consome só `admin_get_pricing_report_card`
 * — nenhuma agregação no frontend, tudo já vem pronto do RPC (pedido
 * explícito de Fabrício ao autorizar este bloco).
 *
 * Impressão (requisito transversal, 2026-08-22): mesmo padrão dos 8
 * relatórios do Catálogo Editorial — `RelatorioPrintButton` no `PageHeader`
 * (`print:hidden`), busca/filtros também `print:hidden`, e uma
 * `PrecoPorCartaPrintFolha` (`RelatorioFolha`/`Cabecalho`/`Rodape`) que só
 * aparece em impressão, consumindo o mesmo `report` já filtrado exibido em
 * tela — nunca uma segunda busca.
 *
 * v2 (2026-08-23, refinamento estrutural de hero visual aprovado por
 * Fabrício) — imagem da carta e logo do Set passam a compor o hero. Nenhuma
 * RPC nova: `getCardFrontImageUrl`/`getCardSetLogoUrlById`
 * (`lib/catalogo/queries.ts`) são leituras pontuais por PK/`card_id`
 * indexado, reaproveitando exatamente as mesmas tabelas/buckets já lidos em
 * `getCartasCompletas`/`getCardSetByCode` — nunca `search_cards` (que, sem
 * `p_query`, varreria e contaria todas as cartas ativas só para resolver uma
 * imagem). Disparadas em paralelo (`Promise.all`) só quando `report` existe
 * — zero custo quando nenhuma Carta está selecionada ainda.
 *
 * v3 (2026-08-23, recomposição visual) — Hero, Preços e Histórico deixam de
 * ser 3 blocos soltos (`PrecoPorCartaHero` + `PrecoPorCartaReport`) e viram
 * um único `PrecoPorCartaReport` (seções internas com divisor, ver esse
 * arquivo). A barra de busca/filtros perde a caixa com borda/fundo — vira
 * uma faixa fina com só `border-b`, para parecer parte do mesmo relatório em
 * vez de um formulário à parte.
 *
 * v4 (2026-08-23, recomposição "Carta | Histórico de Preço", pós-ECharts/
 * ADR-033) — `PrecoPorCartaFiltros` perde a prop `historyDays`/os presets de
 * período, que migram para o cabeçalho do gráfico
 * (`PrecoPorCartaPeriodoFiltro`, dentro de `preco-por-carta-report.tsx`) —
 * `report.historyDays` já chega pronto no componente, não precisa mais vir
 * daqui. `cardSetLogoUrl` deixa de ser passado para `PrecoPorCartaReport`
 * (logo do Set sai da área principal da tela — continua resolvido aqui e
 * usado só por `PrecoPorCartaPrintFolha`, no cabeçalho da folha impressa).
 * Nenhuma leitura nova: mesmos `getCardFrontImageUrl`/`getCardSetLogoUrlById`
 * de v2.
 */
export default async function PrecoPorCartaPage({
  searchParams,
}: {
  searchParams: Promise<{ card?: string; condition?: string; currency?: string; days?: string }>;
}) {
  const { denied, supabase } = await requirePricingAdmin("Preço por Carta", CreditCard);
  if (denied) return denied;

  const { card: cardId, condition: conditionParam, currency: currencyParam, days: daysParam } = await searchParams;

  const conditions = await getCardConditions(supabase);
  const defaultConditionId = conditions.find((c) => c.code === "NM")?.id ?? conditions[0]?.id ?? "";
  const conditionId = conditionParam || defaultConditionId;
  const currency: PricingReportCurrency = VALID_CURRENCIES.has(currencyParam ?? "")
    ? (currencyParam as PricingReportCurrency)
    : "BRL";
  const parsedDays = Number.parseInt(daysParam ?? "", 10);
  const historyDays = (DAY_PRESETS as readonly number[]).includes(parsedDays) ? parsedDays : 90;

  const report = cardId
    ? await getPricingReportCard(supabase, { cardId, conditionId: conditionId || undefined, currency, historyDays })
    : null;

  const [cardImage, cardSetLogoUrl] = report
    ? await Promise.all([
        getCardFrontImageUrl(supabase, report.card.id),
        getCardSetLogoUrlById(supabase, report.card.cardSetId),
      ])
    : [{ imageUrlPt: null, imageUrlEn: null }, null];
  const cardImageUrl = cardImage.imageUrlPt ?? cardImage.imageUrlEn;

  return (
    <AppShell title="Preço por Carta" icon={CreditCard}>
      <PageContainer className="space-y-3">
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <CreditCard className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Preço por Carta</PageTitle>
            </div>
            <PageDescription>Preço atual por fonte/variante e série temporal de uma Carta específica.</PageDescription>
          </PageHeading>
          {report && <RelatorioPrintButton />}
        </PageHeader>

        {/* v3 (2026-08-23) — barra de análise: sem caixa/borda fechada
            (era `rounded-lg border bg-surface-muted/40`), só uma linha fina
            de separação (`border-b`) — para ler como parte do relatório, não
            como um formulário à parte. */}
        <div className="flex flex-col gap-3 border-b border-border/70 pb-3 print:hidden sm:flex-row sm:flex-wrap sm:items-center sm:justify-between">
          <CardPicker />
          {report && (
            <PrecoPorCartaFiltros conditions={conditions} conditionId={report.condition.id} currency={report.currency} />
          )}
        </div>

        {!cardId ? (
          <EmptyState
            title="Busque uma Carta para ver o relatório"
            description="Use o campo acima para localizar a Carta pelo nome ou número."
          />
        ) : !report ? (
          <EmptyState
            title="Carta não encontrada"
            description="A Carta buscada pode ter sido removida, ou o filtro de condição/moeda ficou inválido."
          />
        ) : (
          <>
            <div className="print:hidden">
              <PrecoPorCartaReport report={report} imageUrl={cardImageUrl} />
            </div>
            <PrecoPorCartaPrintFolha report={report} imageUrl={cardImageUrl} cardSetLogoUrl={cardSetLogoUrl} />
          </>
        )}
      </PageContainer>
    </AppShell>
  );
}
