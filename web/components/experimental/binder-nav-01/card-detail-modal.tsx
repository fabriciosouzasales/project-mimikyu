"use client";

import { BookOpen, Copy, Heart, Layers, MapPin, X } from "lucide-react";
import type { KeyboardEvent, PointerEvent, ReactNode } from "react";
import { useCallback, useEffect, useRef } from "react";
import { BINDER_NAME } from "@/app/experimental/binder-spike/mock-data";
import type { MockCardData } from "@/components/experimental/binder-spike/mock-card-face";
import { MockCardFace } from "@/components/experimental/binder-spike/mock-card-face";
import type { RealCardData } from "@/app/experimental/binder-nav-01/mock-data";
import { getCardCopiesOwnedMock, getCardPricingMock, getCardSetInfoMock } from "@/app/experimental/binder-nav-01/card-detail-mock";
import { cn } from "@/lib/utils";
import { RealCardFace } from "./real-card-face";

/**
 * CARD-DETAIL-01 (2026-08-29) — painel de detalhes da carta, aberto ao
 * clicar diretamente na carta dentro de um slot ocupado do Binder (pedido de
 * Fabrício: "Binder = contexto de organização; Card Detail = contexto de
 * informação da carta"). Overlay premium sobre o Binder aberto — o Binder
 * continua visível (backdrop translúcido + blur, não opaco) atrás do modal.
 *
 * Referência visual enviada por Fabrício (print de um app de coleção real,
 * carta "Ho-Oh"): usada como INSPIRAÇÃO DE ESTRUTURA, não cópia — o que foi
 * aproveitado é o padrão de layout (imagem grande à esquerda, painel de
 * informação em seções à direita, linhas ícone+rótulo à esquerda/valor à
 * direita, botão fechar no canto) e NADA do conteúdo específico daquele
 * benchmark (sem marca "TCGplayer", sem tabela multi-fonte de preço, sem
 * badges de raridade/artista — fora de escopo desta rodada). A paleta
 * também não foi copiada: preço aqui usa o dourado/âmbar já estabelecido no
 * Binder (`hsl(40 70% 62%)`, mesmo tom do anel de seleção/foco), não o verde
 * do benchmark — "coerente com MMKYU" (item 8) pesa mais que imitar a
 * referência.
 *
 * ESCOPO DESTA RODADA (explícito, ver pedido completo): só o Card Detail
 * experimental. Sem alteração de domínio, sem integração de backend real —
 * todo o conteúdo de "No seu acervo"/"Valor de mercado" vem de
 * `card-detail-mock.ts` (determinístico por `card.id`, nunca `Math.random`).
 * Favorite É real dentro do spike: referencia a CARD (`card.id`, nunca uma
 * Card Variant — mesma regra já aplicada em `slot-quick-actions.tsx`) e o
 * estado (`favoriteCardIds` em `binder-pages-nav.tsx`) é compartilhado com o
 * botão de favoritar das Quick Actions do slot — alterar aqui reflete lá
 * enquanto o modal está aberto, sem nenhuma persistência.
 *
 * BINDER-QUICK-ACTIONS-01 (2026-08-29) — o botão de favoritar aqui também
 * passou de dourado para VERMELHO no estado ativo, mesma regra aplicada em
 * `slot-quick-actions.tsx`/`binder-slot-full.tsx`: dourado fica reservado a
 * identidade/foco/premium do MMKYU (o preço logo abaixo continua dourado —
 * não é Favorite), nunca para o estado de favorito. Sem outra mudança nesta
 * rodada — Card Detail não ganhou Lock/Replace/Remove (fora de escopo,
 * pedido explícito: "ações permitidas nesta rodada: favoritar/desfavoritar e
 * fechar").
 *
 * Ações permitidas nesta rodada: favoritar/desfavoritar e fechar — de
 * propósito, NADA de DnD, remover, substituir, Wishlist, Labels, edição de
 * Inventory, marketplace ou histórico de preços completo (todos citados
 * explicitamente como fora de escopo pelo pedido).
 *
 * Acessibilidade (item 10): `role="dialog"`/`aria-modal`, foco inicial no
 * container (`tabIndex=-1`, mesmo padrão já usado no dialog raiz do Binder
 * em `binder-nav-view.tsx`), Esc fecha, Tab preso dentro do modal (focus
 * trap manual — sem dependência nova), e o foco volta para o elemento que
 * abriu o modal ao fechar (restaurado pelo chamador, `binder-pages-nav.tsx`,
 * que guarda a referência do elemento clicado).
 *
 * Isolamento do gesto de navegação do Binder: TODAS as teclas dentro do
 * modal chamam `stopPropagation()` (não só Esc) — sem isso, ArrowLeft/
 * ArrowRight/Home/End vazariam para o `onKeyDown` de `binder-nav-view.tsx` e
 * trocariam de spread com o modal aberto. Mesmo cuidado para
 * pointerdown/pointerup: o wrapper de swipe horizontal em
 * `binder-nav-view.tsx` está mais acima na árvore do DOM (o modal é
 * renderizado dentro de `BinderPagesNav`) — sem `stopPropagation()` aqui, um
 * gesto de arrastar dentro do modal poderia disparar a navegação de spread
 * por baixo dele.
 *
 * LIGHT/DARK (2026-08-29) — pedido explícito: "Card Detail com superfícies
 * claras premium e boa hierarquia" no tema claro, ao contrário do OBJETO
 * Binder (que continua escuro nos dois temas). A superfície do diálogo
 * (fundo/borda/sombra) passou a usar os tokens `--binder-modal-*` (ver
 * `globals.css`, escopados via `.binder-nav-01-scope` — cascata chega aqui
 * porque este componente é renderizado como filho de `BinderPagesNav`, que
 * já está dentro da raiz com essa classe, mesmo o modal sendo `position:
 * fixed`: `position: fixed` só afasta o LAYOUT do fluxo normal, a cascata de
 * CSS variables continua seguindo a árvore real do DOM). Textos/botões/
 * badges ganharam pares `dark:` explícitos; o escuro preserva os valores
 * originais byte-a-byte. O dourado do preço/favorito ficou mais profundo no
 * claro (`hsl(32_..._40%)` em vez de `hsl(40_75%_68%)`) só para manter
 * contraste AA sobre um fundo claro — a MESMA família de cor (âmbar MMKYU),
 * não uma substituição. O backdrop que escurece o Binder por trás (`bg-
 * black/72`) fica igual nos dois temas de propósito: é um scrim sobre a
 * PÁGINA, não uma superfície do modal, e o Binder por trás continua escuro
 * em ambos os temas.
 *
 * POLISH LIGHT MODE (2026-08-29, rodada 2) — pedido de Fabrício: "garantir
 * contraste equivalente no Light Mode, sem redesign" (item 6). Bump pontual
 * de opacidade em textos/botões/badge do claro (labels, valores, botão
 * favoritar/fechar) para equivaler à legibilidade que os Quick Actions já
 * têm no couro escuro do Binder — sem tocar em layout, estrutura ou no
 * escuro (`dark:` inalterado).
 */

const FOCUSABLE_SELECTOR = 'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])';

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="space-y-2">
      <h3 className="text-[11px] font-semibold uppercase tracking-[0.12em] text-black/45 dark:text-white/35">{title}</h3>
      <div className="space-y-2">{children}</div>
    </section>
  );
}

function Row({ icon: Icon, label, value }: { icon?: typeof MapPin; label: string; value: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 text-sm">
      <span className="flex items-center gap-1.5 text-black/55 dark:text-white/45">
        {Icon && <Icon className="h-3.5 w-3.5 flex-shrink-0" aria-hidden />}
        {label}
      </span>
      <span className="min-w-0 truncate text-right text-black/85 dark:text-white/85">{value}</span>
    </div>
  );
}

export function CardDetailModal({
  card,
  isFavorite,
  onToggleFavorite,
  pageNumber,
  slotNumber,
  onClose,
}: {
  card: MockCardData | RealCardData;
  isFavorite: boolean;
  onToggleFavorite: () => void;
  pageNumber: number;
  slotNumber: number;
  onClose: () => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const titleId = `card-detail-title-${card.id}`;

  // Foco inicial no container do diálogo — mesmo padrão já usado no dialog
  // raiz do Binder (`binder-nav-view.tsx`, `dialogRef.current?.focus()`).
  useEffect(() => {
    containerRef.current?.focus();
  }, []);

  const handleKeyDown = useCallback(
    (event: KeyboardEvent<HTMLDivElement>) => {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        onClose();
        return;
      }
      if (event.key === "Tab") {
        const root = containerRef.current;
        if (root) {
          const focusable = Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)).filter(
            (el) => !el.hasAttribute("disabled") && el.getClientRects().length > 0,
          );
          if (focusable.length > 0) {
            const first = focusable[0]!;
            const last = focusable[focusable.length - 1]!;
            if (event.shiftKey && document.activeElement === first) {
              event.preventDefault();
              last.focus();
            } else if (!event.shiftKey && document.activeElement === last) {
              event.preventDefault();
              first.focus();
            }
          }
        }
        event.stopPropagation();
        return;
      }
      // Blanket stop — o foco está preso aqui; nenhuma tecla deve "vazar"
      // para os atalhos de navegação do Binder (setas/Home/End) por baixo.
      event.stopPropagation();
    },
    [onClose],
  );

  // Mesmo racional para gestos de ponteiro — ver doc-comment acima sobre o
  // wrapper de swipe horizontal em `binder-nav-view.tsx`.
  const stopPointerPropagation = useCallback((event: PointerEvent) => event.stopPropagation(), []);

  const setInfo = getCardSetInfoMock(card);
  const pricing = getCardPricingMock(card.id);
  const copiesOwned = getCardCopiesOwnedMock(card.id);
  const isRepeated = copiesOwned > 1;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6"
      onPointerDown={stopPointerPropagation}
      onPointerUp={stopPointerPropagation}
      onClick={onClose}
    >
      {/* Backdrop translúcido + blur — o Binder deve continuar perceptível atrás do modal (item 8). */}
      <div aria-hidden className="absolute inset-0 bg-black/72 backdrop-blur-sm" />

      <div
        ref={containerRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        onKeyDown={handleKeyDown}
        onClick={(event) => event.stopPropagation()}
        className="relative z-10 flex w-full max-w-3xl flex-col overflow-hidden rounded-2xl outline-none sm:flex-row"
        style={{
          background: "hsl(var(--binder-modal-bg))",
          boxShadow: "var(--binder-modal-shadow)",
          border: "1px solid var(--binder-modal-border)",
          maxHeight: "min(88dvh, 720px)",
        }}
      >
        {/* Imagem — protagonista, proporção real preservada (object-contain, item 2). */}
        <div
          className="flex shrink-0 items-center justify-center p-6 sm:w-[42%] sm:p-8"
          style={{ background: "hsl(var(--binder-modal-image-bg))" }}
        >
          <div
            // BINDER-CARD-ASPECT-RATIO-01 — `aspect-[5/7]` → `aspect-[8/11]`,
            // proporção real do asset (600×825px). Aqui o efeito é mais
            // visível que no slot: `fit="contain"` faz o letterbox mudar de
            // eixo (antes sobrava faixa vertical vazia comprimindo a arte
            // percebida; agora a arte ocupa a caixa quase por completo).
            className="relative aspect-[8/11] w-full max-w-[260px] overflow-hidden rounded-md"
            style={{ boxShadow: "var(--binder-modal-image-shadow)" }}
          >
            {"imageUrl" in card ? <RealCardFace card={card} fit="contain" /> : <MockCardFace card={card} />}
          </div>
        </div>

        {/* Painel de informação — hierarquia tipográfica clara, scroll interno só se necessário. */}
        <div className="flex min-h-0 flex-1 flex-col">
          <div className="flex items-start justify-between gap-3 px-5 pt-5 sm:px-6">
            <div className="min-w-0">
              <h2 id={titleId} className="truncate text-xl font-semibold leading-tight text-black/90 dark:text-white">
                {card.name}
              </h2>
              <p className="mt-1 text-sm text-black/60 dark:text-white/50">
                {setInfo.setName} · Nº {setInfo.number}
              </p>
            </div>
            <div className="flex flex-shrink-0 items-center gap-1.5">
              <button
                type="button"
                onClick={onToggleFavorite}
                aria-label={isFavorite ? "Desfavoritar carta" : "Favoritar carta"}
                aria-pressed={isFavorite}
                className={cn(
                  "flex h-9 w-9 items-center justify-center rounded-full border transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-2 focus-visible:ring-offset-[hsl(var(--binder-modal-bg))]",
                  isFavorite
                    ? "border-red-500/40 bg-red-500/[0.14] text-red-600 dark:text-red-400"
                    : "border-black/18 bg-black/[0.06] text-black/65 hover:bg-black/[0.1] hover:text-black/95 dark:border-white/12 dark:bg-white/5 dark:text-white/60 dark:hover:bg-white/5 dark:hover:text-white",
                )}
              >
                <Heart className="h-4 w-4" aria-hidden fill={isFavorite ? "currentColor" : "none"} />
              </button>
              <button
                type="button"
                onClick={onClose}
                aria-label="Fechar detalhes da carta"
                className="flex h-9 w-9 items-center justify-center rounded-full border border-black/18 bg-black/[0.06] text-black/65 transition-colors hover:bg-black/[0.14] hover:text-black/95 focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-2 focus-visible:ring-offset-[hsl(var(--binder-modal-bg))] dark:border-white/12 dark:bg-white/5 dark:text-white/60 dark:hover:bg-white/10 dark:hover:text-white"
              >
                <X className="h-4 w-4" aria-hidden />
              </button>
            </div>
          </div>

          <div className="mt-4 min-h-0 flex-1 space-y-4 overflow-y-auto px-5 pb-5 sm:px-6">
            {/* Contexto do acervo — item 4 do pedido. */}
            <Section title="No seu acervo">
              <Row icon={Layers} label="Coleção" value={setInfo.setName} />
              <Row icon={BookOpen} label="Binder" value={BINDER_NAME} />
              <Row icon={MapPin} label="Localização" value={`Página ${pageNumber} · Slot ${slotNumber}`} />
              <Row
                icon={Copy}
                label="Possuo"
                value={
                  <span className="inline-flex items-center gap-1.5">
                    {copiesOwned} {copiesOwned === 1 ? "cópia" : "cópias"}
                    {isRepeated && (
                      <span className="rounded-full bg-black/[0.12] px-1.5 py-0.5 text-[10px] font-medium leading-none text-black/65 dark:bg-white/10 dark:text-white/55">
                        repetida
                      </span>
                    )}
                  </span>
                }
              />
            </Section>

            <div className="h-px bg-black/[0.1] dark:bg-white/8" aria-hidden />

            {/* Pricing resumido — mock local, sem integração real (item 5). */}
            <Section title="Valor de mercado">
              <div className="flex items-baseline justify-between gap-3">
                <span className="text-black/55 dark:text-white/45">{setInfo.variantLabel ?? "Preço estimado"}</span>
                <span className="text-xl font-semibold text-[hsl(32_70%_40%)] dark:text-[hsl(40_75%_68%)]">
                  {pricing.brl.toLocaleString("pt-BR", { style: "currency", currency: "BRL" })}
                </span>
              </div>
              <p className="text-right text-[11px] text-black/45 dark:text-white/35">
                ≈ {pricing.usd.toLocaleString("en-US", { style: "currency", currency: "USD" })} · referência internacional, dado de teste
              </p>
            </Section>
          </div>
        </div>
      </div>
    </div>
  );
}
