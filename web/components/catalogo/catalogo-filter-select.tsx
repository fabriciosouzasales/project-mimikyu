"use client";

import { ChevronDown } from "lucide-react";
import { useRouter } from "next/navigation";
import type { ChangeEvent, ReactNode } from "react";
import { Select } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import type { ExpansaoRow, GameOption } from "@/lib/catalogo/queries";

/**
 * Filtro de Jogo/Expansão em dropdown suspenso ao lado da busca — substitui
 * os chips abaixo da busca (`CatalogoFilterChips`, agora sem uso) por
 * decisão explícita (2026-07-31), a partir de referência visual anexada
 * pelo usuário (busca + dropdown único ao lado, padrão comum de tabelas
 * administrativas). Continua sendo faceta, nunca portão: escolher uma
 * opção apenas refina o conteúdo abaixo via navegação de URL — mesmo
 * parâmetro `?game=`/`?expansion=` que os chips já usavam.
 *
 * Compartilhado entre Catálogo (Card Sets — dois dropdowns lado a lado:
 * Jogo e, depois de escolher um Jogo, Expansão daquele Jogo) e Expansões
 * (um único dropdown, Jogo — `expansoesDoJogo` sempre `[]` naquela tela,
 * já que uma Expansão não filtra a si mesma; o segundo dropdown some
 * automaticamente, mesma condição que os chips antigos já usavam).
 */
function buildHref(basePath: string, params: { q?: string; game?: string; expansion?: string }): string {
  const search = new URLSearchParams();
  if (params.q) search.set("q", params.q);
  if (params.game) search.set("game", params.game);
  if (params.expansion) search.set("expansion", params.expansion);
  const qs = search.toString();
  return qs ? `${basePath}?${qs}` : basePath;
}

function FilterSelect({
  value,
  onChange,
  disabled,
  ariaLabel,
  className,
  children,
}: {
  value: string;
  onChange: (event: ChangeEvent<HTMLSelectElement>) => void;
  disabled?: boolean;
  ariaLabel: string;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div className="relative shrink-0">
      {/* `h-10`/`min-w-[9.5rem]`/`appearance-none`/padding: variante legítima
          de filtro compacto com seta própria — surface/borda/radius/foco/
          disabled vêm do `Select` compartilhado (2026-08-16, consolidação
          de formulários), só a densidade/affordance do dropdown é local. */}
      <Select
        value={value}
        onChange={onChange}
        disabled={disabled}
        aria-label={ariaLabel}
        className={cn("h-10 min-w-[9.5rem] appearance-none py-1 pl-3 pr-8", className)}
      >
        {children}
      </Select>
      <ChevronDown
        className="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground"
        aria-hidden="true"
      />
    </div>
  );
}

export function CatalogoFilterSelect({
  jogos,
  expansoesDoJogo,
  gameCode,
  expansionCode,
  query,
  basePath = "/catalogo/card-sets",
  className,
}: {
  jogos: GameOption[];
  expansoesDoJogo: ExpansaoRow[];
  gameCode?: string;
  expansionCode?: string;
  query: string;
  basePath?: string;
  /** Repassado a cada `Select` — usado por Expansões para bater h-9/bg-surface-muted com o padrão de Jogos. */
  className?: string;
}) {
  const router = useRouter();

  function handleGameChange(event: ChangeEvent<HTMLSelectElement>) {
    const next = event.target.value || undefined;
    router.push(buildHref(basePath, { q: query, game: next }));
  }

  function handleExpansionChange(event: ChangeEvent<HTMLSelectElement>) {
    const next = event.target.value || undefined;
    router.push(buildHref(basePath, { q: query, game: gameCode, expansion: next }));
  }

  const showExpansionFilter = Boolean(gameCode) && expansoesDoJogo.length > 0;

  return (
    <div className="flex gap-2">
      <FilterSelect
        value={gameCode ?? ""}
        onChange={handleGameChange}
        ariaLabel="Filtrar por Jogo"
        className={className}
      >
        <option value="">Todos os Jogos</option>
        {jogos.map((jogo) => (
          <option key={jogo.id} value={jogo.code}>
            {jogo.name}
          </option>
        ))}
      </FilterSelect>

      {showExpansionFilter && (
        <FilterSelect
          value={expansionCode ?? ""}
          onChange={handleExpansionChange}
          ariaLabel="Filtrar por Expansão"
          className={className}
        >
          <option value="">Todas as Expansões</option>
          {expansoesDoJogo.map((expansao) => (
            <option key={expansao.id} value={expansao.code}>
              {expansao.name}
            </option>
          ))}
        </FilterSelect>
      )}
    </div>
  );
}
