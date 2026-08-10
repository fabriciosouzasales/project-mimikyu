import { FileUp } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { ImportarCartasView } from "@/components/catalogo/importar-cartas-view";
import { PageContainer } from "@/components/ui/page";
import { getCardSetsForCartas, getCartasCatalogoStats, getLatestImportJobIncompleteFlags } from "@/lib/catalogo/queries";
import { autoMatchTcgdexSet } from "@/lib/catalogo/tcgdex-lookup";

/**
 * Grupo "Operações" do menu do Catálogo (`nav-config.ts`). Redesenho visual
 * completo em 2026-08-01 (dois protótipos anexados por Fabrício — visão API
 * e visão PDF): esta página absorve o que antes eram duas telas —
 * `ImportarCartasView` (cartões de opção) e `/catalogo/importar-cartas/
 * tcgdex` (`ImportarTcgdexView`, seleção de Coleção + localização automática
 * do Set) — numa só. `tcgdex/page.tsx` virou um redirect para cá (ver
 * comentário lá).
 *
 * `?cardSetId=` resolve a tela a partir da URL, mesmo padrão já usado por
 * `/catalogo/cartas`.
 *
 * **Sem `?fonte=`** (removido em 2026-08-08): o seletor de Fonte (API/PDF)
 * foi retirado desta tela depois que Fabrício encerrou definitivamente o
 * canal PDF (Ciclos 3/4 de `ADR-024` — ver emenda 2026-08-08 no ADR). A
 * fonte TCGdex (API) passa a ser a única opção, então deixou de fazer
 * sentido pedir pra Fabrício escolher — o combobox de Coleção e o botão
 * Analisar (agora sempre visível, sem depender de nenhum toggle) bastam.
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
  searchParams: Promise<{ cardSetId?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Importar Cartas", FileUp);
  if (denied) return denied;

  const { cardSetId } = await searchParams;

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
  //
  // **Emenda (2026-08-09, bug real reportado por Fabrício: "SVP não aparece
  // no combobox" apesar de faltarem 8 cartas).** O motivo é uma lacuna do
  // critério acima: o único job de SVP (01/08) rodou com `total_rows = 218`
  // porque a TCGdex, naquele momento, só listava 218 cartas com dado real —
  // as 218 foram inseridas com sucesso (`inserted_rows = 218`, sem falha),
  // então `getLatestImportJobIncompleteFlags` corretamente não marca esse
  // job como incompleto. O problema é que a TCGdex passou a listar mais
  // cartas *depois* dessa análise (confirmado 226 hoje, ver
  // `docs/05e-catalogo-editorial.md`) — cartas que nunca chegaram a fazer
  // parte de nenhum job desta Coleção, então não existe "linha que falhou"
  // para o critério baseado em job encontrar.
  //
  // A comparação com `total_set_size` que o comentário acima descarta para
  // o caso SV1/SV2 (campo manual, podia ficar *abaixo* da contagem real da
  // TCGdex) continua válida como sinal **complementar**, não substituto: aqui
  // ela pega exatamente o caso que o critério por job não cobre. Os dois
  // critérios em OR não competem — cada um cobre uma lacuna diferente do
  // outro (job incompleto: sobrou linha dentro de um snapshot já buscado;
  // `cardsCatalogados < totalSetSize`: o snapshot mais recente ficou
  // desatualizado frente ao total já confirmado da Coleção).
  const incompleteFlags = await getLatestImportJobIncompleteFlags(
    supabase,
    cardSets.map((cardSet) => cardSet.id),
  );
  const cardSetsParaImportar = cardSets.filter(
    (cardSet) =>
      cardSet.cardsCatalogados === 0 ||
      cardSet.cardsCatalogados < cardSet.totalSetSize ||
      incompleteFlags.get(cardSet.id) === true,
  );
  // KPI "Sem Cartas" continua estrito (zero cartas) — métrica diferente do
  // filtro do seletor acima, não confundir: uma Coleção parcialmente
  // importada some deste contador, mas continua aparecendo no seletor.
  const colecoesSemCartas = cardSets.filter((cardSet) => cardSet.cardsCatalogados === 0).length;
  const totalCartas = cardSets.reduce((sum, cardSet) => sum + cardSet.cardsCatalogados, 0);

  // `selectedCardSet` busca em `cardSets` (lista completa), não em
  // `cardSetsParaImportar` (filtrada) — de propósito, 2026-08-01, oitava
  // rodada: depois que uma importação é confirmada com sucesso, a Coleção
  // pode sair da lista "pendente" (ver `router.refresh()` disparado por
  // `RevisaoImportacaoTable`), mas o painel de resultado desta mesma
  // Coleção ainda selecionada (com o progresso/etapa de confirmação
  // visíveis) precisa continuar resolvendo normalmente — só o combobox
  // (que usa `cardSetsParaImportar` como opções) deve deixar de oferecê-la
  // na próxima escolha.
  const [cartasStats, selectedCardSet] = await Promise.all([
    getCartasCatalogoStats(supabase, totalCartas),
    Promise.resolve(cardSetId ? (cardSets.find((cardSet) => cardSet.id === cardSetId) ?? null) : null),
  ]);

  // `{ code, name }` (era só `.name`, 2026-08-01, bug real corrigido em
  // tcgdex-lookup.ts): autoMatchTcgdexSet agora tenta o id exato da TCGdex
  // pelo código da Coleção antes de cair para busca fuzzy por nome — ver
  // comentário da função.
  const matchResult = selectedCardSet
    ? await autoMatchTcgdexSet({ code: selectedCardSet.code, name: selectedCardSet.name })
    : null;

  return (
    <AppShell title="Importar Cartas" icon={FileUp}>
      <PageContainer>
        {/*
          `key={selectedCardSet?.id}` (2026-08-01, nona rodada, bug real
          reportado por Fabrício: depois de concluir a importação de SV2 e
          selecionar outra Coleção, "o fluxo de progresso não atualiza,
          permanece com as informações do fluxo anterior"). Causa: `
          useAnalyzeJob` (chamado dentro de `ImportarCartasView`) guarda o
          job analisado em `useState` — trocar de Coleção pelo combobox só
          faz `router.push` pra atualizar `?cardSetId=`, o que NÃO remonta
          `ImportarCartasView` (mesma árvore de componente cliente, só as
          props mudam), então o job antigo (de SV2) continuava lá quando
          SV1 era selecionado.

          `key` na identidade da Coleção resolve isso do jeito idiomático
          do React: ao mudar, força o React a desmontar a instância antiga
          de `ImportarCartasView` e montar uma nova do zero, zerando
          `useAnalyzeJob` (e qualquer outro estado interno, como o
          dropdown do combobox) — sem precisar de um `useEffect` de reset
          manual. Não quebra o refresh pós-Confirmar da rodada anterior:
          `router.refresh()` ali não muda `cardSetId`, então a mesma
          Coleção mantém a mesma key e a instância (com o job/progresso já
          concluído) continua montada normalmente.

          Escopo só na Coleção — desde 2026-08-08 não existe mais Fonte
          nesta tela (canal PDF encerrado definitivamente, ver `ADR-024`),
          então esse `key` cobre o único eixo de navegação restante.
        */}
        <ImportarCartasView
          key={selectedCardSet?.id ?? "none"}
          cardSets={cardSetsParaImportar}
          colecoesSemCartas={colecoesSemCartas}
          cardsSemImagem={cartasStats.cardsSemImagem}
          selectedCardSet={selectedCardSet}
          matchResult={matchResult}
        />
      </PageContainer>
    </AppShell>
  );
}
