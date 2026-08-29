"use client";

import { Heart } from "lucide-react";
import type { BinderSlotData } from "@/app/experimental/binder-nav-01/mock-data";
import { MockCardFace } from "@/components/experimental/binder-spike/mock-card-face";
import { cn } from "@/lib/utils";
import { RealCardFace } from "./real-card-face";
import { EmptySlotQuickActions, FilledSlotQuickActions } from "./slot-quick-actions";

/**
 * Variante local de `BinderSlot` (`binder-spike/binder-slot.tsx`) para o
 * BINDER-NAV-01 — pedido de Fabrício, 2026-08-28: "a carta deve ocupar 100%
 * do plástico do slot". O `BinderSlot` original reserva uma margem
 * (`inset-[4%] top-[3%]`) simulando a borda do bolso de PVC ao redor da
 * carta; aqui a carta preenche o bolso de ponta a ponta (`inset-0`) — mais
 * evidência/protagonismo para a carta, pedido explícito desta rodada.
 *
 * Cópia local, não edição do componente compartilhado: `binder-slot.tsx`
 * continua servindo Binder-First/BINDER-VIS-02 exatamente como estava
 * (isolamento experimental total, mesmo padrão já aplicado a
 * `cover-panel.tsx`/`binder-pages-nav.tsx`). Mesma lógica de bolso vazio,
 * abertura no topo e reflexo de plástico — só o preenchimento da carta
 * ocupada muda.
 *
 * Teste ME2 (mesma data) — `slot.card` agora pode ser a carta fictícia
 * (`MockCardData`, SVG sintético) ou uma carta REAL do ME2 (`RealCardData`,
 * artwork do Supabase via `RealCardFace`) — discriminado por `"imageUrl" in
 * slot.card`, já que só `RealCardData` tem esse campo.
 *
 * BINDER-INTERACTION-01 (2026-08-28) — quick actions contextuais por slot
 * (pedido completo de Fabrício, ver `slot-quick-actions.tsx`). O slot deixa
 * de ser puramente presentacional:
 *  - Container agora é `role="group"` + `tabIndex=0`, focável e clicável —
 *    clicar/Enter/Space alterna o estado SELECIONADO (`isSelected`, estado
 *    vem de cima, de `binder-pages-nav.tsx`, para ser efetivamente único por
 *    spread e permitir um único listener de clique-fora). Selecionar NÃO
 *    executa nenhuma ação — só revela/prende a toolbar; quem executa ações
 *    são os botões da própria toolbar (evita ambiguidade "selecionar vs.
 *    adicionar").
 *  - Visibilidade da toolbar = hover OU focus-within (100% CSS, via
 *    `group-hover`/`group-focus-within` — sem JS, sem custo, e sem risco de
 *    "foco chega num botão invisível": `:focus-within` casa no MESMO reflow
 *    em que o botão recebe foco) OU selecionado (classe condicional via
 *    JS, já que precisa sobreviver ao mouse saindo do slot). Isso cobre
 *    diretamente "em mobile, tap deve substituir hover" — o tap já dispara
 *    onClick → seleciona → toolbar aparece, sem depender de :hover.
 *  - Selo de favorito (Card, não Card Variant — `isFavorite` resolvido pelo
 *    pai a partir de `card.id`) fica visível permanentemente quando
 *    favoritado, independente de hover/seleção — sem isso a ação de
 *    favoritar pareceria não ter feito nada assim que o mouse sai do slot.
 *  - Anel de seleção dourado (mesmo tom do focus ring do resto da rota)
 *    para "deixar estado selecionado claro" (item 4 do pedido).
 *  - `prefers-reduced-motion`: já coberto pela regra global em
 *    `globals.css` (`transition-duration: 0.01ms !important` sob o media
 *    query) — nenhuma lógica adicional necessária aqui.
 *
 * CARD-DETAIL-01 (2026-08-29) — pedido de Fabrício: "Binder = contexto de
 * organização; Card Detail = contexto de informação da carta... ao clicar
 * diretamente em uma carta ocupando um slot, abrir um modal de detalhes."
 * Duas mudanças aqui, ambas escopadas a slot OCUPADO:
 *  - A própria arte da carta (o `<div>` que renderiza `RealCardFace`/
 *    `MockCardFace`, ocupando 100% do bolso) virou um elemento focável e
 *    clicável (`role="button"`), com `stopPropagation()` no click/Enter/
 *    Space para NÃO também disparar `onSelectToggle` do grupo pai — clicar
 *    na carta abre o Card Detail (`onOpenDetail`), não seleciona o slot.
 *  - A camada de quick actions (linha ~217 abaixo) tinha `absolute inset-0`
 *    — cobria o slot INTEIRO com `pointer-events-auto` assim que
 *    hover/focus-within ficava verdadeiro, mesmo a cápsula visível
 *    ocupando só uma faixa estreita perto da base. Isso bloqueava
 *    completamente o clique na carta em qualquer slot com o mouse em cima
 *    (que é o estado normal um instante antes de qualquer clique no
 *    desktop). Corrigido para `inset-x-0 bottom-0 h-[30%]` (mesma altura já
 *    usada pelo vinhetado logo acima) — a cápsula continua exatamente onde
 *    estava (ela mesma já é `bottom-[7%]`, bem dentro dessa faixa), só a
 *    área INVISÍVEL que capturava cliques encolheu para não competir com a
 *    arte da carta. Sem essa correção, "clicar na carta abre o Card Detail"
 *    simplesmente não funcionava em desktop.
 *  - Consequência aceita (documentada, não uma omissão): em touch/mobile,
 *    sem hover, tocar a carta agora abre o Card Detail diretamente em vez
 *    de "selecionar" o slot primeiro. As quick actions (Substituir/Remover/
 *    Favoritar) continuam alcançáveis em mobile porque o próprio elemento
 *    da carta é `tabIndex=0` — tocar nele move o foco do teclado para ele,
 *    o que já satisfaz `:focus-within` no slot pai e revela a cápsula (CSS
 *    puro, ver bloco de quick actions abaixo) — inclusive depois de fechar
 *    o Card Detail, já que o foco retorna para esse mesmo elemento
 *    (restaurado por `binder-pages-nav.tsx`).
 *
 * Rodada visual (2026-08-28, mesma data) — pedido de Fabrício: "as quick
 * actions funcionam conceitualmente, mas precisam de uma rodada visual
 * curta... diferenciar claramente hover/focus, selecionado e ação ativa. O
 * estado selecionado deve pertencer ao SLOT inteiro, não parecer apenas
 * seleção de um ícone." Mudanças (sem nenhuma função nova):
 *  - Novo anel de hover/focus, neutro (branco 35%) e mais fino que o de
 *    seleção — dá feedback ao passar/focar SEM ser confundido com
 *    "selecionado". Fica escondido quando `isSelected` para não empilhar
 *    dois contornos ao mesmo tempo.
 *  - Seleção ganhou um TINT translúcido (dourado, 5% de alfa) cobrindo o
 *    slot inteiro, além do anel — o objetivo explícito de Fabrício era que
 *    o estado pertencesse ao retângulo inteiro, não só à borda.
 *  - O vinhetado atrás das quick actions encolheu bastante (de uma faixa
 *    forte cobrindo boa parte da altura para um degradê baixo e suave) —
 *    a cápsula/rótulo de `slot-quick-actions.tsx` já trazem contraste
 *    próprio; isto é só o mínimo de apoio para legibilidade contra fundos
 *    claros.
 */

const SHEEN =
  "linear-gradient(115deg, hsl(0 0% 100% / 0.2) 0%, transparent 32%, transparent 68%, hsl(0 0% 100% / 0.06) 100%)";

export function BinderSlotFull({
  slot,
  isSelected,
  isFavorite,
  onSelectToggle,
  onAddCard,
  onOpenDetail,
  onReplace,
  onRemove,
  onToggleFavorite,
}: {
  slot: BinderSlotData;
  isSelected: boolean;
  isFavorite: boolean;
  onSelectToggle: () => void;
  onAddCard: () => void;
  onOpenDetail: (triggerEl: HTMLElement) => void;
  onReplace: () => void;
  onRemove: () => void;
  onToggleFavorite: () => void;
}) {
  const cardName = slot.card?.name;
  const groupLabel = `${slot.filled && cardName ? `Carta: ${cardName}` : "Slot vazio"}${isSelected ? " (selecionado)" : ""}`;

  return (
    <div
      role="group"
      aria-label={groupLabel}
      tabIndex={0}
      onClick={onSelectToggle}
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          onSelectToggle();
        }
      }}
      className={cn(
        "group/slot relative aspect-[5/7] cursor-pointer overflow-hidden rounded-[4px] outline-none transition-transform duration-150",
        "focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-1 focus-visible:ring-offset-black/70",
      )}
      style={{
        background: slot.filled ? "hsl(0 0% 3% / 0.4)" : "hsl(0 0% 0% / 0.32)",
        boxShadow: [
          "inset 1px 1px 0 hsl(0 0% 100% / 0.14)",
          "inset -1px -1px 0 hsl(0 0% 0% / 0.4)",
          "inset 0 3px 7px rgba(0,0,0,0.55)",
        ].join(", "),
      }}
    >
      {!slot.filled && (
        <div
          className="pointer-events-none absolute inset-[10%]"
          style={{
            backgroundImage:
              "repeating-linear-gradient(0deg, hsl(0 0% 100% / 0.03) 0px, hsl(0 0% 100% / 0.03) 1px, transparent 1px, transparent 6px)",
          }}
          aria-hidden
        />
      )}

      {slot.filled && slot.card && (
        <div
          role="button"
          tabIndex={0}
          aria-label={`Ver detalhes de ${cardName ?? "carta"}`}
          onClick={(event) => {
            event.stopPropagation();
            onOpenDetail(event.currentTarget);
          }}
          onKeyDown={(event) => {
            if (event.key === "Enter" || event.key === " ") {
              event.preventDefault();
              event.stopPropagation();
              onOpenDetail(event.currentTarget);
            }
          }}
          className="absolute inset-0 cursor-pointer overflow-hidden outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[hsl(40_70%_62%)]"
        >
          {"imageUrl" in slot.card ? <RealCardFace card={slot.card} /> : <MockCardFace card={slot.card} />}
        </div>
      )}

      {/* Abertura do bolso — linha clara perto do topo, onde a carta é inserida. */}
      <div
        className="pointer-events-none absolute inset-x-0 top-[7%] h-[2px]"
        style={{ background: "hsl(0 0% 100% / 0.16)" }}
        aria-hidden
      />

      {/* Reflexo do plástico do bolso — por cima do conteúdo, vende "dentro do bolso". */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{ backgroundImage: SHEEN, opacity: slot.filled ? 0.35 : 0.75 }}
        aria-hidden
      />
      {/* Contorno externo do bolso — perceptível mesmo vazio. */}
      <div
        className="pointer-events-none absolute inset-0 rounded-[4px]"
        style={{ boxShadow: "inset 0 0 0 1px hsl(0 0% 100% / 0.1)" }}
        aria-hidden
      />

      {/* Selo de favorito — persistente, independente de hover/seleção (Card, não Card Variant). */}
      {isFavorite && (
        <div
          className="pointer-events-none absolute right-[6%] top-[6%] z-10 flex h-3.5 w-3.5 items-center justify-center rounded-full sm:h-4 sm:w-4"
          style={{ background: "hsl(0 0% 0% / 0.55)" }}
          aria-hidden
        >
          <Heart className="h-2 w-2 text-[hsl(40_75%_72%)] sm:h-2.5 sm:w-2.5" fill="currentColor" aria-hidden />
        </div>
      )}

      {/* Anel de hover/focus — neutro, mais sutil que o de seleção; some
          quando selecionado para não empilhar dois contornos ao mesmo
          tempo (item 2 do pedido: hover/focus e seleção precisam ler como
          coisas diferentes). 100% CSS, sem JS. */}
      {!isSelected && (
        <div
          className="pointer-events-none absolute inset-0 rounded-[4px] opacity-0 transition-opacity duration-150 group-hover/slot:opacity-100 group-focus-within/slot:opacity-100"
          style={{ boxShadow: "0 0 0 1px hsl(0 0% 100% / 0.35)" }}
          aria-hidden
        />
      )}

      {/* Seleção — tint translúcido cobrindo o slot INTEIRO + anel dourado.
          Pedido explícito: "o estado selecionado deve pertencer ao SLOT
          inteiro, não parecer apenas seleção de um ícone." */}
      {isSelected && (
        <>
          <div
            className="pointer-events-none absolute inset-0 rounded-[4px]"
            style={{ background: "hsl(40 70% 62% / 0.05)" }}
            aria-hidden
          />
          <div
            className="pointer-events-none absolute inset-0 rounded-[4px]"
            style={{ boxShadow: "0 0 0 2px hsl(40 70% 62% / 0.9), 0 0 10px 1px hsl(40 70% 62% / 0.35)" }}
            aria-hidden
          />
        </>
      )}

      {/* Vinhetado mínimo de apoio à leitura das quick actions — bem mais
          curto/suave que antes; a cápsula/rótulo já trazem contraste
          próprio (ver `slot-quick-actions.tsx`). */}
      <div
        className="pointer-events-none absolute inset-x-0 bottom-0 h-[30%] opacity-0 transition-opacity duration-150 group-hover/slot:opacity-100 group-focus-within/slot:opacity-100"
        style={{
          background: "linear-gradient(0deg, hsl(0 0% 0% / 0.4) 0%, transparent 100%)",
          ...(isSelected ? { opacity: 1 } : undefined),
        }}
        aria-hidden
      />

      {/* Quick actions — visível em hover/focus-within (CSS puro) OU seleção
          (classe JS, sobrevive ao mouse saindo do slot). */}
      <div
        className={cn(
          "pointer-events-none absolute inset-x-0 bottom-0 h-[30%] opacity-0 transition-opacity duration-150",
          "group-hover/slot:pointer-events-auto group-hover/slot:opacity-100",
          "group-focus-within/slot:pointer-events-auto group-focus-within/slot:opacity-100",
          isSelected && "pointer-events-auto opacity-100",
        )}
      >
        {slot.filled ? (
          <FilledSlotQuickActions
            isFavorite={isFavorite}
            onReplace={onReplace}
            onRemove={onRemove}
            onToggleFavorite={onToggleFavorite}
          />
        ) : (
          <EmptySlotQuickActions onAddCard={onAddCard} />
        )}
      </div>
    </div>
  );
}
