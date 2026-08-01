import { CreditCard } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { CartasGallery } from "@/components/catalogo/cartas-gallery";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer } from "@/components/ui/page";
import {
  getCardSetLogoUrls,
  getCardSetsForCartas,
  getCartasCatalogoStats,
  getCartasCompletas,
  getExpansoes,
  getGameOptions,
} from "@/lib/catalogo/queries";

/**
 * Cartas — reescrita completa em 2026-07-31 (subciclo Card, escopo
 * somente-leitura: criação/edição administrativa de Card via
 * `internal.write_card()` — Query 2030 — e desativação/reativação via
 * `card.is_active` continuam pendentes, fora do escopo desta rodada). Antes
 * era uma navegação simples por chips de código + tabela (ver histórico
 * git); agora delega toda a composição visual a `CartasGallery` — este
 * arquivo só resolve dados (Card Sets + cartas do Set selecionado, logo do
 * Set selecionado) e checa autorização, mesmo padrão de
 * `expansoes/page.tsx`/`card-sets/page.tsx`.
 *
 * `games`/`expansions` — adicionados em 2026-07-31 junto com o filtro
 * hierárquico Jogo→Expansão→Coleção. Bug relatado por Fabrício na primeira
 * versão do filtro: "o primeiro componente não exibe todos os jogos
 * cadastrados". Causa: o seletor de Jogo era montado a partir de
 * `cardSets` (só Jogos que já têm pelo menos um Card Set catalogado
 * apareciam) — um Jogo recém-cadastrado em `/catalogo/jogos`, ainda sem
 * nenhuma Expansão/Card Set, ficava invisível. `getGameOptions()`/
 * `getExpansoes()` (já existentes, usadas em outras telas) buscam TODOS os
 * Jogos e Expansões cadastrados, independente de já terem Card Sets — o
 * seletor de Jogo/Expansão agora reflete o cadastro real, não só o que já
 * tem cartas catalogadas.
 *
 * Resolução da seleção, em ordem de prioridade: `set` (Card Set exato) >
 * `expansion` (Card Set mais recente daquela Expansão, se existir) > `game`
 * (Card Set mais recente daquele Jogo, se existir) > nenhum parâmetro. Um
 * Jogo/Expansão escolhido que ainda não tem nenhum Card Set é um estado
 * legítimo (não cai de volta para o catálogo inteiro) — a tela mostra o
 * estado vazio apropriado (`CartasGallery`, `!selectedCardSet`).
 *
 * **Sem nenhum parâmetro (clique direto no menu Cartas) — atualizado em
 * 2026-07-31, mesmo dia, rodada seguinte:** pedido de Fabrício, "a página
 * deve trazer carregada as cartas do último card set com cartas
 * cadastradas". Antes o padrão era só "o Card Set mais recente do catálogo"
 * (`cardSets[0]`), sem olhar se ele de fato tinha cartas — um Card Set
 * recém-criado (ainda vazio) virava o padrão e a tela abria no estado vazio
 * "Nenhuma carta catalogada". Agora busca o primeiro (mais recente, `cardSets`
 * já vem ordenado) com `cardsCatalogados > 0`; se NENHUM Card Set tiver
 * cartas ainda, cai de volta para `cardSets[0]` (mesmo comportamento de
 * antes — não há "com cartas" para escolher). Cartas sem imagem importada
 * já são tratadas normalmente pelo estado "Sem imagem" existente em
 * `CartaGridCard`/`CartaZoomDialog` — nenhuma mudança necessária ali.
 */
export default async function CartasPage({
  searchParams,
}: {
  searchParams: Promise<{ set?: string; game?: string; expansion?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Cartas", CreditCard);
  if (denied) return denied;

  const { set, game, expansion } = await searchParams;
  const [cardSets, games, expansions] = await Promise.all([
    getCardSetsForCartas(supabase),
    getGameOptions(supabase),
    getExpansoes(supabase),
  ]);

  let selected = set ? (cardSets.find((cardSet) => cardSet.code === set) ?? null) : null;
  let selectedGameId = "";
  let selectedExpansionId = "";

  if (selected) {
    selectedGameId = selected.gameId;
    selectedExpansionId = selected.expansionId;
  } else if (expansion) {
    selectedExpansionId = expansion;
    selected = cardSets.find((cardSet) => cardSet.expansionId === expansion) ?? null;
    selectedGameId = selected?.gameId ?? expansions.find((row) => row.id === expansion)?.gameId ?? (game ?? "");
  } else if (game) {
    selectedGameId = game;
    selected = cardSets.find((cardSet) => cardSet.gameId === game) ?? null;
    if (selected) selectedExpansionId = selected.expansionId;
  } else {
    // "Último card set com cartas cadastradas" — não o mais recente do
    // catálogo a qualquer custo (ver comentário acima). `cardSets` já vem
    // ordenado mais recente primeiro, então o primeiro match já é o que
    // queremos.
    selected = cardSets.find((cardSet) => cardSet.cardsCatalogados > 0) ?? cardSets[0] ?? null;
    if (selected) {
      selectedGameId = selected.gameId;
      selectedExpansionId = selected.expansionId;
    }
  }

  // Mesma base de `cardSets[].cardsCatalogados` usada pelo indicador
  // "Cartas" (`CartasStats`) — passada para `getCartasCatalogoStats` para
  // que "Sem Imagens" seja calculado sobre o mesmo total, sem divergir.
  const totalCartas = cardSets.reduce((sum, cardSet) => sum + cardSet.cardsCatalogados, 0);

  const [logoUrls, cartasStats, cartas] = await Promise.all([
    getCardSetLogoUrls(supabase, selected?.logoStoragePath ? [selected.logoStoragePath] : []),
    getCartasCatalogoStats(supabase, totalCartas),
    selected ? getCartasCompletas(supabase, selected.id) : Promise.resolve([]),
  ]);
  const selectedLogoUrl = selected?.logoStoragePath ? (logoUrls.get(selected.logoStoragePath) ?? null) : null;

  return (
    <AppShell title="Cartas" icon={CreditCard}>
      <PageContainer width="wide">
        <CartasGallery
          key={`${selectedGameId}|${selectedExpansionId}|${selected?.code ?? ""}`}
          cardSets={cardSets}
          games={games}
          expansions={expansions}
          cartasStats={cartasStats}
          selectedCode={selected?.code}
          selectedLogoUrl={selectedLogoUrl}
          selectedGameId={selectedGameId}
          selectedExpansionId={selectedExpansionId}
          cartas={cartas}
        />
      </PageContainer>
    </AppShell>
  );
}
