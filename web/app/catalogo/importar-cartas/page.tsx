import { FileUp } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { ImportarCartasView } from "@/components/catalogo/importar-cartas-view";
import { PageContainer } from "@/components/ui/page";
import { getCardSetsForCartas, getCartasCatalogoStats, getLatestImportJobIncompleteFlags } from "@/lib/catalogo/queries";
import { autoMatchTcgdexSet } from "@/lib/catalogo/tcgdex-lookup";

type Fonte = "api" | "pdf";

/**
 * Grupo "Operações" do menu do Catálogo (`nav-config.ts`). Redesenho visual
 * completo em 2026-08-01 (dois protótipos anexados por Fabrício — visão API
 * e visão PDF): esta página absorve o que antes eram duas telas —
 * `ImportarCartasView` (cartões de opção) e `/catalogo/importar-cartas/
 * tcgdex` (`ImportarTcgdexView`, seleção de Coleção + localização automática
 * do Set) — numa só. `tcgdex/page.tsx` virou um redirect para cá (ver
 * comentário lá).
 *
 * `?fonte=` (api | pdf, default api) e `?cardSetId=` resolvem a tela a
 * partir da URL, mesmo padrão já usado por `/catalogo/cartas`.
 *
 * **Sem `?jobId=`** (removido em 2026-08-01, terceira rodada): um job
 * aberto e sua Revisão não são mais representados na URL — o fluxo inteiro
 * "Analisar → progresso → Revisão" passou a viver em estado de componente
 * cliente dentro de `ImportarCartasView`/`importar-tcgdex-view.tsx`, sem
 * nenhuma navegação/redirect no meio (ver comentário de
 * iniciarImportacaoTcgdex em tcgdex/actions.ts). Um `router.push`/redirect
 * pra representar o job na URL remonta a página do zero no servidor,
 * destruindo qualquer estado de progresso já visível — exatamente o
 * problema que Fabrício reportou ("a tabela... é carregada em uma nova
 * página").
 */
export default async function ImportarCartasPage({
  searchParams,
}: {
  searchParams: Promise<{ cardSetId?: string; fonte?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Importar Cartas", FileUp);
  if (denied) return denied;

  const { cardSetId, fonte: fonteParam } = await searchParams;
  const fonte: Fonte = fonteParam === "pdf" ? "pdf" : "api";

  const cardSets = await getCardSetsForCartas(supabase);
  // Seletor de Coleção — ver comentário acima de getCardSetsForCartas em
  // queries.ts. Restrito originalmente (2026-08-01) só às Coleções sem
  // nenhuma carta; ampliado no mesmo dia (rodada seguinte, bug real
  // reportado por Fabrício: "não consigo retomar a importação de SV1 e
  // SV2" — os dois tinham importação parcial, com linhas que falharam na
  // confirmação, e ficavam invisíveis nesta tela mesmo faltando cartas).
  //
  // Critério: sem nenhuma carta ainda, OU o job de importação mais recente
  // ficou incompleto (`getLatestImportJobIncompleteFlags`, ver queries.ts —
  // comparar contra `card_set.total_set_size` foi tentado primeiro e
  // descartado, esse campo nem sempre reflete a contagem real da TCGdex).
  // Reimportar um set parcial não duplica nada: o job de confirmação
  // (admin_confirm_catalog_import) já trata cada linha por correspondência
  // (NEW/MATCHED/CONFLICT — ADR-024), então as cartas já cadastradas
  // aparecem como MATCHED (sem-op) e só as que faltam entram como NEW.
  const incompleteFlags = await getLatestImportJobIncompleteFlags(
    supabase,
    cardSets.map((cardSet) => cardSet.id),
  );
  const cardSetsParaImportar = cardSets.filter(
    (cardSet) => cardSet.cardsCatalogados === 0 || incompleteFlags.get(cardSet.id) === true,
  );
  // KPI "Sem Cartas" continua estrito (zero cartas) — métrica diferente do
  // filtro do seletor acima, não confundir: uma Coleção parcialmente
  // importada some deste contador, mas continua aparecendo no seletor.
  const colecoesSemCartas = cardSets.filter((cardSet) => cardSet.cardsCatalogados === 0).length;
  const totalCartas = cardSets.reduce((sum, cardSet) => sum + cardSet.cardsCatalogados, 0);

  const [cartasStats, selectedCardSet] = await Promise.all([
    getCartasCatalogoStats(supabase, totalCartas),
    Promise.resolve(cardSetId ? (cardSetsParaImportar.find((cardSet) => cardSet.id === cardSetId) ?? null) : null),
  ]);

  // `{ code, name }` (era só `.name`, 2026-08-01, bug real corrigido em
  // tcgdex-lookup.ts): autoMatchTcgdexSet agora tenta o id exato da TCGdex
  // pelo código da Coleção antes de cair para busca fuzzy por nome — ver
  // comentário da função.
  const matchResult =
    selectedCardSet && fonte === "api"
      ? await autoMatchTcgdexSet({ code: selectedCardSet.code, name: selectedCardSet.name })
      : null;

  return (
    <AppShell title="Importar Cartas" icon={FileUp}>
      <PageContainer>
        <ImportarCartasView
          cardSets={cardSetsParaImportar}
          colecoesSemCartas={colecoesSemCartas}
          cardsSemImagem={cartasStats.cardsSemImagem}
          selectedCardSet={selectedCardSet}
          fonte={fonte}
          matchResult={matchResult}
        />
      </PageContainer>
    </AppShell>
  );
}
