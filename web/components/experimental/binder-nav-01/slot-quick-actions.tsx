import type { LucideIcon } from "lucide-react";
import { Heart, ImagePlus, Plus, Repeat, Trash2 } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * BINDER-INTERACTION-01 (2026-08-28) — quick actions contextuais por slot.
 * Pedido de Fabrício: "criar quick actions contextuais, discretas e premium
 * para slots vazios e ocupados, sem poluir visualmente o Binder." Arquivo
 * novo, isolado em `binder-nav-01/` (mesmo padrão de isolamento de todo o
 * resto do experimental) — sem dependências novas: só `lucide-react`
 * (já usado em `nav-controls.tsx`) e o mesmo token de focus ring dourado já
 * estabelecido lá (`FOCUS_RING`).
 *
 * Duas variantes:
 *  - `EmptySlotQuickActions`: ação primária "Adicionar carta" (rótulo
 *    fantasma, não um botão grande de UI) + espaço reservado, DESABILITADO,
 *    para a futura ação "Adicionar imagem" — só o espaço/affordance visual
 *    pedido explicitamente, sem lógica real ainda.
 *  - `FilledSlotQuickActions`: substituir/favoritar agrupados + remover
 *    isolado por um separador, como ação destrutiva secundária.
 *    IMPORTANTE (pedido explícito): favoritar referencia a CARD, nunca a
 *    Card Variant — `isFavorite`/`onToggleFavorite` são resolvidos pelo
 *    chamador (`binder-pages-nav.tsx`) a partir de `card.id`, nunca de um id
 *    de variante.
 *
 * Correção de composição (2026-08-28, mesma data — pedido final de
 * Fabrício): a lista aprovada de quick actions do slot ocupado é
 * "substituir carta / remover do slot / favoritar-desfavoritar Card" — SEM
 * "visualizar" e SEM "mover":
 *  - "Visualizar" removida da toolbar — a própria carta pode ser clicada
 *    para abrir seus detalhes no futuro, não precisa de um botão dedicado
 *    (nenhuma lógica de abertura de detalhes foi implementada nesta rodada,
 *    só a remoção do botão redundante).
 *  - "Mover" nunca existiu como botão aqui e continua fora de escopo —
 *    movimentação de carta dentro do Binder será tratada EXCLUSIVAMENTE por
 *    Drag and Drop numa rodada futura, nunca por um botão de quick action.
 *  - Uma proposta intermediária de "Adicionar à Wishlist" foi cogitada e
 *    depois REJEITADA por Fabrício antes de chegar a ser implementada:
 *    "não faz sentido oferecer Wishlist dentro de uma carta já inserida no
 *    Binder" — não há, portanto, nenhum código de Wishlist neste arquivo.
 *
 * Rodada visual (2026-08-28, mesma data) — pedido de Fabrício após ver o
 * resultado real: "funcionam conceitualmente, mas precisam de uma rodada
 * visual curta... fazer as quick actions parecerem parte natural do Binder,
 * não uma toolbar genérica sobre cards." Mudanças, SEM nenhuma função nova:
 *  1. Toolbar do slot ocupado deixou de ser uma faixa cheia (`inset-x-0`)
 *     com gradiente forte — agora é uma cápsula compacta, centralizada,
 *     perto da borda inferior, com fundo próprio (não mais uma faixa
 *     cobrindo a largura toda do slot). Ícones menores (glifo reduzido,
 *     alvo de toque mantido em 24px — ver nota de acessibilidade abaixo) e
 *     gap mais fechado.
 *  2. "Remover" passou a ser tratado como ação destrutiva SECUNDÁRIA: fica
 *     isolado por um separador fino depois do grupo visualizar/substituir/
 *     favoritar, com a MESMA aparência neutra em repouso — só ganha cor/
 *     feedback vermelho em hover/focus (`variant="destructive"` em
 *     `QuickActionButton`). Não tem mais o mesmo peso visual das ações
 *     principais.
 *  3. Slot vazio: "Adicionar carta" perdeu a borda/preenchimento de pílula
 *     (lia como botão administrativo) — agora é um rótulo fantasma (texto +
 *     ícone) sem chrome em repouso, só ganha um fundo bem sutil no próprio
 *     hover/focus do botão. O vinhetado atrás dele também encolheu (de uma
 *     faixa forte cobrindo ~15% da altura para um degradê baixo e suave).
 *  4. Favorito já usava contorno quando não-favorito e preenchido quando
 *     favorito (`fill={active ? "currentColor" : "none"}`) — mantido, sem
 *     mudança funcional, só o tom base ficou mais discreto em repouso.
 *  5. Feedback de "ação ativa": todo botão ganha `active:scale-90` (só
 *     transform, sem custo) para dar retorno tátil imediato ao toque/clique,
 *     distinto do estado "favoritado" (que é um toggle persistente, não um
 *     pressionar momentâneo).
 *
 * Posicionamento: cápsula sobreposta à borda inferior do slot. A alternativa
 * "adjacente ao slot" continua descartada — o grid de 3 colunas com `gap-1`
 * não tem espaço lateral/inferior real sem quebrar o layout ou invadir o
 * slot vizinho.
 *
 * Tooltip/aria-label: `title` nativo + `aria-label` em cada botão — o
 * projeto já tem `@radix-ui/react-tooltip` via `components/ui/tooltip`, mas
 * para um ícone de ~24px dentro de um slot de bolso, o overhead de
 * Portal/Provider por botão não se paga; `title` nativo cobre desktop,
 * `aria-label` cobre leitor de tela em qualquer dispositivo.
 *
 * Touch target: botões com no mínimo 24x24px (mínimo AA do WCAG 2.2 "Target
 * Size (Minimum)" — não o antigo 44px, que não cabe fisicamente num slot de
 * ~70-140px de largura sem cobrir a carta). O glifo interno encolheu nesta
 * rodada, mas a área de toque do `<button>` permanece 24px — decisão de
 * design consciente, não omissão.
 */

const FOCUS_RING =
  "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-1 focus-visible:ring-offset-black/80";

function QuickActionButton({
  icon: Icon,
  label,
  onClick,
  active,
  disabled,
  variant = "default",
}: {
  icon: LucideIcon;
  label: string;
  onClick?: () => void;
  active?: boolean;
  disabled?: boolean;
  variant?: "default" | "destructive";
}) {
  return (
    <button
      type="button"
      onClick={(event) => {
        event.stopPropagation();
        onClick?.();
      }}
      disabled={disabled}
      aria-label={label}
      aria-disabled={disabled || undefined}
      title={label}
      className={cn(
        "flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full transition-colors active:scale-90 sm:h-6 sm:w-6",
        disabled
          ? "cursor-not-allowed text-white/20"
          : active
            ? "bg-[hsl(40_70%_62%_/_0.2)] text-[hsl(40_75%_72%)] hover:bg-[hsl(40_70%_62%_/_0.3)]"
            : variant === "destructive"
              ? "text-white/45 hover:bg-red-500/15 hover:text-red-400 focus-visible:ring-red-400/70"
              : "text-white/70 hover:bg-white/15 hover:text-white",
        FOCUS_RING,
      )}
    >
      <Icon className="h-2.5 w-2.5" aria-hidden fill={active ? "currentColor" : "none"} />
    </button>
  );
}

export function EmptySlotQuickActions({ onAddCard }: { onAddCard: () => void }) {
  return (
    <div className="pointer-events-auto absolute inset-x-0 bottom-[7%] flex items-center justify-center gap-1">
      <button
        type="button"
        onClick={(event) => {
          event.stopPropagation();
          onAddCard();
        }}
        aria-label="Adicionar carta"
        title="Adicionar carta"
        className={cn(
          "flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[9px] font-medium text-white/80 transition-colors active:scale-95 hover:bg-white/10 hover:text-white sm:text-[10px]",
          FOCUS_RING,
        )}
      >
        <Plus className="h-2.5 w-2.5" aria-hidden />
        Adicionar carta
      </button>
      {/* Espaço reservado para a futura ação "Adicionar imagem" — sem lógica
          real ainda (pedido explícito: "não precisa implementar lógica real
          ainda"), só o espaço/affordance visual. */}
      <QuickActionButton icon={ImagePlus} label="Adicionar imagem (em breve)" disabled />
    </div>
  );
}

export function FilledSlotQuickActions({
  isFavorite,
  onReplace,
  onRemove,
  onToggleFavorite,
}: {
  isFavorite: boolean;
  onReplace: () => void;
  onRemove: () => void;
  onToggleFavorite: () => void;
}) {
  return (
    <div className="pointer-events-auto absolute inset-x-0 bottom-[7%] flex items-center justify-center">
      <div
        className="flex items-center gap-0.5 rounded-full px-1 py-0.5"
        style={{
          background: "hsl(0 0% 0% / 0.62)",
          boxShadow: "0 2px 8px rgba(0,0,0,0.5), inset 0 1px 0 hsl(0 0% 100% / 0.06)",
        }}
      >
        <QuickActionButton icon={Repeat} label="Substituir carta" onClick={onReplace} />
        <QuickActionButton
          icon={Heart}
          label={isFavorite ? "Desfavoritar carta" : "Favoritar carta"}
          onClick={onToggleFavorite}
          active={isFavorite}
        />
        {/* Separador — isola "remover" (destrutiva) do grupo principal, para
            não ter o mesmo peso visual das outras ações. */}
        <div className="mx-0.5 h-3 w-px flex-shrink-0" style={{ background: "hsl(0 0% 100% / 0.14)" }} aria-hidden />
        <QuickActionButton icon={Trash2} label="Remover do slot" onClick={onRemove} variant="destructive" />
      </div>
    </div>
  );
}
