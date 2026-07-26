import Link from "next/link";
import { ChevronRight } from "lucide-react";
import { SetTypeTag } from "@/components/catalogo/set-type-tag";
import { StateBadge } from "@/components/catalogo/state-badge";
import type { CardSetOverviewRow } from "@/lib/catalogo/queries";

/**
 * Linha navegável (ajuste pedido por Fabrício) — cada Card Set leva ao seu
 * detalhe em /catalogo/card-sets/{code}. Densidade ajustada contra a
 * referência real do Supabase (2026-07-26, print da lista de buckets):
 * linhas bem mais compactas que a primeira versão, identificador principal
 * em `primary` (mesmo papel do azul-link do Supabase, adaptado à nossa
 * cor de marca) e chevron sempre visível, discreto, em vez de só no hover.
 */
export function CardSetsTable({ cardSets }: { cardSets: CardSetOverviewRow[] }) {
  if (cardSets.length === 0) {
    return (
      <div className="flex flex-col items-center gap-1 py-10 text-center">
        <p className="text-sm text-foreground">Nenhum Card Set catalogado ainda</p>
        <p className="text-xs text-muted-foreground">Os Card Sets aparecem aqui assim que forem cadastrados.</p>
      </div>
    );
  }

  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="border-b border-border text-left text-[11px] font-normal uppercase tracking-wide text-muted-foreground">
          <th className="py-1.5 pr-3 font-normal">Card Set</th>
          <th className="py-1.5 pr-3 font-normal">Tipo</th>
          <th className="py-1.5 pr-3 font-normal">Cartas</th>
          <th className="py-1.5 pr-3 font-normal">Imagens</th>
          <th className="py-1.5 pr-3 font-normal">Logo</th>
          <th className="py-1.5" />
        </tr>
      </thead>
      <tbody>
        {cardSets.map((set) => (
          <tr key={set.code} className="border-b border-border/60 last:border-b-0">
            <td className="py-2 pr-3">
              <Link
                href={`/catalogo/card-sets/${set.code}`}
                className="inline-flex flex-col leading-tight focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
                <span className="text-primary hover:underline">{set.name}</span>
                <span className="text-[11px] text-muted-foreground">{set.code}</span>
              </Link>
            </td>
            <td className="py-2 pr-3">
              <SetTypeTag setType={set.setType} />
            </td>
            <td className="py-2 pr-3 text-muted-foreground">
              {set.cardsCatalogados}/{set.totalSetSize}
            </td>
            <td className="py-2 pr-3">
              {set.temImagensCompletas ? (
                <StateBadge tone="success">Completas</StateBadge>
              ) : (
                <StateBadge tone="warning">Pendente</StateBadge>
              )}
            </td>
            <td className="py-2 pr-3 text-muted-foreground">{set.temLogo ? "Cadastrada" : "—"}</td>
            <td className="py-2 text-right">
              <Link
                href={`/catalogo/card-sets/${set.code}`}
                aria-label={`Ver detalhe de ${set.name}`}
                className="inline-flex text-muted-foreground/50 hover:text-muted-foreground focus-visible:outline-none"
              >
                <ChevronRight className="h-3.5 w-3.5" />
              </Link>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
