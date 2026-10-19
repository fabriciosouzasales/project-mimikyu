"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useRouter } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useRef, useState } from "react";
import { AlertTriangle, Check, CheckCircle2, Loader2, Plus, Sparkles, X } from "lucide-react";
import { linkMasterSetPositions, reviewMasterSetLink } from "@/app/colecoes/colecoes/actions";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { Button } from "@/components/ui/button";
import { cardFrontUrl, formatCollectorNumber, formatCount } from "@/lib/colecoes/acervo";
import { type CollectionFailure, collectionFailureMessage } from "@/lib/colecoes/colecoes";
import { type MasterSetLinkCandidate, finishBadge } from "@/lib/colecoes/master-set";
import { CardArt } from "../acervo/card-art";
import addStyles from "../acervo/acervo-add.module.css";
import acervoStyles from "../acervo/acervo.module.css";
import styles from "./colecoes.module.css";
import msStyles from "./master-set.module.css";

/**
 * Master Set — "Adicionar cartas" em lote (5200 + 5046), irmão do
 * `LinkCardsLauncher` do Set padrão.
 *
 * Lista as POSIÇÕES que faltam (carta + acabamento, ou secreta em qualquer
 * acabamento) para as quais existe exemplar livre no acervo — um por posição,
 * o mesmo que o "Adicionar do acervo" da carta sugeriria primeiro. Todas vêm
 * marcadas, com "Selecionar todas" / "Limpar". Na confirmação o servidor relê
 * o estado atual: posição já atendida no meio do caminho não entra.
 *
 * Adicionar a uma coleção não move carta nenhuma: o exemplar continua no
 * acervo, no mesmo lugar; a coleção só passa a contá-lo.
 */
export function MasterSetLinkLauncher({ collectionId, linkable }: { collectionId: string; linkable: number }) {
  const [open, setOpen] = useState(false);
  const empty = linkable <= 0;
  return (
    <>
      <Button
        onClick={() => !empty && setOpen(true)}
        disabled={empty}
        title={empty ? "Nenhuma posição que falta tem carta disponível no seu acervo agora" : undefined}
        size="sm"
        className="h-8 gap-1.5 rounded-full px-3.5 text-[0.8125rem]"
        aria-label={
          empty
            ? "Adicionar cartas — nenhuma carta disponível no seu acervo agora"
            : `Adicionar cartas do seu acervo às posições que faltam (${formatCount(linkable)} disponíveis)`
        }
      >
        <Plus className="h-3.5 w-3.5" aria-hidden="true" />
        Adicionar cartas
        <span className="tabular-nums opacity-80">({formatCount(linkable)})</span>
      </Button>
      {open && !empty ? <MasterSetLinkPanel collectionId={collectionId} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

type Review =
  | { status: "loading" }
  | { status: "error"; reason: CollectionFailure }
  | { status: "ready"; total: number; items: MasterSetLinkCandidate[] };
type Commit =
  | { status: "idle" }
  | { status: "pending" }
  | { status: "error"; reason: CollectionFailure; linked: number }
  | { status: "done"; linked: number };

function MasterSetLinkPanel({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const [review, setReview] = useState<Review>({ status: "loading" });
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [commit, setCommit] = useState<Commit>({ status: "idle" });
  const busy = commit.status === "pending";

  const load = useCallback(async () => {
    setReview({ status: "loading" });
    setCommit({ status: "idle" });
    const result = await reviewMasterSetLink({ collectionId }).catch(() => ({ ok: false as const, reason: "unavailable" as const }));
    if (!result.ok) {
      setReview({ status: "error", reason: result.reason });
      return;
    }
    setPicked(new Set(result.items.map((item) => item.key)));
    setReview({ status: "ready", total: result.total, items: result.items });
  }, [collectionId]);

  useEffect(() => {
    void load();
  }, [load]);

  const chosen = review.status === "ready" ? review.items.filter((item) => picked.has(item.key)).map((item) => item.key) : [];
  const chosenCount = chosen.length;

  const confirm = async () => {
    if (review.status !== "ready" || busy || chosenCount === 0) return;
    setCommit({ status: "pending" });
    const result = await linkMasterSetPositions({ collectionId, positionKeys: chosen }).catch(() => ({
      ok: false as const,
      reason: "unavailable" as const,
      linked: 0,
    }));
    setCommit(result.ok ? { status: "done", linked: result.linked } : { status: "error", reason: result.reason, linked: result.linked });
    if (result.linked > 0) router.refresh();
  };

  const close = () => {
    if (!busy) onClose();
  };

  return (
    <DialogPrimitive.Root open onOpenChange={(next) => !next && close()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={acervoStyles.overlay} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${addStyles.panel}`}
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => busy && event.preventDefault()}
          onPointerDownOutside={(event) => busy && event.preventDefault()}
          onCloseAutoFocus={restoreFocus}
        >
          <div className={acervoStyles.drawerHeader}>
            <DialogPrimitive.Title className={addStyles.panelTitle}>Adicionar cartas</DialogPrimitive.Title>
            <DialogPrimitive.Close
              disabled={busy}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          {commit.status === "done" ? (
            <Done linked={commit.linked} onClose={onClose} />
          ) : review.status === "loading" ? (
            <div className={addStyles.body}>
              <div className={addStyles.centerState} role="status">
                <Loader2 className={`h-5 w-5 ${addStyles.spin}`} aria-hidden="true" />
                Conferindo as cartas do seu acervo…
              </div>
            </div>
          ) : review.status === "error" ? (
            <>
              <div className={addStyles.body}>
                <Notice title="Não conseguimos preparar a revisão">{collectionFailureMessage(review.reason)}</Notice>
              </div>
              <Footer>
                <Button variant="outline" onClick={onClose}>
                  Fechar
                </Button>
                <Button onClick={() => void load()}>Tentar novamente</Button>
              </Footer>
            </>
          ) : review.total === 0 ? (
            <>
              <div className={addStyles.body}>
                <div className={addStyles.done} role="status">
                  <h2 className={addStyles.doneTitle}>Nada para adicionar agora</h2>
                  <p className={addStyles.doneText}>
                    As cartas deste Set que estão livres no seu acervo já ocupam as posições que você tem, ou estão em
                    outra coleção.
                  </p>
                </div>
              </div>
              <Footer>
                <Button onClick={onClose}>Fechar</Button>
              </Footer>
            </>
          ) : (
            <>
              <div className={addStyles.body}>
                <div className={addStyles.reviewHead}>
                  <span className={addStyles.reviewCount}>{formatCount(review.total)}</span>
                  <span className={addStyles.reviewLabel}>
                    {review.total === 1 ? "posição que falta pode" : "posições que faltam podem"} ser preenchidas com
                    cartas do seu acervo. Marque as que entram — <strong>uma por acabamento</strong>.
                  </span>
                </div>
                <p className={addStyles.reviewNote}>
                  Para cada posição entra a carta que o MMKYU sugeriria primeiro (versão padrão, seu idioma). Elas
                  continuam no seu acervo, no mesmo lugar; a coleção só passa a contá-las.
                </p>

                <section aria-labelledby="master-escolha">
                  <div className={styles.pickHead}>
                    <h3 id="master-escolha" className={addStyles.sectionTitle}>
                      {formatCount(chosenCount)} de {formatCount(review.items.length)} marcadas
                    </h3>
                    <span className={styles.pickTools}>
                      <Button
                        variant="ghost"
                        size="sm"
                        disabled={busy || chosenCount === review.items.length}
                        onClick={() => setPicked(new Set(review.items.map((item) => item.key)))}
                      >
                        Selecionar todas
                      </Button>
                      <Button variant="ghost" size="sm" disabled={busy || chosenCount === 0} onClick={() => setPicked(new Set())}>
                        Limpar
                      </Button>
                    </span>
                  </div>
                  {review.total > review.items.length ? (
                    <p className={styles.fieldHint}>
                      Mostrando as primeiras {formatCount(review.items.length)}. Depois de adicionar, abra de novo para ver as demais.
                    </p>
                  ) : null}
                  <ul className={styles.pickList} aria-label="Posições que podem ser preenchidas">
                    {review.items.map((item) => (
                      <PickPosition
                        key={item.key}
                        item={item}
                        picked={picked.has(item.key)}
                        disabled={busy}
                        onToggle={() =>
                          setPicked((current) => {
                            const next = new Set(current);
                            if (next.has(item.key)) next.delete(item.key);
                            else next.add(item.key);
                            return next;
                          })
                        }
                      />
                    ))}
                  </ul>
                </section>

                {commit.status === "error" ? (
                  <Notice title={commit.linked > 0 ? "Parte das cartas entrou" : "Nenhuma carta foi adicionada"}>
                    {commit.linked > 0
                      ? `${formatCount(commit.linked)} ${commit.linked === 1 ? "carta entrou" : "cartas entraram"} na coleção. ${collectionFailureMessage(commit.reason)}`
                      : collectionFailureMessage(commit.reason)}
                  </Notice>
                ) : null}
              </div>
              <Footer lead={chosenCount === 0 ? "Nenhuma posição marcada" : `${formatCount(chosenCount)} ${chosenCount === 1 ? "carta" : "cartas"}`}>
                <Button variant="outline" onClick={close} disabled={busy}>
                  Cancelar
                </Button>
                {commit.status === "error" ? (
                  <Button onClick={() => void load()} disabled={busy}>
                    Revisar de novo
                  </Button>
                ) : (
                  <Button onClick={() => void confirm()} disabled={busy || chosenCount === 0} aria-busy={busy}>
                    {busy ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
                    {busy ? "Adicionando…" : `Adicionar ${formatCount(chosenCount)} à coleção`}
                  </Button>
                )}
              </Footer>
            </>
          )}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

function PickPosition({
  item,
  picked,
  disabled,
  onToggle,
}: {
  item: MasterSetLinkCandidate;
  picked: boolean;
  disabled: boolean;
  onToggle: () => void;
}) {
  const number = formatCollectorNumber(item.collectorNumber, null);
  const finish = finishBadge(item);
  const finishText = item.isSecret && item.variantTypeId === null ? `Secreta · ${finish.toLowerCase()}` : finish;
  return (
    <li className={styles.pickItem} data-picked={picked || undefined}>
      <label className={styles.pickRow}>
        <input
          type="checkbox"
          checked={picked}
          disabled={disabled}
          onChange={onToggle}
          className="sr-only"
          aria-label={`${item.cardName}, ${number}, ${finishText}`}
        />
        <span className={styles.pickArt} aria-hidden="true">
          <CardArt src={cardFrontUrl(SUPABASE_URL, item.imagePath)} alt="" name={item.cardName} caption={number} sizes="3.5rem" />
        </span>
        <span className="min-w-0 flex-1" aria-hidden="true">
          <span className={styles.pickName}>{item.cardName}</span>
          <span className={styles.pickNumber}>{number}</span>
          <span className={msStyles.finishLine} data-secret={item.isSecret || undefined}>
            {item.isSecret ? <Sparkles className={msStyles.secretIcon} /> : null}
            <span className={msStyles.finishText}>{finishText}</span>
          </span>
        </span>
        <span className={styles.pickCheck} aria-hidden="true">
          {picked ? <Check className="h-4 w-4" /> : null}
        </span>
      </label>
    </li>
  );
}

function Done({ linked, onClose }: { linked: number; onClose: () => void }) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => headingRef.current?.focus(), []);
  return (
    <>
      <div className={addStyles.body}>
        <div className={addStyles.done} role="status">
          <span className={addStyles.doneIcon} aria-hidden="true">
            <CheckCircle2 className="h-6 w-6" />
          </span>
          <h2 ref={headingRef} tabIndex={-1} className={addStyles.doneTitle}>
            {linked === 1 ? "1 carta adicionada à coleção" : `${formatCount(linked)} cartas adicionadas à coleção`}
          </h2>
          <p className={addStyles.doneText}>
            {linked === 0
              ? "Essas posições já tinham sido preenchidas — nada mudou."
              : "O progresso do Master Set já está atualizado. As cartas continuam no seu acervo, no mesmo lugar."}
          </p>
        </div>
      </div>
      <Footer>
        <Button onClick={onClose}>Ver a coleção</Button>
      </Footer>
    </>
  );
}

function Footer({ lead, children }: { lead?: string; children: ReactNode }) {
  return (
    <div className={addStyles.footer}>
      <span className={addStyles.footerLead} aria-live="polite">
        {lead ?? ""}
      </span>
      <div className={addStyles.footerActions}>{children}</div>
    </div>
  );
}

function Notice({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className={addStyles.notice} role="alert">
      <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
      <div>
        <p className={addStyles.noticeTitle}>{title}</p>
        <div className={addStyles.noticeText}>{children}</div>
      </div>
    </div>
  );
}
