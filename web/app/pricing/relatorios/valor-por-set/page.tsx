import { Package } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { ValorPorSetSelector } from "@/components/pricing/valor-por-set-selector";
import { ValorPorSetHero } from "@/components/pricing/valor-por-set-hero";
import { ValorPorSetReport } from "@/components/pricing/valor-por-set-report";
import { ValorPorSetCardsTable } from "@/components/pricing/valor-por-set-cards-table";
import { ValorPorSetPrintButton } from "@/components/pricing/valor-por-set-print-button";
import { ValorPorSetPrintFolha } from "@/components/pricing/valor-por-set-print-folha";
import { ValorPorSetPrintProvider } from "@/components/pricing/valor-por-set-print-context";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import {
  PRICING_REPORT_SET_CARDS_PAGE_SIZE,
  getCardConditions,
  getPricingReportSet,
  getPricingReportSetCards,
  type PricingReportCurrency,
} from "@/lib/pricing/queries";
import { getCardSetLogoUrlById, getCardSetsForCartas, getExpansoes } from "@/lib/catalogo/queries";
import { cn } from "@/lib/utils";

const VALID_CURRENCIES = new Set(["BRL", "USD"]);

// MMKYU Collector contempla só Pokémon TCG no lançamento (decisão de
// produto, 2026-08-23) — seletor de Jogo removido da UI desta tela;
// Expansão/Set são pré-filtrados implicitamente por este código, reusando o
// campo já canônico no banco (`game.code`, seed 800) em vez de inventar uma
// string nova. Estruturas de domínio (game/game_id em Expansion/Card Set)
// permanecem intocadas — isto é só a consulta desta tela, não uma redução
// de capacidade do catálogo.
const POKEMON_GAME_CODE = "POKEMON";

/**
 * Valor por Set (Bloco 5, migrations 3943 + 3944) — seleção Expansão/Set,
 * condição (padrão NM), moeda (padrão BRL, opção USD), valor estimado
 * coberto + cobertura + `isPartial` explícito (agregado, `admin_get_pricing_
 * report_set`), seguido da lista/ranking de cartas que compõem o valuation
 * (`admin_get_pricing_report_set_cards`, migration 3944 — RPC dedicada
 * set-based, sem N chamadas por carta, reconciliação por construção com o
 * agregado via helper compartilhada no banco). Nenhuma agregação no
 * frontend em nenhum dos dois casos.
 *
 * Impressão (v2, 2026-08-23 — reescrita do requisito transversal de
 * 2026-08-22): a folha impressa deixou de refletir só a página de 20
 * cartas exibida em tela — agora imprime o Set completo em documento
 * contínuo. `ValorPorSetPrintProvider` (client, `valor-por-set-print-
 * context.tsx`) envolve cabeçalho+seletores+dashboard+folha; o botão
 * `ValorPorSetPrintButton` busca o conjunto completo sob demanda (client-
 * side, mesma RPC `admin_get_pricing_report_set_cards`, em lotes de até
 * 100 — nunca na carga normal da página, que continua paginada em 20 via
 * `getPricingReportSetCards` abaixo) e só então chama `window.print()`.
 * Seletores/dashboard interativo continuam `print:hidden`, inalterados.
 */
export default async function ValorPorSetPage({
  searchParams,
}: {
  searchParams: Promise<{
    expansion?: string;
    set?: string;
    condition?: string;
    currency?: string;
    page?: string;
  }>;
}) {
  const { denied, supabase } = await requirePricingAdmin("Valor por Set", Package);
  if (denied) return denied;

  const {
    expansion: expansionIdParam,
    set: cardSetId,
    condition: conditionParam,
    currency: currencyParam,
    page: pageParam,
  } = await searchParams;

  const [expansions, cardSets, conditions] = await Promise.all([
    getExpansoes(supabase, { gameCode: POKEMON_GAME_CODE }),
    getCardSetsForCartas(supabase, { gameCode: POKEMON_GAME_CODE }),
    getCardConditions(supabase),
  ]);

  const selectedCardSet = cardSetId ? (cardSets.find((set) => set.id === cardSetId) ?? null) : null;
  const selectedExpansionId = expansionIdParam || selectedCardSet?.expansionId || "";

  // Logo do Set no hero (correção 2026-08-23: a versão anterior buscava o
  // logo da EXPANSÃO — `expansion.logoStoragePath` — no bucket errado
  // (`card-set-logo`, que só contém logos de Card Set), então nunca
  // resolvia a nenhuma URL real. Trocado para `getCardSetLogoUrlById`, o
  // mesmo padrão já usado e validado em "Preço por Carta"
  // (`app/pricing/relatorios/preco-por-carta/page.tsx`) — leitura pontual
  // por PK/`card_set_id`, mesmo bucket `card-set-logo` da própria coleção
  // (não da Expansão). Nenhuma RPC nova.
  const cardSetLogoUrl = cardSetId ? await getCardSetLogoUrlById(supabase, cardSetId) : null;

  const defaultConditionId = conditions.find((c) => c.code === "NM")?.id ?? conditions[0]?.id ?? "";
  const conditionId = conditionParam || defaultConditionId;
  const currency: PricingReportCurrency = VALID_CURRENCIES.has(currencyParam ?? "")
    ? (currencyParam as PricingReportCurrency)
    : "BRL";

  const requestedPage = Math.max(0, Number.parseInt(pageParam ?? "0", 10) || 0);

  const report = cardSetId
    ? await getPricingReportSet(supabase, { cardSetId, conditionId: conditionId || undefined, currency })
    : null;

  let cardsPage = requestedPage;
  let cards = { items: [] as Awaited<ReturnType<typeof getPricingReportSetCards>>["items"], totalCount: 0 };
  if (cardSetId && report) {
    cards = await getPricingReportSetCards(supabase, {
      cardSetId,
      conditionId: conditionId || undefined,
      currency,
      limit: PRICING_REPORT_SET_CARDS_PAGE_SIZE,
      offset: requestedPage * PRICING_REPORT_SET_CARDS_PAGE_SIZE,
    });

    const totalPages = Math.max(1, Math.ceil(cards.totalCount / PRICING_REPORT_SET_CARDS_PAGE_SIZE));
    if (requestedPage > 0 && requestedPage >= totalPages) {
      cardsPage = totalPages - 1;
      cards = await getPricingReportSetCards(supabase, {
        cardSetId,
        conditionId: conditionId || undefined,
        currency,
        limit: PRICING_REPORT_SET_CARDS_PAGE_SIZE,
        offset: cardsPage * PRICING_REPORT_SET_CARDS_PAGE_SIZE,
      });
    }
  }

  return (
    <AppShell title="Valor por Set" icon={Package}>
      <PageContainer className="space-y-4">
        <ValorPorSetPrintProvider
          cardSetId={cardSetId ?? null}
          conditionId={report?.condition.id ?? null}
          currency={report?.currency ?? null}
        >
          <PageHeader className="print:hidden">
            <PageHeading>
              <div className="flex items-center gap-2">
                <Package className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
                <PageTitle>Valor por Set</PageTitle>
              </div>
              <PageDescription>Valor estimado coberto e cobertura de preço das Cartas ativas de um Set.</PageDescription>
            </PageHeading>
            {report && <ValorPorSetPrintButton />}
          </PageHeader>

          {/* pt-10 condicional (2026-08-23, refinamento aprovado por Fabrício): só
              no estado "nenhum Set selecionado" — afasta o bloco seletores+mensagem
              do topo da página, já que aqui não há mais nada abaixo para preencher
              o espaço. Com um Set escolhido, o relatório ocupa a tela normalmente
              e os seletores voltam a ficar colados ao cabeçalho, como sempre. */}
          <div className={cn("print:hidden", !cardSetId && "pt-10")}>
            <ValorPorSetSelector
              expansions={expansions}
              cardSets={cardSets}
              selectedExpansionId={selectedExpansionId}
              selectedCardSetId={cardSetId ?? ""}
            />
          </div>

          {!cardSetId ? (
            <EmptyState
              title="Selecione um Set para ver o relatório"
              description="Use os seletores acima — Expansão e Set."
              className="pt-4 pb-0"
            />
          ) : !report ? (
            <EmptyState
              title="Set não encontrado"
              description="O Set pode ter sido removido, ou o filtro de condição/moeda ficou inválido."
            />
          ) : (
            <>
              <div className="space-y-4 print:hidden">
                {selectedCardSet && (
                  <ValorPorSetHero
                    cardSet={{
                      name: selectedCardSet.name,
                      code: selectedCardSet.code,
                      expansionName: selectedCardSet.expansionName,
                      logoUrl: cardSetLogoUrl,
                      baseSetSize: selectedCardSet.baseSetSize,
                    }}
                    report={report}
                    conditions={conditions}
                  />
                )}
                <ValorPorSetReport report={report} />
                <ValorPorSetCardsTable
                  items={cards.items}
                  totalCount={cards.totalCount}
                  page={cardsPage}
                  baseParams={{
                    expansion: selectedExpansionId,
                    set: cardSetId,
                    condition: report.condition.id,
                    currency: report.currency,
                  }}
                />
              </div>

              <ValorPorSetPrintFolha
                report={report}
                cardSet={
                  selectedCardSet
                    ? {
                        code: selectedCardSet.code,
                        name: selectedCardSet.name,
                        expansionName: selectedCardSet.expansionName,
                        logoUrl: cardSetLogoUrl,
                      }
                    : null
                }
              />
            </>
          )}
        </ValorPorSetPrintProvider>
      </PageContainer>
    </AppShell>
  );
}
