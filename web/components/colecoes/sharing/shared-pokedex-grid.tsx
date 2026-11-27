"use client";

import { loadMoreSharedPokedexPositions } from "@/app/colecoes/compartilhada/[id]/modality-actions";
import { PokedexGrid } from "@/components/colecoes/colecoes/pokedex-grid";
import type { PokedexFilter, PokedexPosition } from "@/lib/colecoes/pokedex";
import { SharedPokedexEditorPanel } from "./shared-pokedex-editor-panel";

/**
 * V1-13 · E3-6 — a grade da Pokédex do titular, para o participante: mesma
 * carta representante ampliável, mesma arte da espécie e o mesmo "Mostrar
 * mais", alimentados pela 5324. Sem preços e sem quantidade de exemplares.
 *
 * F3-2: com `editable` (configuração D1 + EDITOR + coleção ativa, decidido no
 * servidor da página), tocar um Pokémon abre o painel colaborativo (5391/5392).
 * Sem `editable` (VIEWER ou edição indisponível): só leitura, como antes. O
 * botão visível não autoriza nada — cada leitura e escrita é decidida no banco.
 */
export function SharedPokedexGrid({
  collectionId,
  filter,
  initial,
  total,
  label,
  editable = false,
}: {
  collectionId: string;
  filter: PokedexFilter;
  initial: PokedexPosition[];
  total: number;
  label: string;
  editable?: boolean;
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
      renderPanel={
        editable
          ? (position, onClose) => <SharedPokedexEditorPanel collectionId={collectionId} position={position} onClose={() => onClose()} />
          : null
      }
    />
  );
}
