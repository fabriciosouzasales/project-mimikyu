"use client";

import { type BinderHeader, binderRegisterContext } from "@/lib/colecoes/binder";
import type { BinderFinish } from "@/lib/colecoes/binder-finish";
import { mayHaveSpeciesReferences } from "@/lib/colecoes/binder-species";
import { mayHaveCatalogNovelties } from "@/lib/colecoes/binder-catalog";
import { collectionHref } from "@/lib/colecoes/colecoes";
import { BinderOverlayShell } from "./binder-overlay-shell";
import { BinderWorkspace } from "./binder-workspace";

/**
 * Fichário aberto SOBRE a página da coleção (P2-B-SPIKE-RECOVERY-01): sem
 * navegar, a coleção fica desfocada e escurecida ao fundo e volta exatamente
 * como estava ao fechar.
 *
 * A casca do diálogo (véu, `inert`, foco preso, rolagem travada, entrada e
 * saída) é `BinderOverlayShell`, a mesma do participante (V1-12); aqui só a
 * área de trabalho do titular. Esc fecha em camadas (a área de trabalho
 * desfaz antes: carta escolhida, Bandeja, seleção).
 */
export function BinderOverlay({
  collectionId,
  collectionName,
  header,
  finish,
  cardSet = null,
  onClose,
}: {
  collectionId: string;
  collectionName: string;
  header: BinderHeader;
  /** Acabamento da capa fechada desta coleção (moldura do fichário aberto). */
  finish?: BinderFinish;
  /** Set da coleção (coleções de Set): referência do cadastro pelo fichário (V1-06). */
  cardSet?: { code: string; name: string } | null;
  onClose: () => void;
}) {
  const columns = header.columns;
  const rows = header.rows;
  if (!columns || !rows) return null;

  return (
    <BinderOverlayShell labelledBy="fichario-titulo" onClose={onClose}>
      {(close) => (
        <BinderWorkspace
          variant="overlay"
          collectionId={collectionId}
          collectionName={collectionName}
          identity={header.identity ?? null}
          finish={finish}
          speciesReferences={mayHaveSpeciesReferences(header)}
          catalogNovelties={mayHaveCatalogNovelties(header)}
          columns={columns}
          rows={rows}
          totalPages={header.pageCount}
          layoutId={header.layoutId}
          filledCount={header.filledCount}
          role={header.role}
          ownerCollectionId={header.ownerCollectionId}
          ownerCollectionName={header.ownerCollectionName}
          participantCount={header.participantCount}
          ownUnplacedCount={header.ownUnplacedCount}
          availableCount={header.availableCount}
          editable={header.editable}
          register={binderRegisterContext(header, cardSet)}
          initialAnchor={1}
          initialPages={[]}
          backHref={collectionHref(collectionId)}
          onClose={close}
        />
      )}
    </BinderOverlayShell>
  );
}
