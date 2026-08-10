import { BookOpen, Layers3 } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { RelatorioCabecalho } from "@/components/catalogo/relatorio-cabecalho";
import { RelatorioColecaoSeletor } from "@/components/catalogo/relatorio-colecao-seletor";
import { RelatorioFolha } from "@/components/catalogo/relatorio-folha";
import { RelatorioPrintButton } from "@/components/catalogo/relatorio-print-button";
import { RelatorioRodape } from "@/components/catalogo/relatorio-rodape";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getCardSetByCode, getCardSetsForCartas } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

const TITULO = "Resumo da Coleção";
const SUBTITULO = "Totais, cobertura por idioma e estado geral da Coleção.";

const LANGUAGE_DISPLAY_NAME: Record<string, string> = {
  en: "Inglês",
  "pt-BR": "Português",
};

/**
 * Relatório "Resumo da Coleção" (Central de Relatórios, V1 aprovada por
 * Fabrício, 2026-08-09) — ficha imprimível de uma única Coleção (totais,
 * cobertura por idioma, estado geral). Reaproveita `getCardSetByCode()`,
 * já existente (mesmo dado do cabeçalho do hub de Card Set) — sem função de
 * query nova para este relatório, só uma apresentação diferente do mesmo
 * dado.
 *
 * Visual alinhado à baseline do Checklist por Coleção (2026-08-09, mesmo
 * dia, rodada seguinte à aprovação do Checklist): `RelatorioFolha` + logo da
 * Coleção no `RelatorioCabecalho` (é um relatório de uma Coleção só, mesma
 * identificação usada no Checklist). Sem tabela/`<thead>` repetido aqui — a
 * ficha é sempre curta o bastante para caber numa única folha, ao contrário
 * dos relatórios que listam Cartas. Cores de texto fixas (`neutral-*`, não
 * os tokens de tema do app) para bater com o resto da folha branca — uma
 * folha impressa não muda com dark mode.
 *
 * Cabeçalho reorganizado em 3 linhas (2026-08-09, mesmo dia, rodada seguinte
 * — ver `checklist/page.tsx` para o mesmo ajuste e o racional completo):
 * identificação da Coleção em destaque na linha 1, nome fixo do relatório
 * ("Resumo da Coleção") na linha 2, subtítulo na linha 3 — via prop
 * `identificacaoColecao` de `RelatorioCabecalho`, em vez do título único
 * concatenado ("Resumo da Coleção — ME4 · Caos Ascendente").
 */
export default async function RelatorioResumoPage({
  searchParams,
}: {
  searchParams: Promise<{ cardSet?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Catálogo editorial", BookOpen);
  if (denied) return denied;

  const { cardSet: cardSetCode } = await searchParams;
  const [cardSets, cardSet] = await Promise.all([
    getCardSetsForCartas(supabase),
    cardSetCode ? getCardSetByCode(supabase, cardSetCode) : Promise.resolve(null),
  ]);

  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer>
        <PageHeader className="print:hidden">
          <PageHeading>
            <div className="flex items-center gap-2">
              <Layers3 className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Resumo{cardSet ? ` — ${cardSet.code} · ${cardSet.name}` : " da Coleção"}</PageTitle>
            </div>
            <PageDescription>{SUBTITULO}</PageDescription>
          </PageHeading>
          {cardSet && <RelatorioPrintButton />}
        </PageHeader>

        <RelatorioColecaoSeletor cardSets={cardSets} selectedCode={cardSetCode} basePath="/catalogo/relatorios/resumo" />

        {!cardSet ? (
          <Card density="compact">
            <CardContent density="compact" className="pt-4">
              <EmptyState title="Selecione uma Coleção" description="Escolha uma Coleção acima para gerar o resumo." />
            </CardContent>
          </Card>
        ) : (
          <RelatorioFolha>
            <RelatorioCabecalho
              titulo={TITULO}
              subtitulo={SUBTITULO}
              identificacaoColecao={`${cardSet.code} · ${cardSet.name}`}
              colecaoLogoUrl={cardSet.logoUrl}
            />

            <div className="space-y-4 px-6 pb-6 print:px-0">
              <div className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm sm:grid-cols-3">
                <div>
                  <p className="text-xs text-neutral-500">Jogo</p>
                  <p className="text-neutral-900">{cardSet.gameName}</p>
                </div>
                <div>
                  <p className="text-xs text-neutral-500">Expansão</p>
                  <p className="text-neutral-900">
                    {cardSet.expansionCode} — {cardSet.expansionName}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-neutral-500">Tipo de Set</p>
                  <p className="text-neutral-900">{cardSet.setType}</p>
                </div>
                <div>
                  <p className="text-xs text-neutral-500">Cards totais (base + secretas)</p>
                  <p className="text-neutral-900">
                    {formatNumber(cardSet.baseSetSize)} + {formatNumber(cardSet.totalSetSize - cardSet.baseSetSize)} ={" "}
                    {formatNumber(cardSet.totalSetSize)}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-neutral-500">Cartas cadastradas</p>
                  <p className="text-neutral-900">
                    {formatNumber(cardSet.cardsCatalogados)}/{formatNumber(cardSet.totalSetSize)}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-neutral-500">Cartas pendentes de cadastro</p>
                  <p className="text-neutral-900">{formatNumber(cardSet.cardsPendentes)}</p>
                </div>
                <div>
                  <p className="text-xs text-neutral-500">Cartas com imagem canônica</p>
                  <p className="text-neutral-900">
                    {formatNumber(cardSet.cardsComImagem)}/{formatNumber(cardSet.cardsCatalogados)}
                  </p>
                </div>
                <div>
                  <p className="text-xs text-neutral-500">Imagens completas</p>
                  <p className="text-neutral-900">{cardSet.temImagensCompletas ? "Sim" : "Não"}</p>
                </div>
                <div>
                  <p className="text-xs text-neutral-500">Data de lançamento</p>
                  <p className="text-neutral-900">
                    {cardSet.releaseDate ? new Date(cardSet.releaseDate).toLocaleDateString("pt-BR") : "—"}
                  </p>
                </div>
              </div>

              {cardSet.coberturaPorIdioma.length > 0 && (
                <div className="space-y-2 border-t border-neutral-200 pt-3">
                  <p className="text-xs font-medium uppercase tracking-wide text-neutral-500">Cobertura por idioma</p>
                  <div className="space-y-1.5">
                    {cardSet.coberturaPorIdioma.map((cobertura) => {
                      const percentual =
                        cardSet.cardsCatalogados > 0
                          ? Math.round((cobertura.cardsComImagem / cardSet.cardsCatalogados) * 100)
                          : 0;
                      return (
                        <div key={cobertura.languageCode} className="flex items-center justify-between text-xs">
                          <span className="text-neutral-500">
                            {LANGUAGE_DISPLAY_NAME[cobertura.languageCode] ?? cobertura.languageCode}
                          </span>
                          <span className="tabular-nums text-neutral-900">
                            {percentual}% · {formatNumber(cobertura.cardsComImagem)}/{formatNumber(cardSet.cardsCatalogados)}
                          </span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>

            <RelatorioRodape />
          </RelatorioFolha>
        )}
      </PageContainer>
    </AppShell>
  );
}
