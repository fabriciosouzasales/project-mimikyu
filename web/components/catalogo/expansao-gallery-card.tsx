"use client";

import { getGameAccentColor } from "@/lib/catalogo/game-accent";
import { cn } from "@/lib/utils";
import type { ExpansaoRow } from "@/lib/catalogo/queries";

/**
 * Card da galeria de Expansões — mesma linguagem visual do card de Card Set
 * (`card-set-gallery-card.tsx`): logo/iniciais em destaque, selo de cor do
 * Jogo, nome, código e uma contagem do que a entidade agrupa. Adaptado à
 * entidade Expansion, que "não reinventa a UX" pede explicitamente:
 *
 * - Sem logo: `logo_storage_path` só existe em `card_set`, não em
 *   `expansion` — usa sempre o mesmo bloco de iniciais que Card Set usa
 *   como reserva, nunca uma imagem.
 * - Contagem de Card Sets em vez de Cartas (o que uma Expansão de fato
 *   agrupa).
 * - Sem página de detalhe própria para Expansion — clicar abre o Dialog de
 *   edição já existente (`EditExpansionDialog`), em vez de navegar para uma
 *   rota que não existe.
 */
function getInitials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]?.toUpperCase() ?? "")
    .join("");
}

export function ExpansaoGalleryCard({
  expansao,
  highlighted,
  onEdit,
}: {
  expansao: ExpansaoRow;
  highlighted: boolean;
  onEdit: (id: string) => void;
}) {
  const accent = getGameAccentColor(expansao.gameCode || expansao.gameName);

  return (
    <button
      type="button"
      onClick={() => onEdit(expansao.id)}
      aria-label={`Editar ${expansao.name}`}
      className={cn(
        "group flex flex-col overflow-hidden rounded-lg border border-border bg-surface text-left transition-colors hover:border-primary/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        highlighted && "border-primary/40 bg-primary/5",
      )}
    >
      <div className="flex aspect-square items-center justify-center bg-surface-muted">
        <span className="font-heading text-2xl font-medium text-muted-foreground">{getInitials(expansao.name)}</span>
      </div>
      <div className="space-y-1 p-3">
        <div className="flex items-center gap-1.5">
          <span className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: accent }} aria-hidden="true" />
          <span className="truncate text-[11px] text-muted-foreground">{expansao.gameName}</span>
        </div>
        <p className="truncate text-sm font-medium text-foreground">{expansao.name}</p>
        <p className="text-xs text-muted-foreground">
          {expansao.code} · {expansao.totalCardSets} {expansao.totalCardSets === 1 ? "card set" : "card sets"}
        </p>
      </div>
    </button>
  );
}
