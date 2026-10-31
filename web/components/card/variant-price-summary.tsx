"use client";

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { useAnchoredPopover } from "@/hooks/use-anchored-popover";
import {
  type VariantPrice,
  formatBrl,
  isPriceMuted,
  NM_REFERENCE_NOTE,
  type PriceIndicator,
  priceDetail,
  priceIndicator,
  priceState,
} from "@/lib/pricing/variant-pricing";
import { cn } from "@/lib/utils";
import { StateGlyph } from "./price-glyph";
import { PRICE_PILL_BASE, PRICE_PILL_INTERACTIVE } from "./price-pill";

/**
 * Preço NM por variante na Collection (V1-09) — mesmo pill do Catálogo
 * Editorial (`price-pill.ts`, referência Genesect EX #004/030).
 *
 * - Sem preço (sem valor, câmbio ausente): não renderiza nada (D5).
 * - Preço antigo (> 14 dias, D1) ou sem data confirmada (fallback, data
 *   além da tolerância futura): o ícone muda de forma (relógio com seta /
 *   calendário cortado) e o texto do estado vai no tooltip e no nome
 *   acessível. O valor mantém a cor de texto principal do Catálogo em todos
 *   os estados (C1: contraste ≥ 4,5:1 em Light e Dark; a cor nunca é o único
 *   sinal) — nunca apresentado como atualizado.
 * - `interactive`: o pill é um botão que abre o detalhe (hover, foco, toque),
 *   como no Catálogo.
 * - `appearance="overlay"` (V1-09, UNIFICATION-08): o mesmo botão e o mesmo
 *   detalhe, vestidos como a etiqueta sobre a arte (classes do chamador —
 *   linguagem homologada do Acervo/fichário); ícone só fora do estado atual e
 *   `data-muted` quando desatualizado/sem data. Dentro de um cartão que já é link (Acervo) ele é só
 *   visual — o detalhe completo fica no painel do exemplar, sem controle
 *   interativo aninhado.
 * - Valor sempre unitário. `now` vem do servidor (mesmo texto na hidratação).
 */
export function VariantPriceSummary({
  price,
  cardName,
  variantName,
  languageCode,
  now,
  interactive = false,
  appearance = "pill",
  glyphClassName,
  className,
}: {
  price: VariantPrice | null | undefined;
  cardName: string;
  variantName: string | null;
  languageCode: string | null;
  now: number;
  interactive?: boolean;
  appearance?: "pill" | "overlay";
  /** Classe do ícone de estado na aparência `overlay`. */
  glyphClassName?: string;
  className?: string;
}) {
  const state = priceState(price, now);
  const indicator = priceIndicator(state);
  if (!price || !indicator || price.brlAmount === null) return null;
  const text = formatBrl(price.brlAmount);
  if (!interactive) {
    return (
      <span className={cn(PRICE_PILL_BASE, className)} data-price-state={state} title={indicator.label}>
        <StateGlyph indicator={indicator} />
        {text}
      </span>
    );
  }
  return (
    <InteractivePill
      price={price}
      text={text}
      indicator={indicator}
      cardName={cardName}
      variantName={variantName}
      languageCode={languageCode}
      now={now}
      appearance={appearance}
      muted={isPriceMuted(state)}
      glyphClassName={glyphClassName}
      className={className}
    />
  );
}

/** Forma do ícone por estado — sinal não cromático (C1). Reexportado para o fichário. */
export { StateGlyph };

function InteractivePill({
  price,
  text,
  indicator,
  cardName,
  variantName,
  languageCode,
  now,
  appearance,
  muted,
  glyphClassName,
  className,
}: {
  price: VariantPrice;
  text: string;
  indicator: PriceIndicator;
  cardName: string;
  variantName: string | null;
  languageCode: string | null;
  now: number;
  appearance: "pill" | "overlay";
  muted: boolean;
  glyphClassName?: string;
  className?: string;
}) {
  const overlay = appearance === "overlay";
  const { anchorRef, contentRef, open, position, scheduleOpen, scheduleClose, openNow, toggle } = useAnchoredPopover<HTMLButtonElement, HTMLDivElement>();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const popoverId = `variant-price-${price.cardVariantId}`;
  return (
    <>
      <button
        ref={anchorRef}
        type="button"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? popoverId : undefined}
        aria-label={`Ver preço de referência — NM, ${text}${indicator.glyph === "current" ? "" : indicator.glyph === "stale" ? ", desatualizado" : ", sem data confirmada"}`}
        title={indicator.label}
        onMouseEnter={() => scheduleOpen()}
        onMouseLeave={() => scheduleClose()}
        onFocus={() => openNow()}
        onBlur={() => scheduleClose()}
        onClick={(event) => {
          event.stopPropagation();
          toggle();
        }}
        className={overlay ? className : cn(PRICE_PILL_BASE, PRICE_PILL_INTERACTIVE, className)}
        data-price-state={overlay ? priceState(price, now) : undefined}
        data-muted={overlay && muted ? "" : undefined}
      >
        {overlay ? (
          indicator.glyph !== "current" ? <StateGlyph indicator={indicator} className={glyphClassName} /> : null
        ) : (
          <StateGlyph indicator={indicator} />
        )}
        {text}
      </button>
      {mounted && open
        ? createPortal(
            <div
              ref={contentRef}
              id={popoverId}
              role="dialog"
              aria-modal="false"
              aria-label={`Preço de referência de ${cardName}`}
              onMouseEnter={openNow}
              onMouseLeave={() => scheduleClose()}
              style={{ position: "fixed", top: position?.top ?? -9999, left: position?.left ?? -9999, visibility: position ? "visible" : "hidden" }}
              className="z-50 w-[280px] max-w-[calc(100vw-16px)] rounded-lg border border-border bg-surface p-3.5 shadow-panel"
            >
              <VariantPriceDetails price={price} variantName={variantName} languageCode={languageCode} now={now} />
            </div>,
            document.body,
          )
        : null}
    </>
  );
}

/**
 * Conteúdo do detalhe — popover do pill e painel do exemplar no Acervo.
 * Mostra os cinco estados; sem preço, diz por quê (nunca R$ 0).
 * `readError`: a leitura de preço falhou (diferente de "sem preço").
 */
export function VariantPriceDetails({
  price,
  variantName,
  languageCode,
  now,
  readError = false,
  className,
}: {
  price: VariantPrice | null | undefined;
  variantName: string | null;
  languageCode: string | null;
  now: number;
  readError?: boolean;
  className?: string;
}) {
  if (readError) {
    return <p className={cn("text-[11px] text-muted-foreground", className)}>Não foi possível carregar o preço de referência agora.</p>;
  }
  const detail = priceDetail(price, { variantName, languageCode, now });
  if (detail.amount === null) {
    return <p className={cn("text-[11px] text-muted-foreground", className)}>{detail.headline}</p>;
  }
  const indicator = priceIndicator(detail.state);
  return (
    <div className={cn("space-y-3", className)} data-price-state={detail.state}>
      <div>
        <p className="flex items-center gap-1.5 text-xl font-bold leading-none text-foreground">
          {indicator && indicator.glyph !== "current" ? <StateGlyph indicator={indicator} className="h-4 w-4 shrink-0" /> : null}
          {detail.amount}
          {indicator && indicator.glyph !== "current" ? <span className="sr-only">, {indicator.label}</span> : null}
        </p>
        <p className="mt-1 text-[11px] font-medium leading-none text-muted-foreground">{detail.headline}</p>
      </div>
      <dl className="space-y-1.5 text-[11px] leading-none">
        {detail.facts.map((fact) => (
          <div key={fact.label} className="flex items-center justify-between gap-3">
            <dt className="text-muted-foreground">{fact.label}</dt>
            <dd className="text-right font-medium text-foreground">{fact.value}</dd>
          </div>
        ))}
      </dl>
      <ul className="space-y-1 border-t border-border pt-2.5 text-[11px] leading-snug text-muted-foreground">
        <li>{NM_REFERENCE_NOTE}</li>
        {detail.notes.map((note) => (
          <li key={note}>{note}</li>
        ))}
      </ul>
    </div>
  );
}
