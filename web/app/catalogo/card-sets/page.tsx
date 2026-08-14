import { Boxes } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { CatalogoGallery } from "@/components/catalogo/catalogo-gallery";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer } from "@/components/ui/page";
import {
  CATALOGO_SEARCH_CARDS_PAGE_SIZE,
  getCardSetCardCounts,
  getCardSetLogoUrls,
  getCardSetsGroupedByExpansion,
  getExpansoes,
  getGameOptions,
  searchCatalogo,
  summarizeCardSetCardCounts,
  type CardSetsExpansionGroup,
  type CardSetsExpansionGroupWithLogo,
  type CatalogoSearchResult,
} from "@/lib/catalogo/queries";

/**
 * Tela Catálogo — página de entrada do módulo (spec de UX aprovada em
 * 2026-07-31, com os quatro ajustes da mesma data: ação "Novo" cobrindo o
 * domínio completo, ordenação explícita com filtro de Jogo, busca que só
 * atualiza o conteúdo, "Carregar mais" no lugar de rolagem infinita).
 * Substitui a antiga listagem somente-leitura em `/catalogo/card-sets`
 * (`card-sets-table.tsx`, que fica sem uso — ver relatório de pendências).
 * A rota de detalhe (`/catalogo/card-sets/[code]`) não é alterada.
 *
 * Ajuste 2026-07-31 (pedido de Fabrício, "faça todos os ajustes necessários
 * para manter o mesmo padrão da página Expansões"): `jogos`/`expansoes`
 * (sem filtro) e os totais de Card Sets passam a alimentar também
 * `CardSetsStats` — totais sempre globais, independente do filtro/busca
 * ativo na galeria abaixo (mesmo raciocínio de `ExpansoesStats`/`getExpansoes()` sem
 * filtro).
 *
 * Ajuste 2026-08-02 (pedido de Fabrício: "da mesma forma como fizemos na
 * página de expansões, separando-as por Jogo, precisamos na página de
 * Coleções, separá-las por Expansão. Hoje aparecem todas juntas") — modo
 * galeria (sem busca) passou a usar `getCardSetsGroupedByExpansion()` em vez
 * de `getCardSetsForCatalogo()` paginado — mesma mudança estrutural já
 * aplicada a `/catalogo/expansoes` quando ganhou agrupamento por Jogo (ver
 * `expansoes/page.tsx`). URLs assinadas resolvidas de uma vez só para todos
 * os itens de todos os grupos (mesmo padrão de `allPaths` em `expansoes/
 * page.tsx`). Busca (`mode === "search"`) continua flat e paginada, sem
 * mudança — `getCardSetsForCatalogo()` segue em uso só por ela (via
 * `searchCatalogo`/`searchCatalogoAction`).
 *
 * Ajuste 2026-08-14 (gargalo #1 da auditoria de performance desta rota):
 * `getCardSetsOverview()` trocada por `getCardSetsStatsSummary()` — os
 * totais de `CardSetsStats` nunca precisaram dos campos ricos (nome, logo,
 * expansão) que `getCardSetsOverview()` busca; a nova função lê só
 * `catalog_card_set_metrics.cards_cadastradas`, sem join com `card_set`
 * nem geração de signed URLs. `getCardSetsOverview()` não foi alterada,
 * continua servindo `/catalogo` (Visão Geral).
 *
 * Ajuste 2026-08-14, rodada seguinte (gargalo #2 da mesma auditoria): a
 * carga de conteúdo (galeria ou busca) entra no mesmo `Promise.all` das
 * quatro chamadas de jogos/expansões/stats — não tinha dependência real
 * delas, só rodava depois por estar fora do bloco. Ver comentário junto ao
 * `Promise.all` abaixo.
 *
 * Ajuste 2026-08-14, Incremento 5 (elimina leitura redundante entre Stats e
 * galeria): `getCardSetsStatsSummary()` (comentário acima) e
 * `getCardSetsGroupedByExpansion()` liam `catalog_card_set_metrics` sem
 * filtro, cada uma na sua própria chamada, na MESMA requisição em modo
 * galeria — duas agregações `card_counts` (RLS) redundantes por carga de
 * página. `getCardSetsStatsSummary()` foi removida (zero outros
 * consumidores confirmados por busca no repositório); esta página agora
 * dispara `getCardSetCardCounts()` uma única vez (`cardSetCountsPromise`,
 * abaixo) e distribui o mesmo resultado para os Stats
 * (`summarizeCardSetCardCounts()`, função pura) e para
 * `getCardSetsGroupedByExpansion()` (que passou a RECEBER os counts em vez
 * de buscá-los). Concorrência preservada: `cardSetCountsPromise` continua
 * correndo em paralelo com `getGameOptions`/`getExpansoes`/conteúdo, dentro
 * do mesmo `Promise.all` de sempre — nenhuma serialização nova.
 */
// INSTRUMENTAÇÃO TEMPORÁRIA (2026-08-14) — decomposição dos ~2s restantes de
// /catalogo/card-sets após os Incrementos #1-#3 da frente de performance.
// Só mede (performance.now(), sem efeito sobre dado/resultado); não altera
// nenhuma query nem a concorrência já implementada — `timed()` só encadeia um
// `.then()` de log sobre a Promise já em execução, o que não atrasa nem
// resseria seu início. Remover depois da medição (ver docs/log.md).
function timedCardSets<T>(label: string, promise: Promise<T>): Promise<T> {
  const start = performance.now();
  return promise.then((result) => {
    console.log(`[PERF card-sets] ${label}: ${(performance.now() - start).toFixed(1)}ms`);
    return result;
  });
}

export default async function CatalogoCardSetsPage({
  searchParams,
}: {
  searchParams: Promise<{ game?: string; expansion?: string; q?: string }>;
}) {
  const pageStart = performance.now(); // INSTRUMENTAÇÃO TEMPORÁRIA

  const guardStart = performance.now(); // INSTRUMENTAÇÃO TEMPORÁRIA
  const { denied, supabase } = await requireCatalogoAdmin("Coleções", Boxes);
  console.log(`[PERF card-sets] requireCatalogoAdmin: ${(performance.now() - guardStart).toFixed(1)}ms`); // INSTRUMENTAÇÃO TEMPORÁRIA
  if (denied) return denied;

  const { game, expansion, q } = await searchParams;
  const query = q?.trim() ?? "";
  const mode: "gallery" | "search" = query ? "search" : "gallery";

  // Paralelização (2026-08-14, gargalo #2 da auditoria de performance desta
  // rota): a carga de conteúdo (galeria ou busca, quinta posição abaixo) não
  // depende de jogos/expansoesDoJogo/expansoes/cardSetsStats — só de
  // game/expansion/q, já resolvidos acima. Antes rodava numa fase à parte,
  // só começando depois que as outras quatro terminassem por completo (duas
  // fases sequenciais sem dependência real entre si). `content` distingue os
  // dois modos por `Array.isArray()` (galeria devolve um array de grupos,
  // busca devolve um objeto `{ cardSets, cards, hasMoreCards }`) — sem `as`,
  // o TypeScript já estreita o tipo pela própria checagem.
  // Anotação explícita de tipo (INSTRUMENTAÇÃO TEMPORÁRIA): sem ela, a
  // inferência genérica de `timedCardSets<T>` sobre o ternário abaixo não
  // unifica os dois ramos (`Promise<CardSetsExpansionGroup[]>` vs.
  // `Promise<CatalogoSearchResult>`) — problema só desta instrumentação, o
  // código sem instrumentação (Incremento #2) não tinha esse ternário passado
  // como argumento de função genérica.
  // Incremento 5 (2026-08-14): única leitura de `catalog_card_set_metrics`
  // (`card_set_id, cards_cadastradas`) desta requisição — disparada aqui,
  // SEM `await`, continua correndo em paralelo com todo o resto do
  // `Promise.all` abaixo (mesma promise é usada tanto no branch de timing
  // quanto dentro de `getCardSetsGroupedByExpansion`, em modo galeria — não
  // é uma segunda leitura, é a mesma promise com dois consumidores).
  const cardSetCountsPromise = getCardSetCardCounts(supabase);

  const contentPromise: Promise<CardSetsExpansionGroup[] | CatalogoSearchResult> =
    mode === "search"
      ? searchCatalogo(supabase, query, { cardsLimit: CATALOGO_SEARCH_CARDS_PAGE_SIZE, cardsOffset: 0 })
      : getCardSetsGroupedByExpansion(supabase, { gameCode: game, expansionCode: expansion }, cardSetCountsPromise);

  const phase1Start = performance.now(); // INSTRUMENTAÇÃO TEMPORÁRIA
  const [jogos, expansoesDoJogo, expansoes, cardSetCounts, content] = await Promise.all([
    timedCardSets("getGameOptions", getGameOptions(supabase)),
    timedCardSets("getExpansoes(gameCode)", game ? getExpansoes(supabase, { gameCode: game }) : Promise.resolve([])),
    timedCardSets("getExpansoes()", getExpansoes(supabase)),
    timedCardSets("getCardSetCardCounts", cardSetCountsPromise),
    timedCardSets(
      mode === "search" ? "content:search(searchCatalogo)" : "content:gallery(getCardSetsGroupedByExpansion)",
      contentPromise,
    ),
  ]);
  console.log(`[PERF card-sets] Fase1(Promise.all, 5 branches): ${(performance.now() - phase1Start).toFixed(1)}ms`); // INSTRUMENTAÇÃO TEMPORÁRIA

  const cardSetsStats = summarizeCardSetCardCounts(cardSetCounts);

  let initialCards: Awaited<ReturnType<typeof searchCatalogo>>["cards"] = [];
  let searchItems: Awaited<ReturnType<typeof searchCatalogo>>["cardSets"] = [];
  let initialHasMore = false;
  let groups: Awaited<ReturnType<typeof getCardSetsGroupedByExpansion>> = [];

  if (Array.isArray(content)) {
    groups = content;
  } else {
    searchItems = content.cardSets;
    initialCards = content.cards;
    initialHasMore = content.hasMoreCards;
  }

  // URLs assinadas resolvidas de uma vez só, para todos os caminhos
  // envolvidos (grupos + busca) — mesmo padrão de `expansoes/page.tsx`.
  const allPaths = [
    ...groups.flatMap((group) => group.items.map((item) => item.logoStoragePath)),
    ...searchItems.map((item) => item.logoStoragePath),
  ];
  const logoStart = performance.now(); // INSTRUMENTAÇÃO TEMPORÁRIA
  const logoUrls = await getCardSetLogoUrls(supabase, allPaths);
  console.log(`[PERF card-sets] getCardSetLogoUrls (${allPaths.length} paths): ${(performance.now() - logoStart).toFixed(1)}ms`); // INSTRUMENTAÇÃO TEMPORÁRIA
  const withLogo = <T extends { logoStoragePath: string | null }>(item: T) => ({
    ...item,
    logoUrl: item.logoStoragePath ? (logoUrls.get(item.logoStoragePath) ?? null) : null,
  });
  const groupsWithLogo: CardSetsExpansionGroupWithLogo[] = groups.map((group) => ({
    ...group,
    items: group.items.map(withLogo),
  }));
  const cardSetsWithLogo = searchItems.map(withLogo);

  console.log(`[PERF card-sets] TOTAL page.tsx: ${(performance.now() - pageStart).toFixed(1)}ms`); // INSTRUMENTAÇÃO TEMPORÁRIA

  return (
    <AppShell title="Coleções" icon={Boxes}>
      <PageContainer width="wide">
        <CatalogoGallery
          jogos={jogos}
          expansoesDoJogo={expansoesDoJogo}
          expansoes={expansoes}
          cardSetsStats={cardSetsStats}
          gameCode={game}
          expansionCode={expansion}
          query={query}
          initialGroups={groupsWithLogo}
          initialCardSets={cardSetsWithLogo}
          initialHasMore={initialHasMore}
          initialCards={initialCards}
          mode={mode}
        />
      </PageContainer>
    </AppShell>
  );
}
