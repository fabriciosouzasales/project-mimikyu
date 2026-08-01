"use client";

import { CreditCard, Search } from "lucide-react";
import { useRouter } from "next/navigation";
import { useMemo, useState, type CSSProperties } from "react";
import { flushSync } from "react-dom";
import { CartasStats } from "@/components/catalogo/cartas-stats";
import { HoloCard } from "@/components/catalogo/holo-card";
import { RaritySymbol } from "@/components/catalogo/rarity-symbol";
import { SetTypeTag } from "@/components/catalogo/set-type-tag";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { formatarData } from "@/lib/format-date";
import { cn } from "@/lib/utils";
import type {
  CartaCompletaRow,
  CartasCatalogoStats,
  CatalogoCardSetRow,
  ExpansaoRow,
  GameOption,
} from "@/lib/catalogo/queries";

/** Quantas cartas aparecem antes do botão "Ver todas" — ponto 10 do pedido de Fabrício ("deve ser exibido inicialmente parte do card set"). Sem critério objetivo único no pedido; 30 cobre ~5 linhas em telas largas (grade de 6-7 colunas) sem sobrecarregar o primeiro carregamento de um Set grande. */
const PAGE_SIZE = 30;

function getInitials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]?.toUpperCase() ?? "")
    .join("");
}

/**
 * `collector_total` é `INTEGER` no banco (perde zeros à esquerda) —
 * diferente de `collector_number`, que é `VARCHAR` e preserva o formato
 * oficial exato (ver comentário da coluna em `140_create_card_table.sql`).
 * Pedido de Fabrício (2026-07-31, print de uma carta real de um Card Set
 * com 86 cartas): "em cartas pertencentes a card set com set base inferior
 * a 100 cartas o número que representa o collector-total precisa ter 3
 * dígitos... deveria ter a identificação 001/086 e não 001/86". Em vez de
 * checar `base_set_size` do Card Set (uma consulta a mais), o padStart(3)
 * cobre exatamente o mesmo caso — sets com 100+ cartas já têm 3+ dígitos
 * naturalmente, então a regra "mínimo 3 dígitos" e "sets com menos de 100
 * cartas" descrevem o mesmo resultado.
 */
function formatCollectorTotal(total: number): string {
  return String(total).padStart(3, "0");
}

/** Texto completo de identificação ("001/086", ou só "001" sem total) — mesmo formato exibido em `CartaGridCard`, reaproveitado pela busca (`filtered`) para que buscar pelo texto exatamente como aparece na tela sempre encontre a carta. */
function cartaFullNumber(carta: Pick<CartaCompletaRow, "collectorNumber" | "collectorTotal">): string {
  return carta.collectorTotal ? `${carta.collectorNumber}/${formatCollectorTotal(carta.collectorTotal)}` : carta.collectorNumber;
}

/**
 * "94 cartas (86 base + 8 secretas)" — ou só "86 cartas" quando o Card Set
 * não tem secretas (`totalSetSize === baseSetSize`, o caso de `PROMO`/
 * `ENERGY`, únicos tipos com essa igualdade obrigatória por constraint —
 * `ck_card_set_promo_size`). Secretas = `totalSetSize - baseSetSize`, mesma
 * fórmula documentada no comentário de `120_create_card_set_table.sql`
 * ("A quantidade de cartas secretas será calculada pela diferença").
 */
function formatCardSetTotals(baseSetSize: number, totalSetSize: number): string {
  const secretas = totalSetSize - baseSetSize;
  if (secretas <= 0) return `${totalSetSize} carta${totalSetSize === 1 ? "" : "s"}`;
  return `${totalSetSize} cartas (${baseSetSize} base + ${secretas} secreta${secretas === 1 ? "" : "s"})`;
}

/** Idioma da imagem exibida no grid/modal — alternador adicionado em 2026-07-31 (pedido de Fabrício: "incluir um componente para alternar entre imagens das cartas em PT e IN"). */
type ImageLanguage = "pt-BR" | "en";

/**
 * Resolve a imagem de uma carta no idioma escolhido, com fallback para o
 * outro idioma quando o escolhido não foi importado para aquela carta
 * específica — nem todo Card Set tem os dois idiomas completos (ver
 * `pickCardFrontPath` em `queries.ts`), então cair para "Sem imagem" quando
 * a carta na verdade tem uma imagem (só que no outro idioma) seria pior do
 * que mostrar a alternativa disponível.
 */
function cartaImageUrl(carta: CartaCompletaRow, language: ImageLanguage): string | null {
  return language === "pt-BR" ? (carta.imageUrlPt ?? carta.imageUrlEn) : (carta.imageUrlEn ?? carta.imageUrlPt);
}

/**
 * View Transitions API (`document.startViewTransition`) — novo em
 * 2026-07-31, pedido de Fabrício: "quero mais fluidez no movimento de
 * zoom... quero que o movimento pareça realmente uma ampliação da carta",
 * rejeitando o zoom+fade genérico do Dialog (`animate-dialog-in`, que salta
 * direto para o tamanho final). API nativa do navegador, sem dependência
 * nova (o sandbox de build não tem acesso a registry npm — mesma restrição
 * já registrada para `HoloCard`). Tipagem própria em vez de depender do
 * `lib.dom.d.ts` do ambiente incluir `startViewTransition` (ainda
 * inconsistente entre versões de TypeScript/Next.js).
 *
 * Mecanismo: `flushSync` força o `setState` a commitar de forma síncrona
 * dentro do callback — o `startViewTransition` exige isso para conseguir
 * capturar o DOM "antigo" e o "novo" em dois instantes bem definidos, e sem
 * `flushSync` o React adiaria o commit para depois do callback já ter
 * retornado. Sem suporte no navegador (ou com `prefers-reduced-motion:
 * reduce`), cai direto para a atualização normal — o Dialog volta a usar
 * seu zoom+fade padrão (`animated` continua `true` nesse caso).
 */
type DocumentWithViewTransitions = Document & {
  startViewTransition?: (callback: () => void) => unknown;
};

function canUseViewTransitions(): boolean {
  if (typeof document === "undefined" || typeof window === "undefined") return false;
  if (!(document as DocumentWithViewTransitions).startViewTransition) return false;
  return !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function runWithViewTransition(update: () => void) {
  if (canUseViewTransitions()) {
    (document as DocumentWithViewTransitions).startViewTransition?.(() => flushSync(update));
  } else {
    update();
  }
}

/** Nome compartilhado entre a miniatura do grid e a imagem do modal ampliado — mesmo princípio de "shared element" que faz o navegador morfar uma na outra em vez de só cross-fade. Prefixo garante um `<custom-ident>` válido em CSS mesmo quando `id` (UUID) começa com dígito. */
function cartaViewTransitionName(id: string): string {
  return `carta-img-${id}`;
}

/**
 * Tela Cartas — reescrita completa em 2026-07-31 (subciclo Card do
 * ADR-023, escopo somente-leitura: criação/edição administrativa de Card
 * continua pendente). Pedido explícito de Fabrício: "esse ciclo é um dos
 * mais importantes do sistema... precisamos caprichar no visual". Segue o
 * mesmo padrão estrutural de `ExpansoesGallery`/`CatalogoGallery`
 * (`PageHeader` + `Card` com busca/filtro no cabeçalho + grid), com
 * adições próprias desta tela:
 *
 * 1. Indicadores do tema Cartas (`CartasStats`) antes do filtro/grid —
 *    substituem a barra "Recentes" (3 chips de Card Set + seletor "outra
 *    coleção") que abria a tela nas primeiras versões. Removida em
 *    2026-07-31 (rodada seguinte à introdução do filtro Jogo→Expansão→
 *    Coleção): pedido de Fabrício, "perdeu o sentido de tê-lo na página com
 *    os filtros que incluímos... vamos voltar ao padrão das outras
 *    páginas" — mesmo padrão `StatCard`/`StatsRow` já usado em Jogos/
 *    Expansões/Coleções.
 * 2. Filtro "Expansão" + filtro "Coleção" lado a lado, ao lado da busca —
 *    também ajuste da mesma rodada ("ao lado da barra de pesquisa... deve
 *    ser acrescentado o filtro de Expansão antes, com sincronismo entre os
 *    filtros"). "Expansão" não tem estado próprio: seu valor é sempre
 *    derivado do Card Set selecionado, e trocá-lo navega para o Card Set
 *    mais recente daquela Expansão; "Coleção" mostra só os Sets da
 *    Expansão atualmente selecionada.
 * 3. `HoloCard` (efeito de hover) em cada carta do grid e no modal
 *    ampliado (`CartaZoomDialog`), numeração/nome/símbolo de raridade
 *    discretos abaixo de cada imagem (`CartaGridCard`).
 *
 * `key={selectedCode}` no componente (ver `page.tsx`) reseta busca/filtros/
 * "Ver todas" a cada troca de Set — mesmo princípio de `key={cardSet.id}`
 * já usado em `EditCardSetForm` para isolar estado por entidade.
 */
export function CartasGallery({
  cardSets,
  games,
  expansions,
  cartasStats,
  selectedCode,
  selectedLogoUrl,
  selectedGameId,
  selectedExpansionId,
  cartas,
}: {
  /** Todos os Card Sets, mais recentes primeiro — alimenta o seletor "Coleção" e os indicadores (`CartasStats`). */
  cardSets: CatalogoCardSetRow[];
  /** Todos os Jogos cadastrados (independente de já terem Card Sets) — alimenta o seletor "Jogo". */
  games: GameOption[];
  /** Todas as Expansões cadastradas (independente de já terem Card Sets) — alimenta o seletor "Expansão". */
  expansions: ExpansaoRow[];
  /** Contagens agregadas (variações, imagens, cartas sem imagem) para `CartasStats` — resolvidas em `page.tsx` via `getCartasCatalogoStats()`. */
  cartasStats: CartasCatalogoStats;
  selectedCode?: string;
  /** URL assinada da logo do Card Set selecionado (bucket privado `card-set-logo`), já resolvida em `page.tsx` — `null` sem logo cadastrada. */
  selectedLogoUrl: string | null;
  /** "" = "Selecionar Todos". Resolvido em `page.tsx` a partir de `set`/`expansion`/`game` na URL — ver comentário ali sobre a prioridade de resolução. */
  selectedGameId: string;
  /** "" = "Selecionar Todos". */
  selectedExpansionId: string;
  cartas: CartaCompletaRow[];
}) {
  const router = useRouter();
  const [search, setSearch] = useState("");
  const [selectedRarities, setSelectedRarities] = useState<Set<string>>(new Set());
  const [selectedCategories, setSelectedCategories] = useState<Set<string>>(new Set());
  const [showAll, setShowAll] = useState(false);
  const [zoomCarta, setZoomCarta] = useState<CartaCompletaRow | null>(null);
  // Idioma da imagem exibida no grid/modal — pt-BR por padrão (mesma
  // prioridade que já existia antes do alternador, `IMAGE_LANGUAGE_PRIORITY`
  // em `queries.ts`). Estado local (não vai para a URL): pedido de Fabrício
  // não menciona persistência entre navegações, e o `key={selectedCode}` já
  // reseta esse estado a cada troca de Coleção como os demais.
  const [imageLanguage, setImageLanguage] = useState<ImageLanguage>("pt-BR");
  // Qual carta, no máximo uma por vez, deve carregar o `viewTransitionName`
  // compartilhado — ver comentário em `runWithViewTransition`/bug corrigido
  // em 2026-07-31 (mesmo dia): dar o nome a TODAS as cartas do grid
  // simultaneamente fazia o navegador capturar e "hoistar" as 122 cartas
  // para a árvore de pseudo-elementos da transição de uma vez, e a ordem de
  // pintura entre elas colocava vizinhas na frente da carta em animação
  // (bug relatado por Fabrício, print mostrando a carta clicada atrás das
  // demais durante o movimento). Só a carta ativa pode ter um nome não-
  // "none" a qualquer momento.
  const [transitionTargetId, setTransitionTargetId] = useState<string | null>(null);

  const selectedCardSet = cardSets.find((set) => set.code === selectedCode) ?? null;

  /**
   * Hierarquia de filtros Jogo → Expansão → Coleção — ampliada em
   * 2026-07-31 (pedido de Fabrício: "vamos incluir um terceiro componente
   * separado com o filtro de jogo... respeitando a hierarquia").
   * `selectedGameId`/`selectedExpansionId` chegam prontos como prop,
   * resolvidos em `page.tsx` a partir de `set`/`expansion`/`game` na URL —
   * não são mais derivados só do Card Set selecionado.
   *
   * Isso mudou depois de um bug relatado por Fabrício: "o primeiro
   * componente não exibe todos os jogos cadastrados". A primeira versão
   * montava `gameOptions`/`expansionOptions` a partir de `cardSets`, então
   * um Jogo ou Expansão recém-cadastrado sem nenhum Card Set ainda ficava
   * invisível nos dois seletores — e, se `selectedGameId` continuasse
   * sendo só `selectedCardSet?.gameId`, nunca haveria como esse estado
   * "Jogo escolhido, mas sem nenhum Card Set" existir de fato (não haveria
   * Card Set nenhum para derivar o Jogo dele). Agora `games`/`expansions`
   * vêm de `getGameOptions()`/`getExpansoes()` (todo o cadastro, não só o
   * que já tem cartas), e a página resolve/preserva o Jogo/Expansão
   * escolhidos mesmo quando o resultado é "nenhum Card Set neste escopo
   * ainda" — ver `!selectedCardSet` mais abaixo para o estado vazio
   * correspondente. "Selecionar Todos" continua sendo um comando de
   * navegação, não um estado que gruda: escolher "Todos" em Jogo/Expansão
   * navega para o Card Set mais recente do escopo resultante quando existe
   * um; Card Set (terceiro nível) não ganha "Todos" funcional, por decisão
   * explícita de Fabrício — é ele quem decide quais cartas a tela busca.
   */
  const gameOptions = games;

  // Opções do seletor "Expansão" — restritas ao Jogo selecionado (se algum
  // estiver escolhido; "Selecionar Todos" em Jogo libera todas). O nome do
  // Jogo não aparece mais no rótulo da opção (pedido de Fabrício: "não é
  // preciso incluir o nome do Jogo" nesse seletor) — agora que existe um
  // seletor de Jogo dedicado, repetir o nome aqui é redundante.
  const expansionOptions = useMemo(
    () => expansions.filter((expansion) => !selectedGameId || expansion.gameId === selectedGameId),
    [expansions, selectedGameId],
  );

  // Opções do seletor "Coleção" — restritas à Expansão selecionada; sem
  // Expansão escolhida ("Todos"), restritas ao Jogo; sem nenhum dos dois,
  // todos os Card Sets. "Coleção" continua sem opção "Todos" — é o nível
  // que efetivamente decide quais cartas a tela busca.
  const cardSetsInScope = useMemo(() => {
    return cardSets.filter((set) => {
      if (selectedExpansionId) return set.expansionId === selectedExpansionId;
      if (selectedGameId) return set.gameId === selectedGameId;
      return true;
    });
  }, [cardSets, selectedGameId, selectedExpansionId]);

  /**
   * Navega para o Card Set mais recente dentro do escopo (Jogo e/ou
   * Expansão) informado — `cardSets` já chega ordenado "mais recentes
   * primeiro", então o primeiro que sobra do filtro é o alvo. Quando o
   * escopo não tem NENHUM Card Set ainda (Jogo/Expansão recém-cadastrados),
   * navega mesmo assim — para `?expansion=`/`?game=` explícitos, em vez de
   * `?set=` — preservando a escolha do usuário e mostrando o estado vazio
   * correspondente, em vez de silenciosamente cair de volta no catálogo
   * inteiro.
   */
  function navigateToMostRecentInScope(gameId: string, expansionId: string) {
    const target = cardSets.find((set) => {
      if (expansionId) return set.expansionId === expansionId;
      if (gameId) return set.gameId === gameId;
      return true;
    });
    if (target) {
      router.push(`/catalogo/cartas?set=${target.code}`);
    } else if (expansionId) {
      router.push(`/catalogo/cartas?expansion=${expansionId}`);
    } else if (gameId) {
      router.push(`/catalogo/cartas?game=${gameId}`);
    } else {
      router.push("/catalogo/cartas");
    }
  }

  function handleGameChange(gameId: string) {
    // Trocar de Jogo reseta a Expansão junto (hierarquia: uma Expansão do
    // Jogo anterior pode nem existir no novo).
    navigateToMostRecentInScope(gameId, "");
  }

  function handleExpansionChange(expansionId: string) {
    navigateToMostRecentInScope(selectedGameId, expansionId);
  }

  const rarityOptions = useMemo(() => {
    const map = new Map<string, { code: string; name: string; order: number; count: number }>();
    for (const carta of cartas) {
      if (!carta.rarityCode) continue;
      const entry = map.get(carta.rarityCode) ?? {
        code: carta.rarityCode,
        name: carta.rarityName,
        order: carta.rarityDisplayOrder,
        count: 0,
      };
      entry.count += 1;
      map.set(carta.rarityCode, entry);
    }
    return Array.from(map.values()).sort((a, b) => a.order - b.order);
  }, [cartas]);

  const categoryOptions = useMemo(() => {
    const map = new Map<string, { code: string; name: string; order: number; count: number }>();
    for (const carta of cartas) {
      if (!carta.categoryCode) continue;
      const entry = map.get(carta.categoryCode) ?? {
        code: carta.categoryCode,
        name: carta.categoryName,
        order: carta.categoryDisplayOrder,
        count: 0,
      };
      entry.count += 1;
      map.set(carta.categoryCode, entry);
    }
    return Array.from(map.values()).sort((a, b) => a.order - b.order);
  }, [cartas]);

  // O alternador PT/EN só faz sentido quando o Card Set de fato tem os dois
  // idiomas importados — mostrá-lo sempre, mesmo quando só um idioma existe,
  // criaria um controle que não muda nada visualmente (pedido de Fabrício
  // não previu esse caso, mas segue o mesmo cuidado já aplicado ao filtro de
  // raridade/categoria, que também só aparece quando há opções).
  const hasBothImageLanguages = useMemo(
    () => cartas.some((carta) => carta.imageUrlPt) && cartas.some((carta) => carta.imageUrlEn),
    [cartas],
  );

  const query = search.trim().toLowerCase();
  const filtered = useMemo(() => {
    return cartas.filter((carta) => {
      if (selectedRarities.size > 0 && !selectedRarities.has(carta.rarityCode)) return false;
      if (selectedCategories.size > 0 && !selectedCategories.has(carta.categoryCode)) return false;
      if (query) {
        const matchesName = carta.name.toLowerCase().includes(query);
        // Busca por número — bug reportado por Fabrício (2026-07-31, print
        // de "001/086" sem resultado): comparava só `collectorNumber`
        // ("001"), nunca o texto completo exibido ("001/086" — ver
        // `formatCollectorTotal`, revisão `1.6`). `cartaFullNumber` monta o
        // mesmo texto mostrado em `CartaGridCard`, então buscar pelo número
        // isolado ("001"), pelo total isolado ("086") ou pelo par completo
        // ("001/086") funciona igual.
        const matchesNumber = cartaFullNumber(carta).toLowerCase().includes(query);
        if (!matchesName && !matchesNumber) return false;
      }
      return true;
    });
  }, [cartas, selectedRarities, selectedCategories, query]);

  const visible = showAll ? filtered : filtered.slice(0, PAGE_SIZE);

  function openZoom(carta: CartaCompletaRow) {
    // Passo de preparo, fora da transição: marca só esta carta como alvo
    // ANTES de capturar o snapshot "antigo" — sem isso, a miniatura do grid
    // ainda estaria sem nome no instante em que `startViewTransition` olha
    // o DOM, e não haveria nada para o navegador morfar.
    flushSync(() => setTransitionTargetId(carta.id));
    runWithViewTransition(() => setZoomCarta(carta));
  }

  function closeZoom() {
    runWithViewTransition(() => setZoomCarta(null));
    // A miniatura do grid já reclama o nome de volta no snapshot "novo"
    // (ver `isTransitionSource` em `CartaGridCard`) assim que `zoomCarta`
    // vira `null` — este reset só limpa o estado depois que a transição já
    // capturou os dois snapshots, sem efeito visual (view-transition-name
    // não faz nada fora de uma transição em andamento).
    setTransitionTargetId(null);
  }

  function toggleRarity(code: string) {
    setSelectedRarities((prev) => {
      const next = new Set(prev);
      if (next.has(code)) next.delete(code);
      else next.add(code);
      return next;
    });
  }

  function toggleCategory(code: string) {
    setSelectedCategories((prev) => {
      const next = new Set(prev);
      if (next.has(code)) next.delete(code);
      else next.add(code);
      return next;
    });
  }

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <div className="flex items-center gap-2">
            <CreditCard className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
            <PageTitle>Cartas</PageTitle>
          </div>
          <PageDescription>Explore as cartas catalogadas, Card Set por Card Set.</PageDescription>
        </PageHeading>
      </PageHeader>

      {cardSets.length > 0 && <CartasStats cardSets={cardSets} stats={cartasStats} />}

      {cardSets.length === 0 ? (
        <Card density="compact">
          <CardContent density="compact" className="pt-4">
            <EmptyState
              title="Nenhuma Coleção cadastrada ainda"
              description="Cadastre um Card Set em /catalogo/card-sets para começar a catalogar cartas."
            />
          </CardContent>
        </Card>
      ) : (
        <Card density="compact" className="overflow-hidden">
          <div className="space-y-3 border-b border-border p-4">
            <div className="flex items-center gap-2">
              <div className="relative min-w-0 flex-1">
                <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <Input
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder="Buscar por nome ou número da carta…"
                  className="h-9 bg-surface-muted pl-9 text-xs"
                  aria-label="Buscar carta"
                />
              </div>
              <select
                value={selectedGameId}
                onChange={(event) => handleGameChange(event.target.value)}
                className="h-9 shrink-0 rounded-md border border-border bg-surface-muted px-3 text-xs text-foreground"
                aria-label="Filtrar por Jogo"
              >
                <option value="">Selecionar Todos</option>
                {gameOptions.map((game) => (
                  <option key={game.id} value={game.id}>
                    {game.name}
                  </option>
                ))}
              </select>
              <select
                value={selectedExpansionId}
                onChange={(event) => handleExpansionChange(event.target.value)}
                className="h-9 shrink-0 rounded-md border border-border bg-surface-muted px-3 text-xs text-foreground"
                aria-label="Filtrar por Expansão"
              >
                <option value="">Selecionar Todos</option>
                {expansionOptions.map((expansion) => (
                  <option key={expansion.id} value={expansion.id}>
                    {expansion.name}
                  </option>
                ))}
              </select>
              <select
                value={selectedCode ?? ""}
                onChange={(event) => router.push(`/catalogo/cartas?set=${event.target.value}`)}
                className="h-9 shrink-0 rounded-md border border-border bg-surface-muted px-3 text-xs text-foreground"
                aria-label="Filtrar por Coleção"
              >
                {cardSetsInScope.map((set) => (
                  <option key={set.code} value={set.code}>
                    {set.name} ({set.code})
                  </option>
                ))}
              </select>
            </div>

            {(rarityOptions.length > 0 || categoryOptions.length > 0) && (
              // Esquema pedido por Fabrício (2026-07-31, ajuste seguinte):
              // "RARIDADE / chips / (12px) / CATEGORIA / chips" — rótulo
              // volta a ficar em linha própria acima dos chips (dentro de
              // cada `FilterGroup`); o espaçamento entre os dois grupos foi
              // ajustado de 12px para 16px logo em seguida (`space-y-4` =
              // 1rem).
              <div className="space-y-4">
                <FilterGroup label="Raridade" options={rarityOptions} selected={selectedRarities} onToggle={toggleRarity} />
                <FilterGroup label="Categoria" options={categoryOptions} selected={selectedCategories} onToggle={toggleCategory} />
              </div>
            )}
          </div>

          <CardContent density="compact" className="pt-4">
            {!selectedCardSet ? (
              // Jogo/Expansão escolhidos ainda não têm nenhum Card Set
              // cadastrado (`navigateToMostRecentInScope` não achou alvo e
              // navegou para `?game=`/`?expansion=` mesmo assim) — estado
              // diferente de "Card Set existe, mas está vazio", abaixo.
              <EmptyState
                title="Nenhuma Coleção cadastrada neste escopo"
                description="Ajuste o filtro de Jogo/Expansão ou cadastre um Card Set em /catalogo/card-sets."
              />
            ) : cartas.length === 0 ? (
              <EmptyState
                title="Nenhuma carta catalogada neste Card Set"
                description={`${selectedCardSet.name} ainda não tem cartas cadastradas.`}
              />
            ) : filtered.length === 0 ? (
              <EmptyState title="Nenhuma carta encontrada" description="Ajuste a busca ou os filtros de raridade/categoria." />
            ) : (
              <div className="space-y-4">
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div className="flex items-start gap-3">
                    {/* Logo do Card Set selecionado, à esquerda do bloco
                        de informações — pedido de Fabrício (2026-07-31),
                        teste do bloco de cabeçalho recém-criado. 36px →
                        56px → 70px ao longo da mesma rodada de testes
                        ("a logo ficou muito pequena. Vamos ampliar." duas
                        vezes seguidas) — protagonista ao lado do nome da
                        Coleção, não mais do tamanho de miniatura de
                        `CardSetChip`.

                        Ajuste seguinte, mesmo dia: "o fundo da logo deve
                        ser transparente... vamos controlar apenas a
                        altura que deve ter 70px" — a caixa quadrada
                        (`w-[70px]`, `bg-surface-muted`, `rounded-md`,
                        padding) fazia sentido para o fallback de iniciais
                        (que precisa de alguma área para centralizar o
                        texto), mas distorcia/emolduava a logo real sem
                        necessidade. Sem logo cadastrada, mantém a caixa
                        70×70 com fundo e iniciais (mesmo fallback de
                        `CardSetChip`/`getInitials`) — o pedido foi sobre "a
                        logo", não sobre o placeholder de iniciais.

                        Terceiro ajuste, mesmo dia: "a largura máxima
                        permitida para a logo é 250px. Vamos limitar a
                        altura a 70px ou largura de 250px... sem exceder
                        esses limites... não deve ser redimensionada em
                        hipótese alguma" — `h-[70px] w-auto` sozinho não
                        tinha teto de largura (uma logo bem larga/baixa
                        podia esticar horizontalmente sem limite). Trocado
                        para `max-h-[70px] max-w-[250px] h-auto w-auto`:
                        nenhuma dimensão é forçada, a imagem renderiza no
                        tamanho original até esbarrar num dos dois tetos —
                        o primeiro a ser atingido manda, e a proporção
                        original é sempre preservada (comportamento nativo
                        do navegador para `max-*` com `auto`/`auto`, sem
                        precisar de `object-fit` para evitar distorção,
                        já que não há caixa de dimensões fixas para a
                        imagem "encaixar" — mantido `object-contain` só
                        como reforço defensivo). */}
                    {selectedLogoUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={selectedLogoUrl}
                        alt=""
                        className="h-auto max-h-[70px] w-auto max-w-[250px] shrink-0 object-contain"
                      />
                    ) : (
                      <div className="flex h-[70px] w-[70px] shrink-0 items-center justify-center rounded-md bg-surface-muted">
                        <span className="text-base font-medium text-muted-foreground">
                          {getInitials(selectedCardSet.name)}
                        </span>
                      </div>
                    )}
                    <div className="min-w-0 space-y-1.5">
                      <p className="truncate text-base font-semibold text-foreground sm:text-lg">
                        {selectedCardSet.code} - {selectedCardSet.name}
                      </p>
                      <div className="flex flex-wrap items-center gap-x-2.5 gap-y-1">
                        <SetTypeTag setType={selectedCardSet.setType} />
                        {selectedCardSet.releaseDate && (
                          <span className="text-[11px] text-muted-foreground">
                            Data de lançamento: {formatarData(selectedCardSet.releaseDate)}
                          </span>
                        )}
                      </div>
                      {/* Total do Card Set + contagem exibida/filtrada
                          unificados numa única linha — pedido de Fabrício
                          (2026-07-31, mesma rodada): "124 cartas (88 base +
                          36 secretas) - Exibidas 124 de 124 cartas". Antes
                          eram duas linhas separadas (totais do Set acima,
                          contagem de busca/filtro abaixo). */}
                      <p className="text-[11px] text-muted-foreground">
                        {formatCardSetTotals(selectedCardSet.baseSetSize, selectedCardSet.totalSetSize)} - Exibidas{" "}
                        {filtered.length} de {cartas.length} carta{cartas.length === 1 ? "" : "s"}
                      </p>
                    </div>
                  </div>

                  {/* Alternador de idioma da imagem — pedido de Fabrício
                      (2026-07-31, mesma rodada): "do lado oposto das
                      informações da coleção, incluir um componente para
                      alternar entre imagens das cartas em PT e IN".
                      `justify-between` no contêiner pai empurra este bloco
                      para a direita; `flex-wrap` evita overflow em telas
                      estreitas (cai para a linha de baixo). Só aparece
                      quando o Card Set de fato tem os dois idiomas
                      importados. */}
                  {hasBothImageLanguages && (
                    <ImageLanguageToggle value={imageLanguage} onChange={setImageLanguage} />
                  )}
                </div>

                <div className="grid grid-cols-3 gap-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 xl:grid-cols-7">
                  {visible.map((carta) => (
                    <CartaGridCard
                      key={carta.id}
                      carta={carta}
                      imageLanguage={imageLanguage}
                      isTransitionSource={transitionTargetId === carta.id && zoomCarta?.id !== carta.id}
                      onOpen={() => openZoom(carta)}
                    />
                  ))}
                </div>

                {!showAll && filtered.length > PAGE_SIZE && (
                  <div className="flex justify-center pt-1">
                    <Button type="button" variant="outline" size="sm" onClick={() => setShowAll(true)}>
                      Ver todas ({filtered.length})
                    </Button>
                  </div>
                )}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      <CartaZoomDialog carta={zoomCarta} imageLanguage={imageLanguage} onClose={closeZoom} />
    </div>
  );
}

/**
 * Alternador PT/EN — segmented control compacto, mesmo padrão visual dos
 * outros controles pequenos da tela (`bg-surface-muted`/`border-border`).
 * Pedido de Fabrício (2026-07-31): "um componente para alternar entre
 * imagens das cartas em PT e IN". Controla só a imagem exibida (grid +
 * modal de zoom) — não afeta nome/número/raridade, que já vêm de uma única
 * fonte independente de idioma.
 */
function ImageLanguageToggle({
  value,
  onChange,
}: {
  value: ImageLanguage;
  onChange: (language: ImageLanguage) => void;
}) {
  const options: { code: ImageLanguage; label: string }[] = [
    { code: "pt-BR", label: "PT" },
    { code: "en", label: "EN" },
  ];

  return (
    <div
      className="flex shrink-0 items-center gap-0.5 rounded-md border border-border bg-surface-muted p-0.5"
      role="group"
      aria-label="Idioma da imagem da carta"
    >
      {options.map((option) => (
        <button
          key={option.code}
          type="button"
          onClick={() => onChange(option.code)}
          aria-pressed={value === option.code}
          className={cn(
            "rounded-[5px] px-2.5 py-1 text-[11px] font-medium transition-colors",
            value === option.code
              ? "bg-surface text-foreground shadow-sm"
              : "text-muted-foreground hover:text-foreground",
          )}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

/**
 * Chips de filtro multi-seleção — pedido de Fabrício (2026-07-31): os
 * checkboxes de Raridade/Categoria "ainda estão com aparência de formulário
 * HTML... destoam da linguagem visual do restante do Catálogo". Mesmo
 * padrão visual de `Chip` em `catalogo-filter-chips.tsx` (filtro de Jogo/
 * Expansão): `rounded-full border px-3 py-1 text-xs font-medium`, ativo
 * `border-primary/40 bg-primary/5 text-primary`, inativo `border-border
 * text-muted-foreground hover:bg-surface-muted hover:text-foreground`.
 * Diferença deliberada: lá são `Link` de seleção única (navegação de rota,
 * faceta hierárquica); aqui são `<button>` com `aria-pressed`, multi-seleção
 * via `Set` local — mesma lógica/estado de antes (`toggleRarity`/
 * `toggleCategory`, `selectedRarities`/`selectedCategories`), só a marcação
 * visual mudou. Contagem embutida no rótulo do chip ("Comum (43)"), pedido
 * explícito.
 *
 * Rótulo do grupo (`label`) — ajustado em 2026-07-31 (rodada seguinte,
 * mesmo dia): esquema pedido por Fabrício, "RARIDADE / chips / (12px) /
 * CATEGORIA / chips" — rótulo em linha própria acima dos chips (não mais
 * inline ao lado, como na primeira versão desta troca). Espaçamento entre
 * os dois grupos ajustado de 12px para 16px logo em seguida, mesmo dia
 * (`space-y-4` no contêiner pai).
 */
function FilterGroup({
  label,
  options,
  selected,
  onToggle,
}: {
  label: string;
  options: { code: string; name: string; count: number }[];
  selected: Set<string>;
  onToggle: (code: string) => void;
}) {
  if (options.length === 0) return null;

  return (
    <div className="space-y-1.5">
      <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <div className="flex flex-wrap gap-1.5">
        {options.map((option) => {
          const active = selected.has(option.code);
          return (
            <button
              key={option.code}
              type="button"
              onClick={() => onToggle(option.code)}
              aria-pressed={active}
              className={cn(
                "inline-flex shrink-0 items-center whitespace-nowrap rounded-full border px-3 py-1 text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
                active
                  ? "border-primary/40 bg-primary/5 text-primary"
                  : "border-border text-muted-foreground hover:bg-surface-muted hover:text-foreground",
              )}
            >
              {option.name} ({option.count})
            </button>
          );
        })}
      </div>
    </div>
  );
}

function CartaGridCard({
  carta,
  imageLanguage,
  isTransitionSource,
  onOpen,
}: {
  carta: CartaCompletaRow;
  /** Qual imagem mostrar — ver `ImageLanguageToggle`/`cartaImageUrl`. */
  imageLanguage: ImageLanguage;
  /**
   * `true` só para a única carta, entre todas as do grid, que está
   * emprestando seu `viewTransitionName` para o morph em andamento (logo
   * antes de abrir, ou logo depois de fechar o modal). Todas as demais
   * ficam permanentemente com `"none"` — dar o nome a todas ao mesmo tempo
   * foi o bug corrigido em 2026-07-31 (a carta clicada ficava atrás das
   * vizinhas durante o movimento, porque o navegador "hoista" toda carta
   * nomeada para a árvore de pseudo-elementos da transição, não só a que
   * está de fato animando).
   */
  isTransitionSource: boolean;
  onOpen: () => void;
}) {
  const imageUrl = cartaImageUrl(carta, imageLanguage);

  return (
    <button
      type="button"
      onClick={onOpen}
      // `gap-2.5` (em vez de `gap-1.5`) — pedido de Fabrício (2026-07-31,
      // print da carta "001/086" com o mouse sobre a imagem): o
      // `scale3d(1.045, ...)` do hover holográfico (`HoloCard`) não afeta o
      // layout (é só `transform`, não reflui os irmãos), então a carta
      // cresce visualmente por cima do respiro entre ela e a identificação
      // — com `gap-1.5` a distância ficava quase zero no hover. Não mexe no
      // espaço entre a identificação e o símbolo (revisões `1.8`/`1.9`,
      // já no mínimo prático).
      className="group flex flex-col gap-2.5 rounded-lg text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      aria-label={`Ampliar ${carta.name}`}
    >
      <HoloCard
        style={
          { viewTransitionName: isTransitionSource ? cartaViewTransitionName(carta.id) : "none" } as CSSProperties
        }
      >
        {imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={imageUrl} alt={carta.name} loading="lazy" decoding="async" className="w-full rounded-lg" />
        ) : (
          <div className="flex aspect-[5/7] w-full items-center justify-center rounded-lg border border-dashed border-border bg-surface-muted p-2 text-center text-[10px] text-muted-foreground">
            Sem imagem
          </div>
        )}
      </HoloCard>
      <div className="space-y-0 px-0.5 text-left">
        <p className="truncate text-[10px] leading-none text-muted-foreground">
          <span className="font-medium text-foreground">#{cartaFullNumber(carta)}</span> - {carta.name}
        </p>
        <RaritySymbol symbolCode={carta.raritySymbolCode} />
      </div>
    </button>
  );
}

/**
 * Modal de ampliação — reduzido a só a imagem em 2026-07-31 (pedido
 * explícito de Fabrício, com print da referência oficial ao lado do nosso
 * resultado: "só quero enxergar a imagem da carta. Não preciso de nenhuma
 * outra informação. É um modo onde o foco está única e exclusivamente na
 * carta"). Removidos: `DialogHeader`/título/número/categoria visíveis,
 * linha de raridade abaixo da carta, botão de fechar (`hideClose`) e todo o
 * "chrome" do Dialog (fundo/borda/sombra do painel, via override de
 * classes) — só o `HoloCard` com a imagem, flutuando sobre o overlay
 * escurecido. Fecha por clique fora ou Esc (comportamento padrão do
 * `Dialog`, preservado). `DialogTitle` continua presente para leitores de
 * tela (`sr-only`, nunca visível) — Radix exige um nome acessível no
 * `Dialog.Content`; omiti-lo seria trocar "sem informação visível" por
 * "sem informação nenhuma", que não foi o pedido.
 *
 * Transição de abertura/fechamento reescrita em 2026-07-31 (mesmo dia,
 * pedido seguinte de Fabrício: "quero que o movimento pareça realmente uma
 * ampliação da carta", rejeitando o zoom+fade genérico que só salta para o
 * tamanho final). `animated={false}` desliga esse zoom+fade padrão do
 * `DialogContent` quando a View Transitions API está disponível — o
 * navegador já faz o morph de verdade (a miniatura do grid cresce até virar a imagem
 * ampliada) via `viewTransitionName` compartilhado com `CartaGridCard`
 * (`cartaViewTransitionName`), disparado por `openZoom`/`closeZoom` no
 * componente pai. Sem suporte (ou `prefers-reduced-motion: reduce`),
 * `animated` volta a `true` — o Dialog usa seu zoom+fade de sempre, ainda
 * curto o bastante para não incomodar.
 */
function CartaZoomDialog({
  carta,
  imageLanguage,
  onClose,
}: {
  carta: CartaCompletaRow | null;
  /** Qual imagem mostrar — ver `ImageLanguageToggle`/`cartaImageUrl`. */
  imageLanguage: ImageLanguage;
  onClose: () => void;
}) {
  const usingViewTransition = canUseViewTransitions();
  const imageUrl = carta ? cartaImageUrl(carta, imageLanguage) : null;

  return (
    <Dialog open={carta !== null} onOpenChange={(next) => !next && onClose()}>
      <DialogContent
        hideClose
        animated={!usingViewTransition}
        aria-describedby={undefined}
        className="w-full max-w-[380px] border-none bg-transparent p-0 shadow-none sm:max-w-[460px]"
      >
        <DialogTitle className="sr-only">{carta?.name ?? "Carta ampliada"}</DialogTitle>
        {carta && (
          <HoloCard
            floating
            className="drop-shadow-[0_25px_50px_-12px_hsl(var(--foreground)/0.55)]"
            style={{ viewTransitionName: cartaViewTransitionName(carta.id) } as CSSProperties}
          >
            {imageUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={imageUrl} alt={carta.name} className="w-full rounded-lg" />
            ) : (
              <div className="flex aspect-[5/7] w-full items-center justify-center rounded-lg border border-dashed border-border bg-surface-muted text-xs text-muted-foreground">
                Sem imagem
              </div>
            )}
          </HoloCard>
        )}
      </DialogContent>
    </Dialog>
  );
}
