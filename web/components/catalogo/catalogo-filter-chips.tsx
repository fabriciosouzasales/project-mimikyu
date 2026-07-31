import Link from "next/link";
import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import type { ExpansaoRow, GameOption } from "@/lib/catalogo/queries";

/**
 * Filtros de Jogo/Expansão como faceta, nunca portão — spec aprovada
 * 2026-07-31. Renderizados como `Link` simples (Server Component, sem
 * necessidade de estado no cliente): clicar refina o conteúdo abaixo via
 * navegação normal de rota, mesmo padrão já usado pelo filtro `?game=` de
 * /catalogo/expansoes. Chips de Expansão só aparecem depois que um Jogo é
 * escolhido — é refinamento progressivo, nunca hierarquia obrigatória.
 */
function buildHref(params: { q?: string; game?: string; expansion?: string }): string {
  const search = new URLSearchParams();
  if (params.q) search.set("q", params.q);
  if (params.game) search.set("game", params.game);
  if (params.expansion) search.set("expansion", params.expansion);
  const qs = search.toString();
  return qs ? `/catalogo/card-sets?${qs}` : "/catalogo/card-sets";
}

function Chip({ href, active, children }: { href: string; active: boolean; children: ReactNode }) {
  return (
    <Link
      href={href}
      className={cn(
        "inline-flex shrink-0 items-center whitespace-nowrap rounded-full border px-3 py-1 text-xs font-medium transition-colors",
        active
          ? "border-primary/40 bg-primary/5 text-primary"
          : "border-border text-muted-foreground hover:bg-surface-muted hover:text-foreground",
      )}
    >
      {children}
    </Link>
  );
}

export function CatalogoFilterChips({
  jogos,
  expansoesDoJogo,
  gameCode,
  expansionCode,
  query,
}: {
  jogos: GameOption[];
  expansoesDoJogo: ExpansaoRow[];
  gameCode?: string;
  expansionCode?: string;
  query: string;
}) {
  return (
    <div className="space-y-2">
      <div className="flex gap-2 overflow-x-auto pb-0.5">
        <Chip href={buildHref({ q: query })} active={!gameCode}>
          Todos
        </Chip>
        {jogos.map((jogo) => (
          <Chip key={jogo.id} href={buildHref({ q: query, game: jogo.code })} active={gameCode === jogo.code}>
            {jogo.name}
          </Chip>
        ))}
      </div>

      {gameCode && expansoesDoJogo.length > 0 && (
        <div className="flex gap-2 overflow-x-auto pb-0.5">
          <Chip href={buildHref({ q: query, game: gameCode })} active={!expansionCode}>
            Todas as expansões
          </Chip>
          {expansoesDoJogo.map((expansao) => (
            <Chip
              key={expansao.id}
              href={buildHref({ q: query, game: gameCode, expansion: expansao.code })}
              active={expansionCode === expansao.code}
            >
              {expansao.name}
            </Chip>
          ))}
        </div>
      )}
    </div>
  );
}
