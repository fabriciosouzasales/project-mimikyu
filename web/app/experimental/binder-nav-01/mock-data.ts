import type { MockCardData } from "@/components/experimental/binder-spike/mock-card-face";

/**
 * Dados mockados do BINDER-NAV-01 (pedido de Fabrício, 2026-08-28 —
 * baseline de navegação operacional; ajustado na Rodada 2, mesma data, para
 * refletir a estrutura física real de abertura).
 *
 * Rodada 2 — mudança de modelo: o Binder não abre mais direto em duas
 * páginas de bolsos. Segundo a referência física enviada (fotos de binders
 * reais com zíper), a abertura inicial mostra a CONTRACAPA INTERNA (painel
 * liso, sem bolsos, mesma linguagem de material da capa) ao lado da
 * PRIMEIRA página de bolsos — só a partir da navegação seguinte é que
 * entram spreads normais de duas páginas de bolsos.
 *
 * Isso desloca o pareamento em uma página: em vez de 13 pares fixos
 * (pág.1+2, pág.3+4, ...), agora a posição 0 usa só a página 1 (pareada com
 * a contracapa interna) e as posições 1..12 pareiam (pág.2+3), (pág.4+5),
 * ..., (pág.24+25).
 *
 * Rodada 7 (2026-08-28, mesma data — pedido de Fabrício: "a última página
 * deve ter a mesma configuração da contracapa"): implementa o estado final
 * antes reservado e não implementado — a página 26 deixa de ficar de fora
 * da navegação e passa a formar a última posição junto com a CONTRACAPA
 * TRASEIRA (mesma configuração visual da contracapa interna frontal: sem
 * bolsos, `InsideCoverFace` — logo + rodapé). `SPREAD_COUNT` passa de 13
 * para 14; a nova posição 13 (última) mostra `[página 26] | [contracapa
 * traseira]`, espelhando a posição 0 (`[contracapa frontal] | [página 1]`).
 * `RightPanel` (novo, paralelo a `LeftPanel`) formaliza que o lado direito
 * também pode ser uma contracapa, não só uma página de bolsos.
 *
 * Teste ME2 (pedido de Fabrício, 2026-08-28, mesma data — "consegue fazer
 * um teste com imagens das cartas da coleção ME2?"): `BinderSlotData` e
 * `BinderPageData` deixaram de reimportar os tipos do `binder-spike`
 * compartilhado e passaram a ser definições LOCAIS (mesmo shape), porque o
 * campo `card` agora aceita tanto a carta fictícia (`MockCardData`, ainda
 * usada em Binder-First/BINDER-VIS-02) quanto uma carta REAL (`RealCardData`
 * — artwork do Card Set ME2 "Fogo Fantasmagórico", lido do Supabase:
 * `card`/`card_asset`, bucket público `card-front`, idioma pt-BR). Isso não
 * toca em nenhum arquivo de `binder-spike/` — é só o BINDER-NAV-01 usando
 * seus próprios tipos locais, já que ele nunca compartilhou o array de dados
 * com o spike original (só a FORMA do tipo). `card()` abaixo agora devolve
 * `RealCardData`, ciclando 18 cartas reais (dois blocos de 9, coletor
 * 001-018) pelos 224 bolsos — mesmo padrão de repetição por módulo que os 8
 * mocks fictícios já usavam. `MockCardData`/`MOCK_CARDS` ficam mantidos,
 * sem uso nesta rodada, para reverter o teste com um diff mínimo se
 * Fabrício preferir voltar às cartas fictícias.
 *
 * BINDER-ADD-REPLACE-CARD-01 (2026-08-29) — primeiro fluxo funcional de
 * Adicionar/Substituir carta (pedido de Fabrício: "retomar implementação
 * funcional" depois do encerramento da frente visual da Collection Library).
 * `ME2_CARDS` passou a ser EXPORTADO — é o mesmo pool reaproveitado pelo
 * Card Picker (`card-picker-mock.ts`), evitando uma segunda lista paralela
 * de cartas. A antiga `getNextReplacementCard()` (ciclava automaticamente
 * para a "próxima" carta ao clicar "Substituir", sem escolha do usuário) foi
 * REMOVIDA — substituir carta agora abre o mesmo Card Picker do fluxo de
 * adicionar, em modo substituição, e a carta escolhida é quem decide o
 * resultado (ver `binder-pages-nav.tsx`, `handleSelectPickerCard`).
 */

export interface RealCardData {
  id: string;
  name: string;
  imageUrl: string;
}

export interface BinderSlotData {
  id: string;
  filled: boolean;
  card?: MockCardData | RealCardData;
}

export interface BinderPageData {
  id: string;
  pageNumber: number;
  slots: BinderSlotData[];
}

const CARD_FRONT_BASE = "https://qjfutqujxrbzgrtkpgkg.supabase.co/storage/v1/object/public/card-front";

/** Mantido para reverter o teste ME2 com facilidade — não usado nesta rodada. */
const MOCK_CARDS: MockCardData[] = [
  { id: "emberling", name: "Emberling", hp: 60, hue: 12, attack: "Ember Burst", damage: 30, rarity: "N", energy: "flame" },
  { id: "aquafin", name: "Aquafin", hp: 70, hue: 205, attack: "Aqua Jet", damage: 40, rarity: "RH", energy: "drop" },
  { id: "verdil", name: "Verdil", hp: 80, hue: 140, attack: "Vine Snap", damage: 20, rarity: "N", energy: "leaf" },
  { id: "stonepaw", name: "Stonepaw", hp: 90, hue: 32, attack: "Rock Slam", damage: 50, rarity: "N", energy: "stone" },
  { id: "voltgnat", name: "Voltgnat", hp: 50, hue: 48, attack: "Static Shock", damage: 30, rarity: "H", energy: "bolt" },
  { id: "skyfeather", name: "Skyfeather", hp: 65, hue: 260, attack: "Gale Wing", damage: 20, rarity: "RH", energy: "wing" },
  { id: "cindrix", name: "Cindrix", hp: 100, hue: 350, attack: "Cinder Roar", damage: 60, rarity: "H", energy: "flame" },
  { id: "mossback", name: "Mossback", hp: 75, hue: 160, attack: "Bramble Guard", damage: 10, rarity: "N", energy: "leaf" },
];
void MOCK_CARDS;

/**
 * 18 cartas reais do Card Set ME2 "Fogo Fantasmagórico" (coletor 001-018,
 * pt-BR). Exportado desde BINDER-ADD-REPLACE-CARD-01 (2026-08-29) — é o
 * mesmo pool que já preenche os 224 bolsos do Binder (ciclado, ver `card()`
 * abaixo); o Card Picker (`card-picker-mock.ts`) reaproveita este array em
 * vez de duplicar uma segunda lista de cartas.
 */
export const ME2_CARDS: RealCardData[] = [
  { id: "me2-001", name: "Oddish", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/001.webp` },
  { id: "me2-002", name: "Gloom", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/002.webp` },
  { id: "me2-003", name: "Vileplume", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/003.webp` },
  { id: "me2-004", name: "Mega Heracross ex", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/004.webp` },
  { id: "me2-005", name: "Lotad", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/005.webp` },
  { id: "me2-006", name: "Lombre", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/006.webp` },
  { id: "me2-007", name: "Ludicolo", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/007.webp` },
  { id: "me2-008", name: "Genesect", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/008.webp` },
  { id: "me2-009", name: "Nymble", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/009.webp` },
  { id: "me2-010", name: "Lokix", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/010.webp` },
  { id: "me2-011", name: "Charmander", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/011.webp` },
  { id: "me2-012", name: "Charmeleon", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/012.webp` },
  { id: "me2-013", name: "Mega Charizard X ex", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/013.webp` },
  { id: "me2-014", name: "Moltres", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/014.webp` },
  { id: "me2-015", name: "Darumaka", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/015.webp` },
  { id: "me2-016", name: "Darmanitan", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/016.webp` },
  { id: "me2-017", name: "Reshiram", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/017.webp` },
  { id: "me2-018", name: "Oricorio ex", imageUrl: `${CARD_FRONT_BASE}/me2/pt-BR/018.webp` },
];

const SLOTS_PER_PAGE = 9;
const TOTAL_PAGES = 26; // 13 spreads físicos originais × 2 — ver nota acima sobre a página 26.
const TOTAL_CARDS = 224;

/** Número de POSIÇÕES navegáveis (0 = contracapa+pág.1 ; 1..12 = spreads normais ; 13 = pág.26+contracapa traseira). */
export const SPREAD_COUNT = 14;

function card(index: number): RealCardData {
  return ME2_CARDS[index % ME2_CARDS.length]!;
}

function buildPage(pageNumber: number, startCardIndex: number): BinderPageData {
  const id = `p${pageNumber}`;
  const slots: BinderSlotData[] = Array.from({ length: SLOTS_PER_PAGE }, (_, i) => {
    const cardIndex = startCardIndex + i;
    const filled = cardIndex < TOTAL_CARDS;
    return {
      id: `${id}-${i + 1}`,
      filled,
      card: filled ? card(cardIndex) : undefined,
    };
  });
  return { id, pageNumber, slots };
}

/** As 26 páginas de bolsos, geradas uma vez, na ordem física (1..26). */
const ALL_PAGES: BinderPageData[] = Array.from({ length: TOTAL_PAGES }, (_, i) =>
  buildPage(i + 1, i * SLOTS_PER_PAGE),
);

export type LeftPanel = { kind: "insideCover" } | { kind: "page"; page: BinderPageData };
export type RightPanel = { kind: "page"; page: BinderPageData } | { kind: "backCover" };

export interface PositionContent {
  left: LeftPanel;
  right: RightPanel;
}

/**
 * Conteúdo do spread na posição `position` (0-indexed, 0..SPREAD_COUNT-1).
 * Posição 0: contracapa interna frontal (sem bolsos) + página 1.
 * Posições 1..12: spreads normais de duas páginas de bolsos.
 * Posição 13 (última): página 26 + contracapa traseira (sem bolsos) — mesma
 * configuração visual da contracapa frontal, espelhando a posição 0.
 */
export function getPositionContent(position: number): PositionContent {
  if (position <= 0) {
    return { left: { kind: "insideCover" }, right: { kind: "page", page: ALL_PAGES[0]! } };
  }
  if (position >= SPREAD_COUNT - 1) {
    return { left: { kind: "page", page: ALL_PAGES[TOTAL_PAGES - 1]! }, right: { kind: "backCover" } };
  }
  const rightIndex = position * 2;
  const leftIndex = rightIndex - 1;
  return { left: { kind: "page", page: ALL_PAGES[leftIndex]! }, right: { kind: "page", page: ALL_PAGES[rightIndex]! } };
}
