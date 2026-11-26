"use client";

import { loadMoreSharedPokedexPositions } from "@/app/colecoes/compartilhada/[id]/modality-actions";
import { PokedexGrid } from "@/components/colecoes/colecoes/pokedex-grid";
import type { PokedexFilter, PokedexPosition } from "@/lib/colecoes/pokedex";

/**
 * V1-13 · E3-6 — a grade da Pokédex do titular, para o participante: mesma
 * carta representante ampliável, mesma arte da espécie e o mesmo "Mostrar
 * mais", alimentados pela 5324. Sem painel de vínculo, sem preços e sem
 * quantidade de exemplares. Só leitura.
 */
export function SharedPokedexGrid({
  collectionId,
  filter,
  initial,
  total,
  label,
}: {
  collectionId: string;
  filter: PokedexFilter;
  initial: PokedexPosition[];
  total: number;
  label: string;
}) {
  return (
    <PokedexGrid
      collectionId={collectionId}
      filter={filter}
      generation={null}
      initial={initial}
      total={total}
      label={label}
      linkable={false}
      loadMoreAction={loadMoreSharedPokedexPositions}
      showQuantities={false}
    />
  );
}
