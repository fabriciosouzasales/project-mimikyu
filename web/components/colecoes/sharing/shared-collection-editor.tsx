"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useState } from "react";
import { PenLine, X } from "lucide-react";
import { editorSaveCollectionText, editorSaveCoverCode, editorSaveCoverFinish } from "@/app/colecoes/compartilhada/[id]/actions";
import { IdentityNameForm, type IdentitySave } from "@/components/colecoes/colecoes/collection-identity-settings";
import { CoverFinishPicker } from "@/components/colecoes/colecoes/cover-finish-picker";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import type { BinderFinish } from "@/lib/colecoes/binder-finish";
import { type MetadataFailure, metadataFailureMessage, metadataFailureRechecks } from "@/lib/colecoes/editor-collection-metadata";
import acervoStyles from "../acervo/acervo.module.css";
import addStyles from "../acervo/acervo-add.module.css";
import manageStyles from "../colecoes/collection-manage.module.css";
import styles from "./share.module.css";

type Fail = { ok: false; message: string; reload: boolean };

function toFail(reason: MetadataFailure): Fail {
  return { ok: false, message: metadataFailureMessage(reason), reload: metadataFailureRechecks(reason) };
}

/**
 * V1-13 · E3-3 — "Editar informações" da coleção compartilhada, só para o
 * EDITOR (configuração D-E3-1 ligada + papel EDITOR + coleção ativa, decidido
 * no servidor da página). Reaproveita os formulários de identidade do titular
 * com a gravação do EDITOR (5376): nome, descrição, código da placa (coleção
 * livre/Pokédex) e acabamento da capa. Nada estrutural: Set, escopo, política,
 * modalidade, visibilidade, arquivamento e participantes não aparecem aqui.
 *
 * Cada gravação confere antes se o valor atual ainda é o que a tela mostrou
 * (releitura do participante) e recusa se mudou; depois de confirmada, a
 * página é relida. Nada otimista, nenhuma repetição automática.
 */
export function SharedCollectionEditButton({
  collectionId,
  name,
  description,
  coverFinish,
  finish,
  coverCode,
  codeApplies,
}: {
  collectionId: string;
  name: string;
  description: string | null;
  /** Acabamento gravado (pode ser nulo: a capa usa o padrão derivado). */
  coverFinish: string | null;
  /** Acabamento exibido (gravado ou derivado). */
  finish: BinderFinish;
  coverCode: string | null;
  /** Só coleção livre ou Pokédex tem código na placa. */
  codeApplies: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const restoreFocus = useRestoreFocus();
  const baseline = { name, description };

  const save: IdentitySave = {
    text: async (nextName, nextDescription) => {
      const r = await editorSaveCollectionText({ collectionId, name: nextName, description: nextDescription, baseline }).catch(() => null);
      if (!r) return toFail("uncertain");
      return r.ok ? { ok: true } : toFail(r.reason);
    },
    code: codeApplies
      ? async (code) => {
          const r = await editorSaveCoverCode({ collectionId, code, baseline: coverCode }).catch(() => null);
          if (!r) return toFail("uncertain");
          return r.ok ? { ok: true } : toFail(r.reason);
        }
      : undefined,
  };

  const saveFinish = async (next: BinderFinish) => {
    const r = await editorSaveCoverFinish({ collectionId, finish: next, baseline: coverFinish }).catch(() => null);
    if (!r) return toFail("uncertain");
    return r.ok ? ({ ok: true } as const) : toFail(r.reason);
  };

  return (
    <>
      <button type="button" className={manageStyles.settingsButton} onClick={() => setOpen(true)} aria-haspopup="dialog">
        <PenLine className="h-4 w-4" aria-hidden="true" />
        <span>Editar informações</span>
      </button>
      {open ? (
        <DialogPrimitive.Root open onOpenChange={(next) => !next && !busy && setOpen(false)}>
          <DialogPrimitive.Portal>
            <DialogPrimitive.Overlay className={acervoStyles.overlay} />
            <DialogPrimitive.Content
              className={`${acervoStyles.drawer} ${manageStyles.panel}`}
              aria-describedby={undefined}
              onEscapeKeyDown={(event) => busy && event.preventDefault()}
              onPointerDownOutside={(event) => busy && event.preventDefault()}
              onCloseAutoFocus={restoreFocus}
            >
              <div className={acervoStyles.drawerHeader}>
                <div className="min-w-0">
                  <DialogPrimitive.Title className={addStyles.panelTitle}>Editar informações</DialogPrimitive.Title>
                  <p className="truncate text-xs text-muted-foreground">{name}</p>
                </div>
                <DialogPrimitive.Close
                  disabled={busy}
                  className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
                  aria-label="Fechar"
                >
                  <X className="h-4 w-4" aria-hidden="true" />
                </DialogPrimitive.Close>
              </div>
              <div className={manageStyles.body}>
                <p className={styles.lead}>
                  Como quem pode organizar, você edita o nome, a descrição{codeApplies ? ", o código da capa" : ""} e a cor da capa. O Set, o objetivo, a
                  visibilidade e quem participa continuam com o titular.
                </p>
                <section className={manageStyles.section} aria-label="Nome e descrição">
                  <IdentityNameForm
                    collectionId={collectionId}
                    name={name}
                    description={description}
                    coverCode={codeApplies ? coverCode : undefined}
                    onBusyChange={setBusy}
                    save={save}
                  />
                </section>
                <section className={manageStyles.section} aria-label="Cor da capa">
                  <CoverFinishPicker collectionId={collectionId} value={finish} onBusyChange={setBusy} save={saveFinish} />
                </section>
              </div>
            </DialogPrimitive.Content>
          </DialogPrimitive.Portal>
        </DialogPrimitive.Root>
      ) : null}
    </>
  );
}
