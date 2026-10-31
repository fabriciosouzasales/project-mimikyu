import { CalendarOff, CircleDollarSign, History, type LucideIcon } from "lucide-react";
import type { PriceIndicator } from "@/lib/pricing/variant-pricing";
import { PRICE_PILL_ICON } from "./price-pill";

/**
 * Forma do ícone por estado do preço (V1-09, C1) — sinal não cromático.
 * Sem estado de cliente: usado tanto pelos componentes de servidor (Acervo)
 * quanto pelos de cliente (pill interativo, fichário).
 */
const GLYPHS: Record<PriceIndicator["glyph"], LucideIcon> = {
  current: CircleDollarSign,
  stale: History,
  unknown: CalendarOff,
};

export function StateGlyph({ indicator, className, style }: { indicator: PriceIndicator; className?: string; style?: React.CSSProperties }) {
  const Icon = GLYPHS[indicator.glyph];
  return <Icon className={className ?? PRICE_PILL_ICON} style={style} aria-hidden="true" data-price-glyph={indicator.glyph} />;
}
