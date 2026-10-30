"use client";

import { useMemo } from "react";
import { RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { type BinderPage, isOccupied } from "@/lib/colecoes/binder";
import { regionCells } from "@/lib/colecoes/binder-region";
import { isForeignSlot } from "@/lib/colecoes/binder-share";
import { cn } from "@/lib/utils";
import { BinderSlotView, GapGutter, RegionPocketView, type SlotDragData, type SlotHandlers } from "./binder-slot";

/**
 * Folha de bolsos do fichário (extraída de `BinderWorkspace` em V1-12 VIEWER
 * EXPERIENCE PARITY CORRECTION-02, sem mudança visual): grade no encaixe
 * calculado, bolsos `BinderSlotView`, imagem em 2 bolsos, esqueleto enquanto
 * a página carrega e "Tentar de novo" na falha.
 *
 * Mesma peça para o titular (`editable`, seleção, Bandeja, abrir espaço) e
 * para o participante VIEWER (`editable=false`, nenhuma ação — os bolsos
 * chegam mascarados pelo banco).
 */
export function PageGrid({
  pageNumber,
  page,
  failed,
  columns,
  rows,
  pocket,
  gap,
  sizes,
  editable,
  selected,
  selectionActive,
  trayIds,
  armed,
  dragging,
  placing,
  placingAvailable,
  focusCollectionId,
  insertEnabled,
  handlers,
  onRetry,
}: {
  pageNumber: number;
  page: BinderPage | null;
  failed: boolean;
  columns: number;
  rows: number;
  pocket: number;
  gap: number;
  sizes: string;
  editable: boolean;
  selected: Set<string>;
  selectionActive: boolean;
  trayIds: Set<string>;
  armed: string | null;
  dragging: SlotDragData | null;
  placing: boolean;
  placingAvailable: boolean;
  focusCollectionId: string | null;
  insertEnabled: boolean;
  handlers: SlotHandlers;
  onRetry: () => void;
}) {
  const cells = useMemo(() => (page ? regionCells(page) : null), [page]);
  const height = (pocket * 11) / 8;
  const control = Math.round(Math.min(26, Math.max(18, pocket * 0.2)));
  return (
    <div
      role="list"
      aria-label={`Página ${pageNumber}`}
      aria-busy={!page || undefined}
      className="relative grid"
      style={{ gridTemplateColumns: `repeat(${columns}, ${pocket}px)`, gridAutoRows: `${(pocket * 11) / 8}px`, gap }}
    >
      {page && cells
        ? page.slots.map((slot, index) => {
            // Bolso coberto por uma imagem em 2 bolsos: a âncora desenha a peça inteira.
            if (cells.covered.has(slot.slotId)) return null;
            const region = cells.anchors.get(slot.slotId);
            if (region) {
              return (
                <div role="listitem" key={slot.slotId} style={{ gridColumn: `span ${region.width}` }}>
                  <RegionPocketView
                    regionId={region.regionId}
                    region={region.region}
                    anchor={slot}
                    width={region.width}
                    pocket={pocket}
                    gap={gap}
                    pageNumber={pageNumber}
                    priority={index < columns * 2}
                    editable={editable}
                    showActions={!selectionActive}
                    placing={placing}
                    dimmed={focusCollectionId !== null}
                    handlers={handlers}
                  />
                </div>
              );
            }
            const inTray = trayIds.has(slot.slotId);
            // Abrir espaço só antes de um bolso com conteúdo e fora de barreira (fixado/mesclado).
            const insertable =
              insertEnabled && !inTray && !slot.locked && !slot.regionId && (isOccupied(slot) || Boolean(slot.expectedCardId) || Boolean(slot.image));
            return (
            <div role="listitem" key={slot.slotId} className="relative">
              {insertable && slot.column > 1 ? (
                <GapGutter gap={gap} height={height} size={control} label={`Abrir espaço antes do bolso da linha ${slot.row}, coluna ${slot.column}`} onInsert={() => handlers.onInsertGap(slot)} />
              ) : null}
              <BinderSlotView
                slot={slot}
                sizes={sizes}
                priority={index < columns * 2}
                editable={editable}
                selected={selected.has(slot.slotId)}
                selectionActive={selectionActive}
                inTray={inTray}
                placing={placing}
                isSource={dragging?.slotId === slot.slotId || armed === slot.slotId}
                pocket={pocket}
                handlers={handlers}
                placingAvailable={placingAvailable}
                dimmed={focusCollectionId !== null && isForeignSlot(slot, focusCollectionId)}
                canInsertGap={insertable}
              />
            </div>
            );
          })
        : Array.from({ length: columns * rows }).map((_, index) => (
            <div
              key={index}
              aria-hidden
              className={cn("rounded-[4px]", !failed && "animate-pulse")}
              style={{ background: "hsl(0 0% 0% / 0.32)", boxShadow: "inset 0 3px 7px rgba(0,0,0,0.55), inset 0 0 0 1px hsl(0 0% 100% / 0.06)" }}
            />
          ))}
      {!page && failed ? (
        <div role="alert" className="absolute inset-0 flex flex-col items-center justify-center gap-3 rounded-md p-4 text-center text-sm text-white/75" style={{ background: "hsl(0 0% 0% / 0.55)" }}>
          <p>Não conseguimos abrir esta página.</p>
          <Button variant="outline" size="sm" className="border-white/25 bg-transparent text-white hover:bg-white/10" onClick={onRetry}>
            <RotateCcw className="h-3.5 w-3.5" aria-hidden />
            Tentar de novo
          </Button>
        </div>
      ) : null}
    </div>
  );
}
