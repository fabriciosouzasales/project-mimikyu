"use client";

import { ChevronDown } from "lucide-react";
import { useRouter } from "next/navigation";
import type { ChangeEvent } from "react";
import { cn } from "@/lib/utils";

/**
 * Seletor de Coleção dos relatórios "Checklist" e "Resumo" — os únicos, dos
 * 6 da Central de Relatórios, que mostram o dado de UMA Coleção por vez (os
 * outros 4 já são tabelas cruzando todas as Coleções, sem seletor). Mesmo
 * padrão visual de `CatalogoFilterSelect` (native `<select>`, URL-driven via
 * `?cardSet=`), `print:hidden` — o relatório impresso já mostra qual
 * Coleção é no próprio título, não precisa do controle de troca.
 */
export function RelatorioColecaoSeletor({
  cardSets,
  selectedCode,
  basePath,
}: {
  cardSets: { id: string; code: string; name: string }[];
  selectedCode?: string;
  basePath: string;
}) {
  const router = useRouter();

  function handleChange(event: ChangeEvent<HTMLSelectElement>) {
    const code = event.target.value;
    router.push(code ? `${basePath}?cardSet=${code}` : basePath);
  }

  return (
    <div className="relative w-full max-w-sm print:hidden">
      <select
        value={selectedCode ?? ""}
        onChange={handleChange}
        aria-label="Selecionar Coleção"
        className={cn(
          "h-10 w-full appearance-none rounded-md border border-input bg-surface py-1 pl-3 pr-8 text-sm shadow-subtle transition-colors",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
        )}
      >
        <option value="">Selecione uma Coleção...</option>
        {cardSets.map((cardSet) => (
          <option key={cardSet.id} value={cardSet.code}>
            {cardSet.code} — {cardSet.name}
          </option>
        ))}
      </select>
      <ChevronDown
        className="pointer-events-none absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground"
        aria-hidden="true"
      />
    </div>
  );
}
