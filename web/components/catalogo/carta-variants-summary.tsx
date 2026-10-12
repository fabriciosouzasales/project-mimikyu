"use client";

import { AlertTriangle, EyeOff, Layers, Star } from "lucide-react";
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { useAnchoredPopover } from "@/hooks/use-anchored-popover";
import type { CartaVariantViewState } from "@/lib/catalogo/carta-variants";
import { buildVariantSummaryModel, VARIANT_LABEL_SEPARATOR } from "@/lib/catalogo/carta-variant-summary";
import { cn } from "@/lib/utils";

/**
 * Indicador de variantes da galeria — Nível 2 (VARIANT-DISPLAY-SEMANTICS-01 / F2.2).
 *
 * Substitui o tooltip legado, que mostrava só o nome do acabamento e por isso
 * repetia "Holográfica" para variantes distintas.
 *
 * Mantém o mesmo pill discreto (ícone + quantidade) e o mesmo padrão de
 * popover do pill de preço vizinho (`useAnchoredPopover`): o próprio pill é um
 * botão focável que abre por hover, foco ou toque e fecha com Escape ou
 * clique fora.
 *
 * Conteúdo: uma linha por variante, na ordem canônica da F1. O acabamento
 * aparece em destaque normal; tiragem e Edition Context aparecem como
 * qualificadores em tom secundário, separados por " / " (D1).
 *
 * Erro da F1 (D2): mostra a contagem bruta e "Detalhes indisponíveis", sem
 * recorrer aos nomes legados.
 *
 * P1 (2026-10-11): a variante padrão aparece marcada com estrela + texto
 * "Padrão" (nunca só cor); carta sem padrão mostra o aviso "Sem variante
 * padrão". `onManageDefault` (opcional) acrescenta o atalho para o diálogo
 * de escolha — caminho de mouse/toque; o caminho de teclado é o diálogo de
 * edição da carta, que tem a mesma ação.
 */
export function CartaVariantsSummary({
  cardId,
  cartaName,
  view,
  onManageDefault,
  onManageVariants,
}: {
  cardId: string;
  cartaName: string;
  view: CartaVariantViewState | null | undefined;
  onManageDefault?: () => void;
  /** P2a: atalho "Gerenciar variações" (lista + cadastro individual). */
  onManageVariants?: () => void;
}) {
  const { anchorRef, contentRef, open, position, scheduleOpen, scheduleClose, openNow, closeNow, toggle } =
    useAnchoredPopover<HTMLButtonElement, HTMLDivElement>();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const model = buildVariantSummaryModel(view, cartaName);
  if (model.kind === "HIDDEN") return null;

  const popoverId = `carta-variants-${cardId}`;
  const unavailable = model.kind === "UNAVAILABLE";

  return (
    <>
      <button
        ref={anchorRef}
        type="button"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? popoverId : undefined}
        aria-label={model.triggerLabel}
        onMouseEnter={() => scheduleOpen()}
        onMouseLeave={() => scheduleClose()}
        onFocus={() => openNow()}
        onBlur={() => scheduleClose()}
        onClick={(event) => {
          event.stopPropagation();
          toggle();
        }}
        className="inline-flex shrink-0 items-center gap-0.5 rounded-full bg-surface-muted px-1.5 py-0.5 text-[9px] font-medium leading-none text-muted-foreground hover:bg-surface-muted/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        {unavailable ? (
          <AlertTriangle className="h-2.5 w-2.5 text-warning" aria-hidden="true" />
        ) : (
          <Layers className="h-2.5 w-2.5" aria-hidden="true" />
        )}
        {model.count ?? "—"}
      </button>

      {mounted && open
        ? createPortal(
            <div
              ref={contentRef}
              id={popoverId}
              role="dialog"
              aria-modal="false"
              aria-label={`Variações cadastradas de ${cartaName}`}
              onMouseEnter={openNow}
              onMouseLeave={() => scheduleClose()}
              style={{
                position: "fixed",
                top: position?.top ?? -9999,
                left: position?.left ?? -9999,
                visibility: position ? "visible" : "hidden",
              }}
              className="z-50 w-max min-w-[180px] max-w-[min(320px,calc(100vw-24px))] rounded-lg border border-border bg-surface p-3 text-xs text-foreground shadow-panel"
            >
              <p className="font-semibold">Variações cadastradas</p>
              {model.kind === "LIST" ? (
                <ul className="mt-1.5 space-y-1">
                  {model.lines.map((line) => (
                    <li
                      key={line.id}
                      aria-label={[line.label, line.isDefault ? "variante padrão" : null, line.isActive ? null : "inativa"]
                        .filter(Boolean)
                        .join(", ")}
                      className={cn("flex items-baseline gap-1.5 leading-snug", !line.isActive && "text-muted-foreground")}
                    >
                      <span aria-hidden="true" className="text-muted-foreground">
                        •
                      </span>
                      <span aria-hidden="true">
                        {line.parts.map((part, index) => (
                          <span
                            key={part.axis}
                            className={cn(part.emphasis === "qualifier" && "text-muted-foreground")}
                          >
                            {index > 0 ? VARIANT_LABEL_SEPARATOR : null}
                            {part.text}
                          </span>
                        ))}
                        {!line.isActive ? (
                          <span className="ml-1.5 inline-flex translate-y-[-1px] items-center gap-0.5 rounded-full border border-border bg-surface-muted px-1.5 py-px align-middle text-[9px] font-medium uppercase tracking-wide text-muted-foreground">
                            <EyeOff className="h-2.5 w-2.5" aria-hidden="true" />
                            Inativa
                          </span>
                        ) : null}
                        {line.repeatedLabel ? (
                          <span className="ml-1.5 rounded bg-surface-muted px-1 py-px text-[10px] text-muted-foreground">
                            rótulo repetido
                          </span>
                        ) : null}
                        {line.isDefault ? (
                          <span className="ml-1.5 inline-flex translate-y-[-1px] items-center gap-0.5 rounded-full border border-primary/40 bg-primary/5 px-1.5 py-px align-middle text-[9px] font-medium uppercase tracking-wide text-primary-ink">
                            <Star className="h-2.5 w-2.5 fill-current" aria-hidden="true" />
                            Padrão
                          </span>
                        ) : null}
                      </span>
                    </li>
                  ))}
                </ul>
              ) : null}
              {model.kind === "LIST" ? (
                !model.defaultLine || onManageDefault || onManageVariants ? (
                <div className="mt-2 space-y-1.5 border-t border-border pt-2">
                <div className="flex items-center justify-between gap-3">
                  {model.defaultLine ? (
                    <span aria-hidden="true" />
                  ) : (
                    <span className="inline-flex items-center gap-1 text-warning">
                      <AlertTriangle className="h-3 w-3" aria-hidden="true" />
                      Sem variante padrão
                    </span>
                  )}
                  {onManageDefault ? (
                    <button
                      type="button"
                      onClick={(event) => {
                        event.stopPropagation();
                        closeNow();
                        onManageDefault();
                      }}
                      className="rounded font-medium text-primary-ink underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      {model.defaultLine ? "Alterar padrão" : "Escolher padrão"}
                    </button>
                  ) : null}
                </div>
                {onManageVariants ? (
                  <div className="flex justify-end">
                    <button
                      type="button"
                      onClick={(event) => {
                        event.stopPropagation();
                        closeNow();
                        onManageVariants();
                      }}
                      className="rounded font-medium text-primary-ink underline-offset-4 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      Gerenciar variações
                    </button>
                  </div>
                ) : null}
                </div>
                ) : null
              ) : (
                <div className="mt-1.5 flex items-start gap-1.5 text-muted-foreground">
                  <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0 text-warning" aria-hidden="true" />
                  <p>
                    <span className="font-medium text-foreground">Detalhes indisponíveis.</span>{" "}
                    {model.count === null
                      ? "Não foi possível ler as variações desta carta."
                      : `${model.count === 1 ? "1 variação cadastrada" : `${model.count} variações cadastradas`}, mas os dados de uma delas estão incompletos.`}
                  </p>
                </div>
              )}
            </div>,
            document.body,
          )
        : null}
    </>
  );
}
