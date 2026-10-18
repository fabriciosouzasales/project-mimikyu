"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useRouter } from "next/navigation";
import { useEffect, useId, useState, useTransition } from "react";
import { ChevronDown, Loader2, Plus, X } from "lucide-react";
import {
  linkCopiesToCollection,
  readMasterSetOutOfScope,
  readMasterSetPositionCopies,
} from "@/app/colecoes/colecoes/actions";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { formatCount } from "@/lib/colecoes/acervo";
import { type CollectionFailure, collectionFailureMessage } from "@/lib/colecoes/colecoes";
import { storageLabel } from "@/lib/colecoes/collection-manage";
import {
  OUT_OF_SCOPE_PAGE_SIZE,
  type OutOfScopeCopy,
  type PositionCopy,
  outOfScopeReasonText,
  positionCopyLabel,
} from "@/lib/colecoes/master-set";
import { CardArt } from "../acervo/card-art";
import acervoStyles from "../acervo/acervo.module.css";
import addStyles from "../acervo/acervo-add.module.css";
import manageStyles from "./collection-manage.module.css";
import msStyles from "./master-set.module.css";

// ---------------------------------------------------------------------------
// Exemplares fora do objetivo (5196) — seção recolhível, leitura sob demanda
// ---------------------------------------------------------------------------

type OutLoad =
  | { status: "idle" }
  | { status: "loading"; items: OutOfScopeCopy[] }
  | { status: "ready"; items: OutOfScopeCopy[]; total: number }
  | { status: "error"; items: OutOfScopeCopy[]; reason: CollectionFailure };

/**
 * Exemplares que estão nesta coleção mas não contam para o objetivo atual.
 * Só lê quando o colecionador abre a seção; nada aqui remove, desvincula ou
 * altera exemplar — eles continuam na coleção (C-188).
 */
export function OutOfScopeSection({ collectionId, total }: { collectionId: string; total: number }) {
  const [open, setOpen] = useState(false);
  const [load, setLoad] = useState<OutLoad>({ status: "idle" });
  const panelId = useId();

  const fetchPage = async (offset: number, current: OutOfScopeCopy[]) => {
    setLoad({ status: "loading", items: current });
    const result = await readMasterSetOutOfScope({ collectionId, offset }).catch(
      () => ({ ok: false, reason: "unavailable" }) as const,
    );
    if (!result.ok) {
      setLoad({ status: "error", items: current, reason: result.reason });
      return;
    }
    setLoad({ status: "ready", items: [...current, ...result.items], total: result.total || total });
  };

  const toggle = () => {
    const next = !open;
    setOpen(next);
    if (next && load.status === "idle") void fetchPage(0, []);
  };

  const items = load.status === "idle" ? [] : load.items;
  const known = load.status === "ready" ? load.total : total;
  const hasMore = load.status === "ready" && items.length < known && items.length > 0;

  return (
    <section className={msStyles.outOfScope} aria-labelledby={`${panelId}-title`}>
      <button
        type="button"
        className={msStyles.outToggle}
        aria-expanded={open}
        aria-controls={panelId}
        onClick={toggle}
      >
        <span className="min-w-0">
          <span id={`${panelId}-title`} className={msStyles.outTitle}>
            {total === 1 ? "1 exemplar fora do objetivo" : `${formatCount(total)} exemplares fora do objetivo`}
          </span>
          <span className={msStyles.outSubtitle}>Continuam nesta coleção — só não contam para o progresso atual.</span>
        </span>
        <ChevronDown className={msStyles.outChevron} data-open={open || undefined} aria-hidden="true" />
      </button>

      {open ? (
        <div id={panelId} className={msStyles.outBody}>
          <p className={manageStyles.note}>
            Nada foi removido ou movido. Se você mudar os acabamentos do objetivo em Ajustes, eles podem voltar a contar.
          </p>
          {items.length > 0 ? (
            <ul className={msStyles.outList}>
              {items.map((item) => (
                <li key={item.physicalCardId} className={msStyles.outItem}>
                  <span className={msStyles.outName}>
                    {item.cardName}
                    <span className={msStyles.outNumber}> · nº {item.collectorNumber}</span>
                  </span>
                  {item.finishName ? <span className={msStyles.outFinish}>{item.finishName}</span> : null}
                  <span className={msStyles.outReason}>{outOfScopeReasonText(item.reason)}</span>
                </li>
              ))}
            </ul>
          ) : null}
          <div aria-live="polite">
            {load.status === "loading" ? (
              <div className={msStyles.outLoading}>
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                Carregando exemplares…
              </div>
            ) : null}
            {load.status === "error" ? (
              <div className="flex flex-col gap-3" role="alert">
                <InlineFeedback tone="error">
                  {load.reason === "not_authenticated"
                    ? collectionFailureMessage(load.reason)
                    : "Não conseguimos carregar esta lista agora. Nada foi alterado — tente novamente."}
                </InlineFeedback>
                <Button
                  variant="outline"
                  className="min-h-11 self-start"
                  onClick={() => void fetchPage(load.items.length, load.items)}
                >
                  Tentar novamente
                </Button>
              </div>
            ) : null}
          </div>
          {hasMore ? (
            <Button variant="outline" className="min-h-11 self-start" onClick={() => void fetchPage(items.length, items)}>
              Ver mais {formatCount(Math.min(OUT_OF_SCOPE_PAGE_SIZE, known - items.length))}
            </Button>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}

// ---------------------------------------------------------------------------
// Adicionar do acervo a UMA posição (5199 proposta + 5046)
// ---------------------------------------------------------------------------

type CopiesLoad =
  | { status: "loading" }
  | { status: "error"; reason: CollectionFailure }
  | { status: "ready"; items: PositionCopy[]; total: number };

export function AddFromAcervoButton(props: {
  collectionId: string;
  cardId: string;
  variantTypeId: string | null;
  cardName: string;
  caption: string;
  finish: string;
  imageUrl: string | null;
  available: number;
}) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className={msStyles.addButton} onClick={() => setOpen(true)} aria-haspopup="dialog">
        <Plus className="h-3.5 w-3.5" aria-hidden="true" />
        Adicionar do acervo
        <span className="sr-only">
          {" "}
          — {props.cardName}, {props.finish}
        </span>
      </button>
      {open ? <AddFromAcervoPanel {...props} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

/**
 * Painel: exemplares livres do acervo que satisfazem esta posição. O
 * colecionador escolhe UM e ele é vinculado pela 5046 — que confere dono,
 * Set, coleção ativa e recusa exemplar já vinculado (nada é duplicado nem
 * movido de lugar; versão, idioma e local do exemplar ficam como estão).
 */
function AddFromAcervoPanel({
  collectionId,
  cardId,
  variantTypeId,
  cardName,
  caption,
  finish,
  imageUrl,
  onClose,
}: {
  collectionId: string;
  cardId: string;
  variantTypeId: string | null;
  cardName: string;
  caption: string;
  finish: string;
  imageUrl: string | null;
  onClose: () => void;
}) {
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const [load, setLoad] = useState<CopiesLoad>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);
  const [linkError, setLinkError] = useState<CollectionFailure | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [, startRefresh] = useTransition();

  useEffect(() => {
    let alive = true;
    setLoad({ status: "loading" });
    readMasterSetPositionCopies({ collectionId, cardId, variantTypeId })
      .then((result) => {
        if (!alive) return;
        setLoad(result.ok ? { status: "ready", items: result.items, total: result.total } : { status: "error", reason: result.reason });
      })
      .catch(() => alive && setLoad({ status: "error", reason: "unavailable" }));
    return () => {
      alive = false;
    };
  }, [attempt, collectionId, cardId, variantTypeId]);

  const link = async (copy: PositionCopy) => {
    setBusy(copy.physicalCardId);
    setLinkError(null);
    const result = await linkCopiesToCollection({ collectionId, physicalCardIds: [copy.physicalCardId] }).catch(
      () => ({ ok: false, reason: "unavailable" }) as const,
    );
    setBusy(null);
    if (!result.ok) {
      setLinkError(result.reason);
      // Outro dispositivo pode ter vinculado o mesmo exemplar: relê a lista.
      if (result.reason === "already_linked") setAttempt((n) => n + 1);
      return;
    }
    setDone(`${positionCopyLabel(copy)} entrou na coleção. Continua guardado no mesmo lugar.`);
    // Grade, progresso e contagens vêm do servidor.
    startRefresh(() => router.refresh());
  };

  const locked = busy !== null;

  return (
    <DialogPrimitive.Root open onOpenChange={(open) => !open && !locked && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={acervoStyles.overlay} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${manageStyles.panel}`}
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => locked && event.preventDefault()}
          onPointerDownOutside={(event) => locked && event.preventDefault()}
          onCloseAutoFocus={restoreFocus}
        >
          <div className={acervoStyles.drawerHeader}>
            <div className="min-w-0">
              <DialogPrimitive.Title className={addStyles.panelTitle}>Adicionar do acervo</DialogPrimitive.Title>
              <p className="truncate text-xs text-muted-foreground">{finish}</p>
            </div>
            <DialogPrimitive.Close
              disabled={locked}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          <div className={manageStyles.body}>
            <div className={manageStyles.cardHead}>
              <div className={manageStyles.cardArt}>
                <CardArt src={imageUrl} alt="" name={cardName} caption={caption} sizes="6rem" />
              </div>
              <div className="min-w-0">
                <p className={manageStyles.cardName}>{cardName}</p>
                <p className={manageStyles.cardCaption}>
                  {caption} · {finish}
                </p>
              </div>
            </div>

            <p className={manageStyles.note}>
              Escolha qual exemplar entra. Ele só passa a fazer parte desta coleção — continua guardado onde está, com a
              mesma versão e o mesmo idioma.
            </p>

            <div aria-live="polite" className="flex flex-col gap-3">
              {done ? <InlineFeedback tone="success">{done}</InlineFeedback> : null}
              {linkError ? <InlineFeedback tone="error">{linkFailureText(linkError)}</InlineFeedback> : null}
            </div>

            {done ? (
              <Button variant="outline" className="min-h-11 self-start" onClick={onClose}>
                Fechar
              </Button>
            ) : load.status === "loading" ? (
              <div className={manageStyles.copyList} aria-busy="true" aria-label="Carregando exemplares">
                <div className={manageStyles.skeleton} />
                <div className={manageStyles.skeleton} />
              </div>
            ) : load.status === "error" ? (
              <div className="flex flex-col gap-3" role="alert">
                <InlineFeedback tone="error">
                  {load.reason === "not_authenticated"
                    ? collectionFailureMessage(load.reason)
                    : "Não conseguimos carregar os exemplares agora. Nada foi alterado — tente novamente."}
                </InlineFeedback>
                <Button variant="outline" className="min-h-11 self-start" onClick={() => setAttempt((n) => n + 1)}>
                  Tentar novamente
                </Button>
              </div>
            ) : load.items.length === 0 ? (
              <p className={manageStyles.note}>
                Não há mais exemplares livres desta carta neste acabamento no seu acervo (podem ter entrado em outra
                coleção).
              </p>
            ) : (
              <ul className={manageStyles.copyList}>
                {load.items.map((copy) => (
                  <li key={copy.physicalCardId} className={manageStyles.copy}>
                    <div className={manageStyles.copyRow}>
                      <div className="min-w-0">
                        <p className={manageStyles.copyTitle}>{positionCopyLabel(copy)}</p>
                        <p className={manageStyles.copyMeta}>
                          <span>{storageLabel(copy.storageName)}</span>
                        </p>
                      </div>
                      <Button
                        className="min-h-11 shrink-0"
                        onClick={() => void link(copy)}
                        disabled={locked}
                        aria-label={`Adicionar ${positionCopyLabel(copy)} à coleção`}
                      >
                        {busy === copy.physicalCardId ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
                        {busy === copy.physicalCardId ? "Adicionando…" : "Adicionar"}
                      </Button>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function linkFailureText(reason: CollectionFailure): string {
  if (reason === "already_linked") return "Este exemplar acabou de entrar em uma coleção. A lista foi atualizada — escolha outro.";
  if (reason === "not_found") return "Esta coleção não aceita cartas agora (pode ter sido arquivada). Nada foi alterado.";
  if (reason === "not_authenticated") return collectionFailureMessage(reason);
  return "Não foi possível adicionar. Nada foi alterado — tente novamente.";
}
