"use client";

import { useEffect, useState } from "react";
import { ArrowRight, BookOpen, Eye, Pencil } from "lucide-react";
import { BINDER_OPEN_EVENT, Glyph } from "@/components/colecoes/fichario/binder-entry";
import entryStyles from "@/components/colecoes/fichario/binder-entry.module.css";
import { BinderOverlayShell } from "@/components/colecoes/fichario/binder-overlay-shell";
import { formatCount } from "@/lib/colecoes/acervo";
import { modelLabel } from "@/lib/colecoes/binder";
import type { BinderFinish } from "@/lib/colecoes/binder-finish";
import { type MemberRole, ROLE_LABEL, type SharedBinderIdentity } from "@/lib/colecoes/sharing";
import { SharedBinderWorkspace } from "./shared-binder-workspace";

/**
 * Entrada do Fichário Digital na coleção compartilhada (V1-12 SHARED
 * EXPERIENCE-01) — mesma peça visual da entrada do titular
 * (`binder-entry.module.css`, miniatura da grade, "Abrir o fichário") e a
 * mesma abertura: o fichário abre SOBRE a coleção, na casca imersiva
 * compartilhada (`BinderOverlayShell`), e fecha de volta a ela intacta.
 *
 * Dentro, a MESMA camada visual do fichário do titular em só leitura
 * (`SharedBinderWorkspace`: moldura, couro, contracapa, bolsos): páginas lidas sob
 * demanda pela porta do participante (5316 → núcleo mascarado 5315). Nenhum
 * controle de edição, nenhuma leitura privada do titular. A capa do hero
 * (`BinderCoverLink`) dispara o mesmo evento e abre o mesmo fichário.
 */
export function SharedBinderEntry({
  collectionId,
  collectionName,
  ownerDisplayName,
  finish,
  binder,
  role = null,
  speciesEnabled = false,
  editorEnabled = false,
  completionPolicy = null,
}: {
  collectionId: string;
  collectionName: string;
  ownerDisplayName: string;
  finish: BinderFinish;
  /** V1-13 · E3-1: papel do próprio participante (5312); `null` = sem papel conhecido (texto de sempre). */
  role?: MemberRole | null;
  binder: { columns: number; rows: number; pageCount: number; ownFilled: number; identity: SharedBinderIdentity | null };
  /** V1-13 · E3-6 / F2: páginas pela 5393 (referências de espécie), decidido no servidor da página. */
  speciesEnabled?: boolean;
  /**
   * V1-13 · E4 (D-E4-1): EDITOR com a organização disponível (D1 + papel + coleção ativa, decidido no servidor
   * da página) organiza DENTRO da sobreposição, como o titular. Não autoriza nada: cada escrita é do banco.
   */
  editorEnabled?: boolean;
  /** Objetivo da coleção (reservas, organização automática e novidades dependem dele), como na rota /fichario. */
  completionPolicy?: string | null;
}) {
  const [open, setOpen] = useState(false);
  const ready = binder.pageCount > 0;

  useEffect(() => {
    if (!ready) return;
    const onOpen = (event: Event) => {
      if ((event as CustomEvent<string>).detail === collectionId) setOpen(true);
    };
    window.addEventListener(BINDER_OPEN_EVENT, onOpen);
    return () => window.removeEventListener(BINDER_OPEN_EVENT, onOpen);
  }, [collectionId, ready]);

  if (!ready) {
    return (
      <div className={entryStyles.entry} data-state="info" role="note">
        <Glyph columns={binder.columns} rows={binder.rows} />
        <span className={entryStyles.text}>
          <span className={entryStyles.title}>Fichário digital</span>
          <span className={entryStyles.meta}>O titular ainda não montou as páginas deste fichário.</span>
        </span>
      </div>
    );
  }

  return (
    <>
      <button type="button" className={entryStyles.entry} data-state="ready" onClick={() => setOpen(true)} aria-haspopup="dialog">
        <Glyph columns={binder.columns} rows={binder.rows} filled />
        <span className={entryStyles.text}>
          <span className={entryStyles.title}>
            Fichário digital
            <span className={entryStyles.shared}>
              {role === "EDITOR" ? <Pencil aria-hidden="true" /> : <Eye aria-hidden="true" />}
              {role ? ROLE_LABEL[role].toLowerCase() : "somente visualização"}
            </span>
          </span>
          <span className={entryStyles.meta}>
            {modelLabel(binder.columns, binder.rows)} · {formatCount(binder.pageCount)} {binder.pageCount === 1 ? "página" : "páginas"} ·{" "}
            {formatCount(binder.ownFilled)} {binder.ownFilled === 1 ? "carta desta coleção nos bolsos" : "cartas desta coleção nos bolsos"}
          </span>
        </span>
        <span className={entryStyles.cta}>
          <BookOpen aria-hidden="true" />
          {editorEnabled ? "Organizar o fichário" : "Abrir o fichário"}
          <ArrowRight className={entryStyles.arrow} aria-hidden="true" />
        </span>
      </button>
      {open ? (
        <BinderOverlayShell labelledBy="fichario-compartilhado-titulo" onClose={() => setOpen(false)}>
          {(close) => (
            <SharedBinderWorkspace
              variant="overlay"
              titleId="fichario-compartilhado-titulo"
              collectionId={collectionId}
              collectionName={collectionName}
              ownerDisplayName={ownerDisplayName}
              finish={finish}
              identity={binder.identity}
              columns={binder.columns}
              rows={binder.rows}
              pageCount={binder.pageCount}
              ownFilled={binder.ownFilled}
              memberRole={role}
              speciesEnabled={speciesEnabled}
              editorEnabled={editorEnabled}
              completionPolicy={completionPolicy}
              onClose={close}
            />
          )}
        </BinderOverlayShell>
      ) : null}
    </>
  );
}
