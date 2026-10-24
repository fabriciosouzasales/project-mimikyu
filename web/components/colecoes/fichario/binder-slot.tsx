"use client";

import { createContext, useCallback, useContext, useEffect, useState, type RefObject } from "react";
import * as TooltipPrimitive from "@radix-ui/react-tooltip";
import { useDndContext, useDraggable, useDroppable, type DraggableSyntheticListeners } from "@dnd-kit/core";
import {
  BetweenVerticalStart,
  Bookmark,
  BookmarkX,
  Check,
  Crop,
  ImageOff,
  Inbox,
  Lock,
  LockOpen,
  Maximize2,
  Plus,
  RefreshCw,
  Shuffle,
  Trash2,
  Undo2,
  Ungroup,
  type LucideIcon,
} from "lucide-react";
import { cardFrontUrl, formatCollectorNumber } from "@/lib/colecoes/acervo";
import { type BinderSlot, type RegionImage, type SlotImage, canReserveCurrent, hasReservation, isOccupied, slotDescription } from "@/lib/colecoes/binder";
import { regionObjectPosition } from "@/lib/colecoes/binder-region";
import { type SpeciesReference, formatNationalNumber, shouldShowSpeciesReference, speciesReferenceLabel } from "@/lib/colecoes/binder-species";
import { speciesArtworkUrl } from "@/lib/pokedex/artwork";
import { cn } from "@/lib/utils";
import { PocketArt } from "./binder-page";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

/**
 * POKEDEX-BINDER-SPECIES-REFERENCE: exibição das referências de espécie do
 * fichário (preferência persistida, ajuste A). `false` em todo fichário que
 * não é de Pokédex — o bolso vazio segue exatamente como antes.
 */
export const SpeciesReferenceVisibleContext = createContext(false);

/** Onde menus flutuantes são montados: dentro do diálogo do fichário (foco e tela cheia). */
export const BinderPortalContext = createContext<RefObject<HTMLElement | null> | null>(null);

/** `available`: carta ainda sem bolso (Cartas disponíveis) — `slotId` carrega a alocação. */
export type SlotDragData = { kind: "slot" | "tray" | "available"; slotId: string };

export type SlotHandlers = {
  onActivate: (slot: BinderSlot, additive: boolean) => void;
  onToggleSelect: (slot: BinderSlot) => void;
  onToggleLock: (slot: BinderSlot) => void;
  onToTray: (slot: BinderSlot) => void;
  /** Devolve a carta que está na Bandeja ao próprio bolso (nada é gravado). */
  onReturnFromTray: (slot: BinderSlot) => void;
  onReserve: (slot: BinderSlot) => void;
  onClearReserve: (slot: BinderSlot) => void;
  /** Pede confirmação antes de tirar do fichário (o "Desfazer" continua depois). */
  onRemove: (slot: BinderSlot) => void;
  /** Bolso vazio (ou só reservado) e solto: abre "Adicionar carta" (P2-BINDER-CAPACITY-AND-EMPTY-SLOT-01). */
  onAddCard: (slot: BinderSlot) => void;
  /** Bolso com imagem personalizada (C-198): ver, ajustar, substituir ou remover. */
  onOpenImage: (slot: BinderSlot, mode: "view" | "frame" | "replace" | "remove") => void;
  /** Inserir espaço antes deste bolso (5243): prévia do banco → confirmação quando atravessa página. */
  onInsertGap: (slot: BinderSlot) => void;
  /** Imagem em 2 bolsos (5240): ver, ajustar, substituir ou separar. */
  onOpenRegion: (regionId: string, mode: RegionDialogMode) => void;
};

export type RegionDialogMode = "view" | "frame" | "replace" | "separate";

const SHEEN = "linear-gradient(115deg, hsl(0 0% 100% / 0.2) 0%, transparent 32%, transparent 68%, hsl(0 0% 100% / 0.06) 100%)";
const RING = "focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-1 focus-visible:ring-offset-black/80";

/**
 * Bolso do fichário — recuperado do spike `binder-nav-01/binder-slot-full.tsx`
 * e `slot-quick-actions.tsx` (P2-B-SPIKE-RECOVERY-01), ligado aos dados reais
 * da 5223 e só às ações com contrato:
 *
 *  - bolso escuro com abertura e reflexo do plástico, carta ocupando o bolso;
 *  - selos persistentes: cadeado (azul-frio) e divergência da reserva no
 *    canto direito;
 *  - P2-B-CARD-QUICK-ACTIONS-01: o menu "…" saiu. No canto superior
 *    ESQUERDO, um botão circular de seleção (um clique marca/desmarca,
 *    dourado quando marcada). Na BASE, a cápsula do spike com ações diretas,
 *    nesta ordem: Bandeja (levar/devolver) · Reserva (reservar/liberar) ·
 *    Fixação (fixar/soltar) · Retirada (pede confirmação; "Desfazer" depois).
 *    Aparece em hover/foco; no toque, tocar a carta dá foco e revela, tocar
 *    fora esconde. Cada botão reflete o estado real do bolso e fica
 *    indisponível (aria-disabled + tooltip com o motivo) quando não se aplica;
 *    bolso sem carta só mostra o que vale para ele (reserva e fixação).
 *    Do spike ficam de fora, sem botão fictício: Favoritar e Substituir (sem
 *    contrato). "Adicionar carta" no bolso vazio voltou em P2-BINDER-
 *    CAPACITY-AND-EMPTY-SLOT-01 (5230 lista as cartas sem bolso; 5131
 *    posiciona) e "Adicionar imagem" (o `ImagePlus` do spike) em
 *    P2-BINDER-CUSTOM-IMAGES-CLOSEOUT-AND-FRONTEND-01, como aba do mesmo
 *    seletor (5231–5236);
 *  - bolso com imagem personalizada (C-198): a imagem cobre o bolso com o
 *    enquadramento salvo, sob o mesmo plástico; não arrasta, não recebe
 *    carta, não é selecionável nem fixável. Cápsula própria: Ver · Ajustar ·
 *    Substituir · Remover;
 *  - com seleção ativa, as ações individuais somem e clicar alterna a
 *    seleção (regra do spike, BINDER-MULTISELECT-UX-01); bolso vazio nunca
 *    é selecionável.
 */
export function BinderSlotView({
  slot,
  sizes,
  priority,
  editable,
  selected,
  selectionActive,
  inTray,
  placing,
  isSource,
  pocket,
  handlers,
  dimmed = false,
  placingAvailable = false,
  canInsertGap = false,
}: {
  slot: BinderSlot;
  sizes: string;
  priority: boolean;
  editable: boolean;
  selected: boolean;
  selectionActive: boolean;
  inTray: boolean;
  /** Há uma carta "na mão" (arrastando ou escolhida na Bandeja). */
  placing: boolean;
  isSource: boolean;
  /** Largura do bolso em px (encaixe): dimensiona os controles para caber em 4×5 e 5×4. */
  pocket: number;
  handlers: SlotHandlers;
  /** "Só desta coleção": bolso de outra coleção do fichário compartilhado (só visual). */
  dimmed?: boolean;
  /** A carta "na mão" é uma carta disponível: só bolso vazio recebe (nunca substitui). */
  placingAvailable?: boolean;
  /** "Abrir espaço antes deste bolso" vale aqui (bolso com conteúdo, sem barreira, fora de "Só desta coleção"). */
  canInsertGap?: boolean;
}) {
  const occupied = isOccupied(slot);
  const reserved = !occupied && slot.state === "RESERVED_EMPTY";
  const image = !occupied && !reserved ? (slot.image ?? null) : null;
  // D3: só o bolso visualmente vazio mostra a referência (carta, reserva, imagem e mesclagem têm prioridade).
  const speciesVisible = useContext(SpeciesReferenceVisibleContext);
  const speciesRef = shouldShowSpeciesReference(slot, speciesVisible) ? (slot.speciesRef ?? null) : null;
  const canDrag = editable && occupied && !slot.locked && !inTray && !selectionActive;
  // Bolso com imagem nunca recebe carta (o banco recusa com SLOT_HAS_IMAGE).
  const canDrop = editable && !slot.locked && !image && (!inTray || isSource) && !(placingAvailable && occupied);
  const drag = useDraggable({
    id: `slot:${slot.slotId}`,
    data: { kind: "slot", slotId: slot.slotId } satisfies SlotDragData,
    disabled: !canDrag,
  });
  const drop = useDroppable({ id: `pocket:${slot.slotId}`, disabled: !canDrop });
  const { active: anyDrag } = useDndContext();
  const setRefs = useCallback(
    (node: HTMLDivElement | null) => {
      drag.setNodeRef(node);
      drop.setNodeRef(node);
    },
    [drag, drop],
  );

  const face = occupied ? slot.present : slot.expected;
  const src = cardFrontUrl(SUPABASE_URL, face?.imagePath ?? null);
  const number = face?.collectorNumber ? formatCollectorNumber(face.collectorNumber, face.collectorTotal) : null;
  // Spike binder-nav-01 (EmptySlotQuickActions): bolso vazio e solto convida a "Adicionar carta".
  const addable = editable && !occupied && !image && !slot.locked && !selectionActive && !placing && !inTray;
  const label = [slotDescription(slot), speciesRef ? speciesReferenceLabel(speciesRef) : null, addable ? "Enter para adicionar carta" : null, dimmed ? "de outra coleção" : null, slot.locked ? "bolso fixado" : null, inTray ? "carta na Bandeja" : null, selected ? "selecionada" : null]
    .filter(Boolean)
    .join(", ");
  const validDrop = drop.isOver && canDrop && !isSource;
  const lockedDuringDrag = slot.locked && (!!anyDrag || placing);
  // Selecionar não depende de editar (é só tela); as ações gravam e respeitam o modo leitura.
  const canSelect = occupied && !inTray;
  const showActions = editable && !selectionActive;
  // Controles proporcionais ao bolso: legíveis em 2×2, sem cobrir a arte em 5×4.
  const control = Math.round(Math.min(26, Math.max(18, pocket * 0.2)));

  const activate = (event: React.MouseEvent | React.KeyboardEvent) => {
    const additive = "ctrlKey" in event && (event.ctrlKey || event.metaKey || event.shiftKey);
    handlers.onActivate(slot, additive);
  };

  return (
    <div
      ref={setRefs}
      role="group"
      aria-label={label}
      className="group/slot relative overflow-hidden rounded-[4px] transition-[opacity,filter] duration-200 ease-out motion-reduce:transition-none"
      style={{
        aspectRatio: "8 / 11",
        background: occupied || image ? "hsl(0 0% 3% / 0.4)" : "hsl(0 0% 0% / 0.32)",
        boxShadow: ["inset 1px 1px 0 hsl(0 0% 100% / 0.14)", "inset -1px -1px 0 hsl(0 0% 0% / 0.4)", "inset 0 3px 7px rgba(0,0,0,0.55)"].join(", "),
        opacity: drag.isDragging ? 0.35 : dimmed ? 0.3 : selectionActive && occupied && !selected ? 0.7 : 1,
        filter: dimmed ? "saturate(0.35)" : undefined,
      }}
    >
      {!occupied && !reserved && !image ? (
        <div
          className="pointer-events-none absolute inset-[10%]"
          style={{ backgroundImage: "repeating-linear-gradient(0deg, hsl(0 0% 100% / 0.03) 0px, hsl(0 0% 100% / 0.03) 1px, transparent 1px, transparent 6px)" }}
          aria-hidden
        />
      ) : null}

      {/* Área principal: a carta (ou a reserva). Clique: colocar a carta da mão, alternar seleção ou só focar. */}
      <div
        role="button"
        tabIndex={0}
        aria-label={label}
        aria-pressed={occupied ? selected : undefined}
        onClick={activate}
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            activate(event);
          }
        }}
        className={cn(
          "absolute inset-0 overflow-hidden outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[hsl(40_70%_62%)]",
          canDrag ? "cursor-grab active:cursor-grabbing" : image && placing ? "cursor-not-allowed" : "cursor-pointer",
        )}
        {...(canDrag ? (drag.listeners as DraggableSyntheticListeners) : undefined)}
      >
        {occupied ? (
          <PocketArt src={src} name={face?.cardName ?? null} number={number} priority={priority} sizes={sizes} />
        ) : image ? (
          <SlotImageArt image={image} priority={priority} />
        ) : speciesRef ? (
          <SpeciesReferenceArt reference={speciesRef} />
        ) : reserved ? (
          <span className="absolute inset-0 block">
            <span className="absolute inset-0 block opacity-25 grayscale-[0.7]">
              <PocketArt src={src} name={null} number={null} priority={false} sizes={sizes} />
            </span>
            <span
              className="absolute inset-x-[6%] bottom-[6%] rounded-[3px] px-1 py-0.5 text-center text-[9px] font-semibold leading-tight text-white/80 sm:text-[10px]"
              style={{ background: "hsl(0 0% 0% / 0.55)" }}
              aria-hidden
            >
              <span className="block truncate">{face?.cardName ?? "Reservado"}</span>
              <span className="block text-white/55">Falta{number ? ` · ${number}` : ""}</span>
            </span>
          </span>
        ) : null}
      </div>

      {addable ? (
        <div
          className="pointer-events-none absolute inset-0 flex items-center justify-center opacity-0 transition-opacity duration-150 group-hover/slot:opacity-100 group-focus-within/slot:opacity-100 motion-reduce:transition-none"
          aria-hidden
        >
          <span
            className="flex items-center justify-center rounded-full text-white/80"
            style={{ width: control + 6, height: control + 6, background: "hsl(0 0% 0% / 0.5)", boxShadow: "inset 0 0 0 1px hsl(0 0% 100% / 0.22)" }}
          >
            <Plus style={{ width: control * 0.55, height: control * 0.55 }} />
          </span>
        </div>
      ) : null}

      {/* Abertura e reflexo do plástico (spike). */}
      <div className="pointer-events-none absolute inset-x-0 top-[7%] h-[2px]" style={{ background: "hsl(0 0% 100% / 0.16)" }} aria-hidden />
      <div className="pointer-events-none absolute inset-0" style={{ backgroundImage: SHEEN, opacity: occupied || image ? 0.35 : 0.75 }} aria-hidden />
      <div className="pointer-events-none absolute inset-0 rounded-[4px]" style={{ boxShadow: "inset 0 0 0 1px hsl(0 0% 100% / 0.1)" }} aria-hidden />

      {inTray ? (
        <div
          className="pointer-events-none absolute inset-0 z-10 flex flex-col items-center justify-center gap-1 text-[10px] font-semibold text-[hsl(40_80%_78%)]"
          style={{ background: "hsl(0 0% 0% / 0.72)", boxShadow: "inset 0 0 0 1px hsl(40 70% 62% / 0.6)" }}
          aria-hidden
        >
          <Inbox className="h-4 w-4" />
          Na Bandeja
        </div>
      ) : null}

      {slot.locked ? (
        <Badge side="right" tone="hsl(205 80% 75%)">
          <Lock className="h-2 w-2 sm:h-2.5 sm:w-2.5" fill="currentColor" aria-hidden />
        </Badge>
      ) : null}
      {slot.state === "OCCUPIED_MISMATCH" ? (
        <Badge side="right" offset={slot.locked ? 1 : 0} tone="hsl(38 92% 70%)" title="Diferente da carta reservada">
          <Shuffle className="h-2 w-2 sm:h-2.5 sm:w-2.5" aria-hidden />
        </Badge>
      ) : null}

      {!selected ? (
        <div
          className="pointer-events-none absolute inset-0 rounded-[4px] opacity-0 transition-opacity duration-150 group-hover/slot:opacity-100 group-focus-within/slot:opacity-100"
          style={{ boxShadow: "0 0 0 1px hsl(0 0% 100% / 0.35)" }}
          aria-hidden
        />
      ) : (
        <>
          <div className="pointer-events-none absolute inset-0 rounded-[4px]" style={{ background: "hsl(40 70% 62% / 0.06)" }} aria-hidden />
          <div
            className="pointer-events-none absolute inset-0 rounded-[4px]"
            style={{ boxShadow: "0 0 0 2px hsl(40 70% 62% / 0.85), 0 6px 12px -4px rgba(0,0,0,0.45)" }}
            aria-hidden
          />
        </>
      )}

      {validDrop || (placing && canDrop && !isSource && !anyDrag) ? (
        <div
          className="pointer-events-none absolute inset-0 z-20 rounded-[4px]"
          style={
            validDrop
              ? { background: "hsl(40 70% 62% / 0.12)", boxShadow: "0 0 0 2px hsl(40 70% 62% / 0.85), 0 0 14px 2px hsl(40 70% 62% / 0.3)" }
              : { boxShadow: "inset 0 0 0 1px hsl(40 70% 62% / 0.45)" }
          }
          aria-hidden
        />
      ) : null}
      {lockedDuringDrag ? (
        <div
          className="pointer-events-none absolute inset-0 z-20 rounded-[4px]"
          style={{
            background: "hsl(0 0% 0% / 0.45)",
            backgroundImage: "repeating-linear-gradient(135deg, hsl(0 0% 100% / 0.06) 0px, hsl(0 0% 100% / 0.06) 2px, transparent 2px, transparent 8px)",
            boxShadow: "inset 0 0 0 1px hsl(205 40% 70% / 0.3)",
          }}
          aria-hidden
        />
      ) : null}

      {canSelect && (editable || selectionActive) ? (
        <SelectButton
          selected={selected}
          visible={selected || selectionActive}
          size={control}
          name={face?.cardName ?? "carta"}
          onToggle={() => handlers.onToggleSelect(slot)}
        />
      ) : null}

      {showActions && !placing && !selectionActive ? (
        <>
          <div
            className="pointer-events-none absolute inset-x-0 bottom-0 h-[30%] opacity-0 transition-opacity duration-150 group-hover/slot:opacity-100 group-focus-within/slot:opacity-100"
            style={{ background: "linear-gradient(0deg, hsl(0 0% 0% / 0.42) 0%, transparent 100%)" }}
            aria-hidden
          />
          <div
            className={cn(
              "pointer-events-none absolute inset-x-0 bottom-0 z-30 h-[30%] opacity-0 transition-opacity duration-150 motion-reduce:transition-none",
              "group-hover/slot:pointer-events-auto group-hover/slot:opacity-100",
              "group-focus-within/slot:pointer-events-auto group-focus-within/slot:opacity-100",
            )}
          >
            {image ? (
              <ImageQuickActions slot={slot} size={control} handlers={handlers} canInsertGap={canInsertGap} />
            ) : (
              <QuickActions slot={slot} occupied={occupied} reserved={reserved} inTray={inTray} size={control} handlers={handlers} canInsertGap={canInsertGap} />
            )}
          </div>
        </>
      ) : null}
    </div>
  );
}

/**
 * Referência de espécie no bolso vazio (POKEDEX-BINDER-SPECIES-REFERENCE):
 * arte oficial atenuada, sem moldura de carta, e o número nacional discreto.
 * Não é carta — nada de nome em destaque, selo ou brilho de carta possuída.
 * Arte de 320 px (WebP endereçado por conteúdo), carregada sob demanda; se
 * não houver arte ou ela falhar, fica só o número (o bolso continua vazio).
 */
function SpeciesReferenceArt({ reference }: { reference: SpeciesReference }) {
  const url = speciesArtworkUrl(reference.artworkPath);
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [url]);
  return (
    <span className="pointer-events-none absolute inset-0 block" aria-hidden>
      {url && !failed ? (
        // eslint-disable-next-line @next/next/no-img-element -- arte pública e imutável (hash no caminho); sem otimizador para 1.025 bolsos
        <img
          src={url}
          alt=""
          width={320}
          height={320}
          draggable={false}
          decoding="async"
          loading="lazy"
          className="absolute inset-x-[12%] top-[16%] h-auto w-[76%] object-contain opacity-[0.26] grayscale-[0.35]"
          onError={() => setFailed(true)}
        />
      ) : null}
      <span className="absolute inset-x-0 bottom-[6%] text-center text-[9px] font-semibold tabular-nums tracking-wide text-white/40 sm:text-[10px]">
        {formatNationalNumber(reference.nationalNumber)}
      </span>
    </span>
  );
}

/**
 * Imagem personalizada no bolso: cobre o bolso com o enquadramento salvo
 * (`object-position` 50% foco%). URL assinada de 1 h ou prévia local; se não
 * carregar, aviso discreto — o bolso continua "com imagem" (nunca vira vazio).
 */
function SlotImageArt({ image, priority }: { image: SlotImage; priority: boolean }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [image.url]);
  if (!image.url || failed) {
    return (
      <span
        className="absolute inset-0 flex flex-col items-center justify-center gap-1 px-1 text-center text-[9px] font-semibold leading-tight text-white/55 sm:text-[10px]"
        style={{ background: "linear-gradient(160deg, hsl(0 0% 14%), hsl(0 0% 7%))" }}
        aria-hidden
      >
        <ImageOff className="h-3.5 w-3.5 opacity-70" />
        Imagem indisponível
      </span>
    );
  }
  return (
    // eslint-disable-next-line @next/next/no-img-element -- URL assinada do bucket privado (1 h) ou prévia local blob:
    <img
      src={image.url}
      alt=""
      draggable={false}
      decoding="async"
      loading={priority ? "eager" : "lazy"}
      className="absolute inset-0 h-full w-full object-cover"
      style={{ objectPosition: `50% ${image.focalY}%` }}
      onError={() => setFailed(true)}
    />
  );
}

function Badge({ side, tone, title, offset = 0, children }: { side: "left" | "right"; tone: string; title?: string; offset?: number; children: React.ReactNode }) {
  return (
    <div
      className={cn(
        "pointer-events-none absolute z-10 flex h-3.5 w-3.5 items-center justify-center rounded-full sm:h-4 sm:w-4",
        side === "left" ? "left-[6%]" : "right-[6%]",
      )}
      style={{ top: `calc(6% + ${offset * 1.25}rem)`, background: "hsl(0 0% 0% / 0.55)", color: tone }}
      title={title}
      aria-hidden
    >
      {children}
    </div>
  );
}

/** Tooltip escuro do spike, montado dentro do diálogo (funciona em tela cheia). */
function Tip({ label, children }: { label: string; children: React.ReactNode }) {
  const portal = useContext(BinderPortalContext);
  return (
    <TooltipPrimitive.Root>
      <TooltipPrimitive.Trigger asChild>{children}</TooltipPrimitive.Trigger>
      <TooltipPrimitive.Portal container={portal?.current ?? undefined}>
        <TooltipPrimitive.Content
          side="top"
          sideOffset={6}
          collisionPadding={8}
          className="z-[95] select-none rounded-md px-2 py-1 text-[11px] font-medium text-white/90"
          style={{ background: "hsl(0 0% 6% / 0.96)", boxShadow: "0 6px 16px -4px rgba(0,0,0,0.6), 0 0 0 1px hsl(0 0% 100% / 0.1)" }}
        >
          {label}
          <TooltipPrimitive.Arrow style={{ fill: "hsl(0 0% 6% / 0.96)" }} />
        </TooltipPrimitive.Content>
      </TooltipPrimitive.Portal>
    </TooltipPrimitive.Root>
  );
}

/**
 * Seleção individual: círculo no canto superior esquerdo. Um clique marca ou
 * desmarca. Fica visível em hover/foco, quando marcada ou com seleção ativa.
 * `pointerdown` não chega ao arrasto (o botão é irmão da área arrastável).
 */
function SelectButton({ selected, visible, size, name, onToggle }: { selected: boolean; visible: boolean; size: number; name: string; onToggle: () => void }) {
  return (
    <TooltipPrimitive.Provider delayDuration={300}>
      <Tip label={selected ? "Desmarcar" : "Selecionar"}>
        <button
          type="button"
          aria-pressed={selected}
          aria-label={selected ? `Desmarcar ${name}` : `Selecionar ${name}`}
          onPointerDown={(event) => event.stopPropagation()}
          onClick={(event) => {
            event.stopPropagation();
            onToggle();
          }}
          className={cn(
            "absolute left-[4%] top-[4%] z-30 flex items-center justify-center rounded-full transition-opacity duration-150 motion-reduce:transition-none",
            visible ? "opacity-100" : "opacity-0 group-hover/slot:opacity-100 group-focus-within/slot:opacity-100 focus-visible:opacity-100",
            RING,
          )}
          // Área de toque maior que o círculo visível.
          style={{ width: size + 8, height: size + 8, margin: -4 }}
        >
          <span
            className="flex items-center justify-center rounded-full"
            style={{
              width: size,
              height: size,
              background: selected ? "hsl(40 70% 55%)" : "hsl(0 0% 0% / 0.55)",
              boxShadow: selected ? "0 1px 3px rgba(0,0,0,0.5)" : "inset 0 0 0 1.5px hsl(0 0% 100% / 0.75), 0 1px 3px rgba(0,0,0,0.45)",
            }}
          >
            {selected ? <Check className="text-black" style={{ width: size * 0.6, height: size * 0.6 }} strokeWidth={3} aria-hidden /> : null}
          </span>
        </button>
      </Tip>
    </TooltipPrimitive.Provider>
  );
}

function QuickButton({
  icon: Icon,
  label,
  onClick,
  size,
  active,
  tone = "neutral",
  disabled = false,
}: {
  icon: LucideIcon;
  label: string;
  onClick: () => void;
  size: number;
  active?: boolean;
  tone?: "neutral" | "tray" | "reserve" | "lock" | "danger";
  disabled?: boolean;
}) {
  const activeClass =
    tone === "lock"
      ? "bg-[hsl(205_70%_58%_/_0.22)] text-[hsl(205_80%_75%)] hover:bg-[hsl(205_70%_58%_/_0.32)]"
      : "bg-[hsl(40_70%_62%_/_0.22)] text-[hsl(40_80%_78%)] hover:bg-[hsl(40_70%_62%_/_0.32)]";
  return (
    <Tip label={label}>
      <button
        type="button"
        onPointerDown={(event) => event.stopPropagation()}
        onClick={(event) => {
          event.stopPropagation();
          if (!disabled) onClick();
        }}
        aria-label={label}
        aria-pressed={active}
        aria-disabled={disabled || undefined}
        className={cn(
          "flex flex-shrink-0 items-center justify-center rounded-full transition-colors",
          disabled
            ? "cursor-not-allowed text-white/25"
            : active
              ? activeClass
              : tone === "danger"
                ? "text-white/60 hover:bg-red-500/15 hover:text-red-400"
                : "text-white/75 hover:bg-white/15 hover:text-white",
          !disabled && "active:scale-90",
          RING,
        )}
        style={{ width: size, height: size }}
      >
        <Icon style={{ width: size * 0.52, height: size * 0.52 }} aria-hidden />
      </button>
    </Tip>
  );
}

/** Cápsula do bolso com imagem: Ver · Ajustar · Substituir · Remover. */
function ImageQuickActions({ slot, size, handlers, canInsertGap }: { slot: BinderSlot; size: number; handlers: SlotHandlers; canInsertGap: boolean }) {
  return (
    <TooltipPrimitive.Provider delayDuration={250} skipDelayDuration={100}>
      <div className="absolute inset-x-0 bottom-[6%] flex items-center justify-center">
        <div
          role="toolbar"
          aria-label="Ações da imagem do bolso"
          className="flex items-center gap-px rounded-full px-0.5 py-0.5"
          style={{ background: "hsl(0 0% 0% / 0.62)", boxShadow: "0 2px 8px rgba(0,0,0,0.5), inset 0 1px 0 hsl(0 0% 100% / 0.06)" }}
        >
          {canInsertGap ? <QuickButton icon={BetweenVerticalStart} label="Abrir espaço antes deste bolso" onClick={() => handlers.onInsertGap(slot)} size={size} /> : null}
          <QuickButton icon={Maximize2} label="Ver imagem" onClick={() => handlers.onOpenImage(slot, "view")} size={size} />
          <QuickButton icon={Crop} label="Ajustar enquadramento" onClick={() => handlers.onOpenImage(slot, "frame")} size={size} />
          <QuickButton icon={RefreshCw} label="Substituir imagem" onClick={() => handlers.onOpenImage(slot, "replace")} size={size} />
          <QuickButton icon={Trash2} label="Remover imagem" onClick={() => handlers.onOpenImage(slot, "remove")} size={size} tone="danger" />
        </div>
      </div>
    </TooltipPrimitive.Provider>
  );
}

/**
 * Cápsula de ações diretas na base da carta (spike `FilledSlotQuickActions`):
 * Bandeja · Reserva · Fixação · Retirada. Só entra o que vale para o bolso.
 */
function QuickActions({
  slot,
  occupied,
  reserved,
  inTray,
  size,
  handlers,
  canInsertGap,
}: {
  slot: BinderSlot;
  occupied: boolean;
  reserved: boolean;
  inTray: boolean;
  size: number;
  handlers: SlotHandlers;
  canInsertGap: boolean;
}) {
  const reservation = hasReservation(slot);
  const canReserve = canReserveCurrent(slot);
  return (
    <TooltipPrimitive.Provider delayDuration={250} skipDelayDuration={100}>
      <div className="absolute inset-x-0 bottom-[6%] flex items-center justify-center">
        <div
          role="toolbar"
          aria-label="Ações do bolso"
          className="flex items-center gap-px rounded-full px-0.5 py-0.5"
          style={{ background: "hsl(0 0% 0% / 0.62)", boxShadow: "0 2px 8px rgba(0,0,0,0.5), inset 0 1px 0 hsl(0 0% 100% / 0.06)" }}
        >
          {canInsertGap ? <QuickButton icon={BetweenVerticalStart} label="Abrir espaço antes deste bolso" onClick={() => handlers.onInsertGap(slot)} size={size} /> : null}
          {occupied ? (
            inTray ? (
              <QuickButton icon={Undo2} label="Devolver da Bandeja a este bolso" onClick={() => handlers.onReturnFromTray(slot)} size={size} active tone="tray" />
            ) : (
              <QuickButton
                icon={Inbox}
                label={slot.locked ? "Levar para a Bandeja — solte o bolso primeiro" : "Levar para a Bandeja"}
                onClick={() => handlers.onToTray(slot)}
                size={size}
                tone="tray"
                disabled={slot.locked}
              />
            )
          ) : null}
          {!occupied && !slot.locked && !inTray ? (
            <QuickButton icon={Plus} label="Adicionar carta" onClick={() => handlers.onAddCard(slot)} size={size} />
          ) : null}
          {occupied || reserved || reservation ? (
            reservation ? (
              <QuickButton icon={BookmarkX} label="Liberar reserva deste bolso" onClick={() => handlers.onClearReserve(slot)} size={size} active tone="reserve" />
            ) : (
              <QuickButton
                icon={Bookmark}
                label={canReserve ? "Reservar este bolso para a carta" : "Reservar — sem carta para reservar"}
                onClick={() => handlers.onReserve(slot)}
                size={size}
                tone="reserve"
                disabled={!canReserve}
              />
            )
          ) : null}
          <QuickButton
            icon={slot.locked ? Lock : LockOpen}
            label={inTray ? "Fixar — devolva a carta da Bandeja primeiro" : slot.locked ? "Soltar bolso" : "Fixar bolso"}
            onClick={() => handlers.onToggleLock(slot)}
            size={size}
            active={slot.locked}
            tone="lock"
            disabled={inTray && !slot.locked}
          />
          {occupied ? (
            <QuickButton
              icon={Trash2}
              label={slot.locked ? "Tirar do fichário — solte o bolso primeiro" : inTray ? "Tirar do fichário — devolva da Bandeja primeiro" : "Tirar do fichário"}
              onClick={() => handlers.onRemove(slot)}
              size={size}
              tone="danger"
              disabled={slot.locked || inTray}
            />
          ) : null}
        </div>
      </div>
    </TooltipPrimitive.Provider>
  );
}

/**
 * Fenda entre dois bolsos (referência aprovada "Insert slot"): no hover,
 * um fio dourado e um "+" marcam onde o espaço abre. Só ponteiro — teclado
 * e toque usam o mesmo comando na cápsula do bolso ("Abrir espaço antes
 * deste bolso"), por isso fica fora da ordem de Tab.
 */
export function GapGutter({ gap, height, size, label, onInsert }: { gap: number; height: number; size: number; label: string; onInsert: () => void }) {
  const zone = Math.max(14, gap + 8);
  return (
    <button
      type="button"
      tabIndex={-1}
      aria-label={label}
      title={label}
      onPointerDown={(event) => event.stopPropagation()}
      onClick={(event) => {
        event.stopPropagation();
        onInsert();
      }}
      className="group/gutter absolute top-0 z-40 flex cursor-pointer items-center justify-center outline-none"
      style={{ left: -(gap / 2) - zone / 2, width: zone, height }}
    >
      <span
        aria-hidden
        className="pointer-events-none absolute inset-y-[8%] left-1/2 w-[2px] -translate-x-1/2 rounded-full opacity-0 transition-opacity duration-150 group-hover/gutter:opacity-100 motion-reduce:transition-none"
        style={{ background: "linear-gradient(180deg, transparent, hsl(40 70% 62% / 0.9) 18%, hsl(40 70% 62% / 0.9) 82%, transparent)", boxShadow: "0 0 10px hsl(40 70% 62% / 0.45)" }}
      />
      <span
        aria-hidden
        className="pointer-events-none relative flex scale-90 items-center justify-center rounded-full opacity-0 transition-[opacity,transform] duration-150 group-hover/gutter:scale-100 group-hover/gutter:opacity-100 motion-reduce:transition-none"
        style={{ width: size, height: size, background: "hsl(40 70% 55%)", color: "hsl(0 0% 6%)", boxShadow: "0 2px 8px rgba(0,0,0,0.55)" }}
      >
        <Plus style={{ width: size * 0.6, height: size * 0.6 }} strokeWidth={2.6} />
      </span>
    </button>
  );
}

/**
 * Imagem em 2 bolsos (5239–5241): uma única peça cobrindo os bolsos lado a
 * lado, com o vão entre eles — mesmo plástico, reflexo e abertura do bolso.
 * Barreira para cartas e para "Abrir espaço". Cápsula: Ver · Ajustar ·
 * Substituir · Separar. Sem imagem lida (assinatura falhou, leitura
 * atrasada), a área continua visível e protegida.
 */
export function RegionPocketView({
  regionId,
  region,
  anchor,
  width,
  pocket,
  gap,
  pageNumber,
  priority,
  editable,
  showActions,
  placing,
  dimmed = false,
  handlers,
}: {
  regionId: string;
  region: RegionImage | null;
  anchor: BinderSlot;
  width: number;
  pocket: number;
  gap: number;
  pageNumber: number;
  priority: boolean;
  editable: boolean;
  showActions: boolean;
  placing: boolean;
  dimmed?: boolean;
  handlers: SlotHandlers;
}) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [region?.url]);
  const control = Math.round(Math.min(26, Math.max(18, pocket * 0.2)));
  const label = `Imagem em ${width} bolsos, página ${pageNumber}, linha ${anchor.row}, colunas ${anchor.column} a ${anchor.column + width - 1}`;
  return (
    <div
      role="group"
      aria-label={label}
      className="group/slot relative h-full overflow-hidden rounded-[4px] transition-[opacity,filter] duration-200 ease-out motion-reduce:transition-none"
      style={{
        width: pocket * width + gap * (width - 1),
        background: "hsl(0 0% 3% / 0.4)",
        boxShadow: ["inset 1px 1px 0 hsl(0 0% 100% / 0.14)", "inset -1px -1px 0 hsl(0 0% 0% / 0.4)", "inset 0 3px 7px rgba(0,0,0,0.55)"].join(", "),
        opacity: dimmed ? 0.3 : 1,
        filter: dimmed ? "saturate(0.35)" : undefined,
      }}
    >
      <div
        role="button"
        tabIndex={0}
        aria-label={`${label}. Enter para ver`}
        aria-haspopup="dialog"
        onClick={() => handlers.onOpenRegion(regionId, "view")}
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            handlers.onOpenRegion(regionId, "view");
          }
        }}
        className={cn(
          "absolute inset-0 overflow-hidden outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[hsl(40_70%_62%)]",
          placing ? "cursor-not-allowed" : "cursor-pointer",
        )}
      >
        {region?.url && !failed ? (
          // eslint-disable-next-line @next/next/no-img-element -- URL assinada do bucket privado (1 h) ou prévia local blob:
          <img
            src={region.url}
            alt=""
            draggable={false}
            decoding="async"
            loading={priority ? "eager" : "lazy"}
            className="absolute inset-0 h-full w-full object-cover"
            style={{ objectPosition: regionObjectPosition(region.focalX, region.focalY) }}
            onError={() => setFailed(true)}
          />
        ) : (
          <span
            className="absolute inset-0 flex flex-col items-center justify-center gap-1 px-1 text-center text-[9px] font-semibold leading-tight text-white/55 sm:text-[10px]"
            style={{ background: "linear-gradient(160deg, hsl(0 0% 14%), hsl(0 0% 7%))" }}
            aria-hidden
          >
            <ImageOff className="h-3.5 w-3.5 opacity-70" />
            {region ? "Imagem indisponível" : "Imagem em 2 bolsos"}
          </span>
        )}
      </div>

      {/* Costura discreta entre os bolsos: a peça é uma só, mas o fichário continua tendo bolsos. */}
      {Array.from({ length: width - 1 }).map((_, index) => (
        <div
          key={index}
          className="pointer-events-none absolute inset-y-[3%]"
          style={{ left: pocket * (index + 1) + gap * index + gap / 2 - 0.5, width: 1, background: "hsl(0 0% 100% / 0.07)" }}
          aria-hidden
        />
      ))}
      <div className="pointer-events-none absolute inset-x-0 top-[7%] h-[2px]" style={{ background: "hsl(0 0% 100% / 0.16)" }} aria-hidden />
      <div className="pointer-events-none absolute inset-0" style={{ backgroundImage: SHEEN, opacity: 0.35 }} aria-hidden />
      <div className="pointer-events-none absolute inset-0 rounded-[4px]" style={{ boxShadow: "inset 0 0 0 1px hsl(0 0% 100% / 0.1)" }} aria-hidden />
      <div
        className="pointer-events-none absolute inset-0 rounded-[4px] opacity-0 transition-opacity duration-150 group-hover/slot:opacity-100 group-focus-within/slot:opacity-100"
        style={{ boxShadow: "0 0 0 1px hsl(0 0% 100% / 0.35)" }}
        aria-hidden
      />

      {showActions && !placing ? (
        <>
          <div
            className="pointer-events-none absolute inset-x-0 bottom-0 h-[30%] opacity-0 transition-opacity duration-150 group-hover/slot:opacity-100 group-focus-within/slot:opacity-100"
            style={{ background: "linear-gradient(0deg, hsl(0 0% 0% / 0.42) 0%, transparent 100%)" }}
            aria-hidden
          />
          <div
            className={cn(
              "pointer-events-none absolute inset-x-0 bottom-0 z-30 h-[30%] opacity-0 transition-opacity duration-150 motion-reduce:transition-none",
              "group-hover/slot:pointer-events-auto group-hover/slot:opacity-100",
              "group-focus-within/slot:pointer-events-auto group-focus-within/slot:opacity-100",
            )}
          >
            <TooltipPrimitive.Provider delayDuration={250} skipDelayDuration={100}>
              <div className="absolute inset-x-0 bottom-[6%] flex items-center justify-center">
                <div
                  role="toolbar"
                  aria-label="Ações da imagem em 2 bolsos"
                  className="flex items-center gap-px rounded-full px-0.5 py-0.5"
                  style={{ background: "hsl(0 0% 0% / 0.62)", boxShadow: "0 2px 8px rgba(0,0,0,0.5), inset 0 1px 0 hsl(0 0% 100% / 0.06)" }}
                >
                  <QuickButton icon={Maximize2} label="Ver imagem" onClick={() => handlers.onOpenRegion(regionId, "view")} size={control} />
                  {editable ? (
                    <>
                      <QuickButton icon={Crop} label="Ajustar enquadramento" onClick={() => handlers.onOpenRegion(regionId, "frame")} size={control} disabled={!region} />
                      <QuickButton icon={RefreshCw} label="Substituir imagem" onClick={() => handlers.onOpenRegion(regionId, "replace")} size={control} disabled={!region} />
                      <QuickButton icon={Ungroup} label="Separar os bolsos" onClick={() => handlers.onOpenRegion(regionId, "separate")} size={control} tone="danger" />
                    </>
                  ) : null}
                </div>
              </div>
            </TooltipPrimitive.Provider>
          </div>
        </>
      ) : null}
    </div>
  );
}
