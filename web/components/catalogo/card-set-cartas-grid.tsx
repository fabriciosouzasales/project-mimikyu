"use client";

import { Search } from "lucide-react";
import { useMemo, useState, type CSSProperties } from "react";
import { flushSync } from "react-dom";
import { HoloCard } from "@/components/catalogo/holo-card";
import { RaritySymbol } from "@/components/catalogo/rarity-symbol";
import { Dialog, DialogContent, DialogTitle } from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { Input } from "@/components/ui/input";
import { useInfiniteReveal } from "@/hooks/use-infinite-reveal";
import { cn } from "@/lib/utils";
import type { CartaCompletaRow } from "@/lib/catalogo/queries";

/** Tamanho de cada lote revelado por rolagem (`useInfiniteReveal`) — mesmo valor de `PAGE_SIZE` em `cartas-gallery.tsx`, mas a grade aqui é menor (ver `CardSetCartasGrid`), então cobre menos linhas; suficiente para não pesar o primeiro carregamento do hub, que já soma outras seções acima. */
const PAGE_SIZE = 24;

/** Mesma regra de `formatCollectorTotal`/`cartaFullNumber` em `cartas-gallery.tsx` — duplicada aqui (não importada) porque lá são funções internas não exportadas; o hub é um consumidor novo e independente, sem alterar a tela de Cartas. */
function cartaFullNumber(carta: Pick<CartaCompletaRow, "collectorNumber" | "collectorTotal">): string {
  return carta.collectorTotal
    ? `${carta.collectorNumber}/${String(carta.collectorTotal).padStart(3, "0")}`
    : carta.collectorNumber;
}

function cartaImageUrl(carta: CartaCompletaRow): string | null {
  return carta.imageUrlPt ?? carta.imageUrlEn;
}

/**
 * View Transitions API — mesmo mecanismo de `cartas-gallery.tsx`
 * (`canUseViewTransitions`/`runWithViewTransition`/`cartaViewTransitionName`),
 * duplicado aqui em vez de importado: são funções internas não exportadas
 * daquele arquivo, e este hub nunca está montado na mesma página que
 * `/catalogo/cartas` — não há risco de colisão de `viewTransitionName`
 * entre os dois. Pedido de Fabrício (2026-08-08): "ao clicar na imagem da
 * carta o comportamento deve ser o mesmo da tela Cartas. Imagem amplia com
 * movimento" — mesma miniatura-vira-imagem-ampliada, não um zoom+fade
 * genérico.
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

function cartaViewTransitionName(id: string): string {
  return `carta-img-${id}`;
}

/**
 * Grade de Cartas da Coleção — seção principal do hub de Card Set
 * (`/catalogo/card-sets/{code}`, escopo V1 aprovado por Fabrício em
 * 2026-08-08: "reutilizando a galeria existente"). Não é `CartasGallery`
 * embutida (aquele componente é a tela `/catalogo/cartas` inteira, com
 * cabeçalho próprio, seletor de Jogo/Expansão/Coleção — navegaria para fora
 * do contexto do hub — e dialogs de criação/edição/desativação, fora do
 * escopo aprovado para este incremento) — é uma grade nova, menor, somente
 * leitura, que reaproveita os mesmos blocos visuais de `CartaGridCard`
 * (efeito `HoloCard` no hover, símbolo de raridade, placeholder "Sem
 * imagem", badge "Inativa") em vez de reconstruir esses efeitos do zero.
 * Ações administrativas (editar, desativar/reativar, criar) continuam
 * exclusivas de `/catalogo/cartas`. Link "Ver em Cartas" removido em
 * 2026-08-08 (revisão de fechamento, pedido de Fabrício) — as ações
 * contextuais do hub (Importar Cartas/Imagens/Histórico) já cobrem a
 * navegação relevante a partir daqui.
 *
 * Zoom com View Transition (2026-08-08, mesmo dia, rodada seguinte) —
 * clicar na imagem amplia com o mesmo movimento de "miniatura crescendo até
 * virar a imagem ampliada" da tela Cartas, não um Dialog genérico. Modal
 * reduzido a só a imagem (`CartaZoomDialogReadOnly`), mesmo princípio do
 * `CartaZoomDialog` original.
 *
 * Sem alternador de idioma da imagem (PT/EN) nem toggle "Mostrar inativas"
 * — cartas inativas aparecem sempre (com a mesma badge), sem controle para
 * escondê-las; simplificação deliberada para não duplicar essa mecânica de
 * estado da tela completa neste incremento.
 *
 * Botão "Ver todas as N cartas" trocado por rolagem infinita (2026-08-09,
 * pedido de Fabrício após inspeção geral das páginas de Catálogo Editorial:
 * "carregar as cartas à medida que o usuário rola a tela para baixo") — ver
 * `useInfiniteReveal`.
 */
export function CardSetCartasGrid({ cartas }: { cartas: CartaCompletaRow[] }) {
  const [query, setQuery] = useState("");
  const [zoomCarta, setZoomCarta] = useState<CartaCompletaRow | null>(null);
  const [transitionTargetId, setTransitionTargetId] = useState<string | null>(null);

  const termo = query.trim().toLowerCase();
  const filtradas = useMemo(() => {
    if (!termo) return cartas;
    return cartas.filter(
      (carta) => carta.name.toLowerCase().includes(termo) || cartaFullNumber(carta).toLowerCase().includes(termo),
    );
  }, [cartas, termo]);

  const { visibleCount, sentinelRef } = useInfiniteReveal(PAGE_SIZE, termo);
  const visiveis = filtradas.slice(0, visibleCount);

  function openZoom(carta: CartaCompletaRow) {
    flushSync(() => setTransitionTargetId(carta.id));
    runWithViewTransition(() => setZoomCarta(carta));
  }

  function closeZoom() {
    runWithViewTransition(() => setZoomCarta(null));
    setTransitionTargetId(null);
  }

  return (
    <div className="space-y-3">
      <div className="relative w-full max-w-xs">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Buscar por nome ou número…"
          className="h-9 bg-surface-muted pl-9 text-xs"
          aria-label="Buscar carta"
        />
      </div>

      {cartas.length === 0 ? (
        <EmptyState
          title="Nenhuma carta cadastrada"
          description="Cartas desta Coleção aparecem aqui conforme forem catalogadas."
        />
      ) : filtradas.length === 0 ? (
        <EmptyState title={`Nenhum resultado para "${query}"`} description="Tente outro termo." />
      ) : (
        <>
          <div className="grid grid-cols-3 gap-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8">
            {visiveis.map((carta) => (
              <CartaGridCardReadOnly
                key={carta.id}
                carta={carta}
                isTransitionSource={transitionTargetId === carta.id && zoomCarta?.id !== carta.id}
                onOpen={() => openZoom(carta)}
              />
            ))}
          </div>
          {visibleCount < filtradas.length && <div ref={sentinelRef} aria-hidden="true" className="h-1 w-full" />}
        </>
      )}

      <CartaZoomDialogReadOnly carta={zoomCarta} onClose={closeZoom} />
    </div>
  );
}

/**
 * Versão somente-leitura de `CartaGridCard` (`cartas-gallery.tsx`) — mesmos
 * efeitos visuais pedidos por Fabrício ("mantenha os mesmos efeitos da
 * página cartas"): `HoloCard` (hover holográfico + agora também o morph de
 * ampliação), `RaritySymbol` e badge "Inativa". Sem botão de editar/
 * desativar — essas ações continuam só na tela `/catalogo/cartas`.
 */
function CartaGridCardReadOnly({
  carta,
  isTransitionSource,
  onOpen,
}: {
  carta: CartaCompletaRow;
  isTransitionSource: boolean;
  onOpen: () => void;
}) {
  const imageUrl = cartaImageUrl(carta);

  return (
    <div className="flex flex-col gap-1.5 rounded-lg text-left">
      <button
        type="button"
        onClick={onOpen}
        className="block w-full rounded-lg text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        aria-label={`Ampliar ${carta.name}`}
      >
        <HoloCard
          className={cn(!carta.isActive && "opacity-50 grayscale")}
          style={
            { viewTransitionName: isTransitionSource ? cartaViewTransitionName(carta.id) : "none" } as CSSProperties
          }
        >
          {imageUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={imageUrl} alt={carta.name} loading="lazy" decoding="async" className="w-full rounded-lg" />
          ) : (
            <div className="flex aspect-[5/7] w-full items-center justify-center rounded-lg border border-dashed border-border bg-surface-muted p-2 text-center text-[9px] text-muted-foreground">
              Sem imagem
            </div>
          )}
        </HoloCard>
      </button>
      <div className="space-y-0.5 px-0.5">
        <p className="truncate text-[9px] leading-none text-muted-foreground">
          <span className="font-medium text-foreground">#{cartaFullNumber(carta)}</span> - {carta.name}
        </p>
        <div className="flex items-center gap-1">
          <RaritySymbol symbolCode={carta.raritySymbolCode} />
          {!carta.isActive && (
            <span className="rounded-full bg-surface-muted px-1.5 py-0.5 text-[8px] font-medium leading-none text-muted-foreground">
              Inativa
            </span>
          )}
        </div>
      </div>
    </div>
  );
}

/**
 * Modal de ampliação somente-leitura — mesmo princípio do `CartaZoomDialog`
 * original (`cartas-gallery.tsx`): só a imagem, sem "chrome" do Dialog
 * (fundo/borda/sombra removidos via override de classes), `animated={false}`
 * quando a View Transition está disponível (o navegador já faz o morph via
 * `viewTransitionName` compartilhado com `CartaGridCardReadOnly`).
 */
function CartaZoomDialogReadOnly({ carta, onClose }: { carta: CartaCompletaRow | null; onClose: () => void }) {
  const usingViewTransition = canUseViewTransitions();
  const imageUrl = carta ? cartaImageUrl(carta) : null;

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
