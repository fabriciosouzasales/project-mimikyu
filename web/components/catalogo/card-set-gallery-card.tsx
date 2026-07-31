import Link from "next/link";
import { getGameAccentColor } from "@/lib/catalogo/game-accent";
import type { CardSetWithLogo } from "@/app/catalogo/card-sets/catalogo-actions";

/**
 * Card da galeria — spec aprovada 2026-07-31. Nível 1 (arte/logo) sempre
 * maior que o texto; sem logo cadastrada, iniciais do nome substituem a
 * arte (nunca um ícone genérico solto) — decisão tomada aqui mesmo, sem
 * reabrir discussão de UX, para o caso não coberto explicitamente pela
 * especificação. Sem data de criação/atualização nem qualquer metadado
 * administrativo — decisão já aprovada (Nível 4, quase invisível).
 */
function getInitials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]?.toUpperCase() ?? "")
    .join("");
}

export function CardSetGalleryCard({ cardSet }: { cardSet: CardSetWithLogo }) {
  const accent = getGameAccentColor(cardSet.gameCode || cardSet.gameName);

  return (
    <Link
      href={`/catalogo/card-sets/${cardSet.code}`}
      className="group flex flex-col overflow-hidden rounded-lg border border-border bg-surface transition-colors hover:border-primary/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
    >
      <div className="flex aspect-square items-center justify-center bg-surface-muted">
        {cardSet.logoUrl ? (
          // Signed URL expira e é gerada por requisição — next/image exigiria
          // configurar domínio remoto para uma URL que nem é estável; <img>
          // simples evita esse acoplamento sem perder o essencial (a imagem
          // aparece). Ver relatório de decisões técnicas.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={cardSet.logoUrl} alt="" className="h-full w-full object-contain p-4" />
        ) : (
          <span className="font-heading text-2xl font-medium text-muted-foreground">
            {getInitials(cardSet.name)}
          </span>
        )}
      </div>
      <div className="space-y-1 p-3">
        <div className="flex items-center gap-1.5">
          <span className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: accent }} aria-hidden="true" />
          <span className="truncate text-[11px] text-muted-foreground">{cardSet.gameName}</span>
        </div>
        <p className="truncate text-sm font-medium text-foreground">{cardSet.name}</p>
        <p className="text-xs text-muted-foreground">
          {cardSet.code} · {cardSet.cardsCatalogados} {cardSet.cardsCatalogados === 1 ? "carta" : "cartas"}
        </p>
      </div>
    </Link>
  );
}
