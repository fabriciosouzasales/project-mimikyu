"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useMemo } from "react";
import { Select } from "@/components/ui/select";
import type { CatalogoCardSetRow, ExpansaoRow } from "@/lib/catalogo/queries";

/**
 * Seletor Expansão → Set de "Valor por Set" (Bloco 5, migration 3943) —
 * mesma hierarquia de `cartas-gallery.tsx`, mas simplificada: aqui não
 * existe "Selecionar Todos" navegando para o Set mais recente do escopo
 * (decisão daquela tela, própria de navegação/browsing). Esta é uma tela
 * analítica — trocar Expansão só restringe as opções de Set abaixo e limpa
 * a escolha de Set (nunca escolhe um Set no lugar do usuário); o relatório
 * em si só aparece depois que um Set é escolhido explicitamente.
 *
 * Sem seletor de Jogo (removido em 2026-08-23, decisão de produto: o MMKYU
 * Collector contempla só Pokémon TCG no lançamento) — `expansions` e
 * `cardSets` já chegam pré-filtrados para Pokémon TCG por `game.code`
 * (`app/pricing/relatorios/valor-por-set/page.tsx`, via `getExpansoes`/
 * `getCardSetsForCartas`), então não há cascata de Jogo para fazer aqui.
 */
export function ValorPorSetSelector({
  expansions,
  cardSets,
  selectedExpansionId,
  selectedCardSetId,
}: {
  expansions: ExpansaoRow[];
  cardSets: CatalogoCardSetRow[];
  selectedExpansionId: string;
  selectedCardSetId: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const cardSetOptions = useMemo(() => {
    if (!selectedExpansionId) return cardSets;
    return cardSets.filter((set) => set.expansionId === selectedExpansionId);
  }, [cardSets, selectedExpansionId]);

  function pushParams(next: Record<string, string | undefined>) {
    const params = new URLSearchParams(searchParams.toString());
    for (const [key, value] of Object.entries(next)) {
      if (value) params.set(key, value);
      else params.delete(key);
    }
    router.push(`${pathname}?${params.toString()}`);
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Select
        value={selectedExpansionId}
        onChange={(event) => pushParams({ expansion: event.target.value || undefined, set: undefined })}
        className="h-9 w-auto min-w-[9rem] max-w-[14rem] bg-surface-muted px-3 text-xs"
        aria-label="Filtrar por Expansão"
      >
        <option value="">Selecionar Expansão</option>
        {expansions.map((expansion) => (
          <option key={expansion.id} value={expansion.id}>
            {expansion.name}
          </option>
        ))}
      </Select>

      <Select
        value={selectedCardSetId}
        onChange={(event) => pushParams({ set: event.target.value || undefined })}
        className="h-9 w-auto min-w-[10rem] max-w-[16rem] bg-surface-muted px-3 text-xs"
        aria-label="Filtrar por Set"
      >
        <option value="">Selecionar Set</option>
        {cardSetOptions.map((set) => (
          <option key={set.id} value={set.id}>
            {set.name} ({set.code})
          </option>
        ))}
      </Select>
    </div>
  );
}
