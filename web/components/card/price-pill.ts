/**
 * Pill de preço do Design System MMKYU — padrão do Catálogo Editorial (P12,
 * referência Genesect EX #004/030): mesma altura, borda, fundo, raio e
 * espaçamento do indicador de variantes. Compartilhado entre o Catálogo
 * (`CardPriceSummary`, por carta) e a Collection (`VariantPriceSummary`, por
 * variante — V1-09). Mudar aqui muda os dois: é o mesmo componente visual.
 */
export const PRICE_PILL_BASE =
  "inline-flex shrink-0 items-center gap-0.5 whitespace-nowrap rounded-full bg-surface-muted px-1.5 py-0.5 text-[10px] font-semibold leading-none text-foreground";

/** Estados de interação quando o pill abre o detalhe (botão). */
export const PRICE_PILL_INTERACTIVE = "hover:bg-surface-muted/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring";

/** Ícone do pill (`CircleDollarSign`). */
export const PRICE_PILL_ICON = "h-2.5 w-2.5 shrink-0";
