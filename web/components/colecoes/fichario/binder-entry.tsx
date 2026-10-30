"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { ArrowRight, BookOpen, BookOpenCheck, Link2 } from "lucide-react";
import { formatCount } from "@/lib/colecoes/acervo";
import { type BinderHeader, binderEntryVisible, binderHref, canJoinExistingBinder, createBlocker, isSharedBinder, modelLabel } from "@/lib/colecoes/binder";
import type { BinderFinish } from "@/lib/colecoes/binder-finish";
import { BinderJoinDialog } from "./binder-join";
import { BinderEndedStatus } from "./binder-lifecycle";
import { BINDER_OPEN_ON_ARRIVAL_KEY } from "@/lib/colecoes/binder-lifecycle";
import { BinderOverlay } from "./binder-overlay";
import styles from "./binder-entry.module.css";

const OPEN_EVENT = "mmkyu:open-binder";

/**
 * Entrada do Fichário Digital no hero da coleção.
 *
 * Com fichário (P2-B-SPIKE-RECOVERY-01): "Abrir o fichário" NÃO navega — abre
 * o fichário sobre a coleção (`BinderOverlay`), que volta intacta ao fechar.
 * A capa da coleção (`BinderCoverLink`) faz o mesmo. Sem fichário: "Montar o
 * fichário" leva à montagem (`/fichario`); sem elegibilidade, explica o que
 * falta. Coleção que não está guardada num fichário físico (local padrão de
 * outro tipo ou nenhum) não exibe a entrada. O cabeçalho vem da 5223, lido em
 * paralelo pela página da coleção.
 */
export function BinderEntry(props: Parameters<typeof BinderEntryCard>[0]) {
  // V1-05: depois de desmontar/excluir, a coleção confirma o resultado logo abaixo da entrada.
  return (
    <>
      <BinderEntryCard {...props} />
      <BinderEndedStatus collectionId={props.collectionId} />
    </>
  );
}

function BinderEntryCard({
  collectionId,
  collectionName,
  finish,
  binder,
}: {
  collectionId: string;
  collectionName: string;
  /** Acabamento (cor) da capa desta coleção — repassado à moldura do fichário aberto. */
  finish?: BinderFinish;
  /**
   * Código do Set/capa. Desde a P3-A a contracapa não mostra mais código
   * (R11); mantido no contrato das três páginas de coleção, sem uso aqui.
   */
  coverCode?: string | null;
  binder: BinderHeader | null;
}) {
  const href = binderHref(collectionId);
  const [open, setOpen] = useState(false);
  const [joining, setJoining] = useState(false);
  const ready = Boolean(binder?.hasBinder && binder.columns && binder.rows && binder.pageCount > 0);

  const openBinder = useCallback(() => setOpen(true), []);
  useEffect(() => {
    if (!ready) return;
    const onOpen = (event: Event) => {
      if ((event as CustomEvent<string>).detail === collectionId) setOpen(true);
    };
    window.addEventListener(OPEN_EVENT, onOpen);
    return () => window.removeEventListener(OPEN_EVENT, onOpen);
  }, [collectionId, ready]);

  // Fichário recém-montado: abre a sobreposição uma vez ao chegar (V1-05).
  useEffect(() => {
    if (!ready) return;
    try {
      if (window.sessionStorage.getItem(BINDER_OPEN_ON_ARRIVAL_KEY) !== collectionId) return;
      window.sessionStorage.removeItem(BINDER_OPEN_ON_ARRIVAL_KEY);
    } catch {
      return;
    }
    setOpen(true);
  }, [collectionId, ready]);

  if (!binderEntryVisible(binder)) return null;

  if (binder && ready && binder.columns && binder.rows) {
    return (
      <>
        <button type="button" className={styles.entry} data-state="ready" onClick={openBinder} aria-haspopup="dialog">
          <Glyph columns={binder.columns} rows={binder.rows} filled />
          <span className={styles.text}>
            <span className={styles.title}>
              Fichário digital
              {binder.role === "GUEST" && binder.ownerCollectionName ? (
                <span className={styles.shared}>
                  <Link2 aria-hidden="true" />
                  de {binder.ownerCollectionName}
                </span>
              ) : isSharedBinder(binder) ? (
                <span className={styles.shared}>
                  <Link2 aria-hidden="true" />
                  compartilhado
                </span>
              ) : null}
            </span>
            <span className={styles.meta}>
              {binder.identity?.displayName ? `${binder.identity.displayName} · ` : ""}
              {modelLabel(binder.columns, binder.rows)} · {formatCount(binder.pageCount)} {binder.pageCount === 1 ? "página" : "páginas"} ·{" "}
              {isSharedBinder(binder)
                ? `${formatCount(binder.ownFilledCount)} ${binder.ownFilledCount === 1 ? "carta desta coleção nos bolsos" : "cartas desta coleção nos bolsos"}`
                : `${formatCount(binder.filledCount)} ${binder.filledCount === 1 ? "carta nos bolsos" : "cartas nos bolsos"}`}
              {binder.availableCount > 0 && binder.editable
                ? ` · ${formatCount(binder.availableCount)} ${binder.availableCount === 1 ? "disponível" : "disponíveis"}`
                : ""}
            </span>
          </span>
          <span className={styles.cta}>
            <BookOpen aria-hidden="true" />
            Abrir o fichário
            <ArrowRight className={styles.arrow} aria-hidden="true" />
          </span>
        </button>
        {open ? (
          <BinderOverlay
            collectionId={collectionId}
            collectionName={collectionName}
            header={binder}
            finish={finish}
            onClose={() => setOpen(false)}
          />
        ) : null}
      </>
    );
  }

  // Já existe um fichário digital no mesmo fichário físico: usar o existente vem primeiro (nunca induz a montar outro).
  if (binder && canJoinExistingBinder(binder)) {
    return (
      <>
        <button type="button" className={styles.entry} data-state="join" onClick={() => setJoining(true)} aria-haspopup="dialog">
          <Glyph columns={3} rows={3} filled />
          <span className={styles.text}>
            <span className={styles.title}>Fichário digital</span>
            <span className={styles.meta}>
              {binder.defaultStorageName ? `“${binder.defaultStorageName}” já tem um fichário digital.` : "Este local já tem um fichário digital."} Use o mesmo
              para esta coleção.
            </span>
          </span>
          <span className={styles.cta}>
            <Link2 aria-hidden="true" />
            Usar fichário existente
            <ArrowRight className={styles.arrow} aria-hidden="true" />
          </span>
        </button>
        {joining ? <BinderJoinDialog collectionId={collectionId} collectionName={collectionName} onClose={() => setJoining(false)} /> : null}
      </>
    );
  }

  if (binder && !binder.hasBinder && createBlocker(binder) === null) {
    return (
      <Link href={href} className={styles.entry} data-state="create">
        <Glyph columns={3} rows={3} />
        <span className={styles.text}>
          <span className={styles.title}>Fichário digital</span>
          <span className={styles.meta}>Organize esta coleção em páginas, como no seu fichário de verdade.</span>
        </span>
        <span className={styles.cta}>
          <BookOpenCheck aria-hidden="true" />
          Montar o fichário
          <ArrowRight className={styles.arrow} aria-hidden="true" />
        </span>
      </Link>
    );
  }

  return (
    <Link href={href} className={styles.entry} data-state="info">
      <Glyph columns={3} rows={3} />
      <span className={styles.text}>
        <span className={styles.title}>Fichário digital</span>
        <span className={styles.meta}>
          {binder === null
            ? "Veja esta coleção página por página."
            : binder.hasBinder
              ? "Este fichário está sem páginas no momento."
              : !binder.active
                ? "Coleção arquivada: reative para montar o fichário."
                : "Escolha um fichário como local padrão para montar as páginas."}
        </span>
      </span>
      <span className={styles.ctaQuiet}>
        {binder === null || binder.hasBinder ? "Abrir" : "Ver como montar"}
        <ArrowRight className={styles.arrow} aria-hidden="true" />
      </span>
    </Link>
  );
}

/** Miniatura da grade do modelo: duas folhas abertas, bolsos em 8:11. */
function Glyph({ columns, rows, filled = false }: { columns: number; rows: number; filled?: boolean }) {
  const pockets = Array.from({ length: columns * rows });
  return (
    <span className={styles.glyph} data-filled={filled || undefined} style={{ "--cols": columns } as React.CSSProperties} aria-hidden="true">
      <span className={styles.leaf}>
        {pockets.map((_, index) => (
          <span key={index} />
        ))}
      </span>
      <span className={styles.leaf}>
        {pockets.map((_, index) => (
          <span key={index} />
        ))}
      </span>
    </span>
  );
}

/**
 * A capa do hero também é a porta do fichário: com fichário pronto, abre a
 * sobreposição (mesmo evento do botão); sem fichário, leva à montagem.
 */
export function BinderCoverLink({
  collectionId,
  ready,
  available = true,
  children,
}: {
  collectionId: string;
  ready: boolean;
  /** `binderEntryVisible`: sem fichário físico, a capa não leva ao fichário. */
  available?: boolean;
  children: React.ReactNode;
}) {
  if (!ready && !available) return <>{children}</>;
  if (!ready) {
    return (
      <Link href={binderHref(collectionId)} className={styles.coverLink} aria-label="Fichário digital desta coleção">
        {children}
      </Link>
    );
  }
  return (
    <button
      type="button"
      className={styles.coverLink}
      aria-label="Abrir o fichário digital"
      aria-haspopup="dialog"
      onClick={() => window.dispatchEvent(new CustomEvent(OPEN_EVENT, { detail: collectionId }))}
    >
      {children}
    </button>
  );
}
