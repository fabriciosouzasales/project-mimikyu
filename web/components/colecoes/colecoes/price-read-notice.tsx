import { Info } from "lucide-react";
import { type VariantPricesStatus, priceReadNoticeText } from "@/lib/pricing/variant-pricing";

/**
 * PRICING TIMEOUT CORRECTION-01 — aviso discreto quando a leitura dos preços de
 * referência da página não foi completa (falha temporária, nunca "sem
 * cotação"). Mesmo visual da nota informativa da Pokédex; anunciado com
 * cortesia (`role="status"`). Nada é renderizado com leitura completa.
 */
export function PriceReadNotice({ status, className = "" }: { status: VariantPricesStatus | null | undefined; className?: string }) {
  const text = priceReadNoticeText(status);
  if (!text) return null;
  return (
    <p
      role="status"
      data-price-read={status}
      className={`flex items-start gap-2.5 rounded-xl border border-border bg-surface px-3.5 py-3 text-[0.8125rem] leading-[1.45] text-muted-foreground ${className}`}
    >
      <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
      {text}
    </p>
  );
}
