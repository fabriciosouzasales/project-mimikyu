"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AlertTriangle, Bookmark, Check, CheckCircle2, Loader2, Sparkles, X } from "lucide-react";
import { addMissingWishes, previewMissingWishes } from "@/app/colecoes/lista-de-desejos/actions";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { Button } from "@/components/ui/button";
import { Select } from "@/components/ui/select";
import { cardFrontUrl, formatCollectorNumber, formatCount } from "@/lib/colecoes/acervo";
import type { WishFailureReason } from "@/lib/wishlist/wishlist";
import {
  type BulkConfirmationSummary,
  type BulkItem,
  type BulkScope,
  type BulkSelection,
  bulkAddHeadline,
  bulkCounts,
  bulkPlan,
  chooseBulkVariant,
  selectAllDirect,
  toggleBulkItem,
} from "@/lib/wishlist/wishlist-bulk";
import { CardArt } from "@/components/colecoes/acervo/card-art";
import addStyles from "@/components/colecoes/acervo/acervo-add.module.css";
import acervoStyles from "@/components/colecoes/acervo/acervo.module.css";
import styles from "@/components/colecoes/colecoes/colecoes.module.css";
import msStyles from "@/components/colecoes/colecoes/master-set.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const WISHLIST_HREF = "/colecoes/lista-de-desejos";

/**
 * V1-11 W7 — "Desejar faltantes" (Set padrão e Master Set).
 *
 * Abre a prévia das cartas/posições que faltam na coleção, separadas como o contrato
 * pede (§4.2): **prontas** (uma variante possível), **escolha a variante** (mais de uma —
 * nunca presumida), **já na sua Lista** e **sem variante disponível**. Nada vem marcado:
 * o colecionador escolhe (um a um ou "Marcar todas" — só as prontas, nunca as que exigem escolha), revisa e confirma uma vez. A
 * gravação é única e idempotente (5352), sempre "qualquer idioma", e o resultado conta
 * incluídos, já existentes e falhas — nada parcial aparece como sucesso.
 *
 * Desejar não muda a coleção, o acervo, reservas nem o progresso (C-211).
 */
export function MissingWishesLauncher({ collectionId, missing }: { collectionId: string; missing: number }) {
  const [open, setOpen] = useState(false);
  const empty = missing <= 0;
  return (
    <>
      <Button
        variant="outline"
        size="sm"
        onClick={() => !empty && setOpen(true)}
        disabled={empty}
        title={empty ? "Nada falta nesta coleção" : undefined}
        className="h-8 gap-1.5 rounded-full px-3.5 text-[0.8125rem]"
        aria-label={empty ? "Desejar faltantes — nada falta nesta coleção" : "Desejar faltantes: escolher quais cartas que faltam vão para a Lista de desejos"}
      >
        <Bookmark className="h-3.5 w-3.5" aria-hidden="true" />
        Desejar faltantes
      </Button>
      {open && !empty ? <MissingWishesPanel collectionId={collectionId} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

type Preview =
  | { status: "loading" }
  | { status: "error"; reason: WishFailureReason }
  | { status: "ready"; scope: BulkScope; total: number; items: BulkItem[] };

type Commit =
  | { status: "idle" }
  | { status: "pending" }
  | { status: "error"; reason: WishFailureReason }
  | { status: "done"; summary: BulkConfirmationSummary };

const FAILURE_TEXT: Readonly<Record<WishFailureReason, string>> = {
  not_authenticated: "Sua sessão expirou. Entre de novo para continuar.",
  invalid: "Esta coleção não está disponível para desejar faltantes.",
  variant_unavailable: "Alguma carta deixou de estar disponível no catálogo.",
  multiple_entries: "Não foi possível concluir agora.",
  unavailable: "Este recurso ainda não está disponível. Tente de novo mais tarde.",
  failed: "Não foi possível concluir agora. Nada foi alterado na sua coleção.",
};

function MissingWishesPanel({ collectionId, onClose }: { collectionId: string; onClose: () => void }) {
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const [preview, setPreview] = useState<Preview>({ status: "loading" });
  const [selection, setSelection] = useState<BulkSelection>(new Map());
  const [step, setStep] = useState<"pick" | "review">("pick");
  const [commit, setCommit] = useState<Commit>({ status: "idle" });
  const busy = commit.status === "pending";

  const load = useCallback(async () => {
    setPreview({ status: "loading" });
    setCommit({ status: "idle" });
    setStep("pick");
    setSelection(new Map());
    const result = await previewMissingWishes(collectionId).catch(() => ({ ok: false as const, reason: "failed" as const }));
    setPreview(result.ok ? { status: "ready", scope: result.scope, total: result.total, items: result.items } : { status: "error", reason: result.reason });
  }, [collectionId]);

  useEffect(() => {
    void load();
  }, [load]);

  const items = useMemo(() => (preview.status === "ready" ? preview.items : []), [preview]);
  const plan = useMemo(() => bulkPlan(items, selection), [items, selection]);
  const counts = useMemo(() => bulkCounts(items), [items]);

  const confirm = async () => {
    if (busy || plan.variantIds.length === 0 || plan.pendingChoice > 0) return;
    setCommit({ status: "pending" });
    // Só posição + variante escolhida: a elegibilidade é refeita no servidor (FIX-03).
    const selections = items.flatMap((item) => {
      const variantId = selection.get(item.key);
      return variantId ? [{ positionKey: item.key, variantId }] : [];
    });
    const result = await addMissingWishes({ collectionId, selections }).catch(() => ({ ok: false as const, reason: "failed" as const }));
    if (!result.ok) {
      setCommit({ status: "error", reason: result.reason });
      return;
    }
    setCommit({ status: "done", summary: result.summary });
    if (result.summary.created > 0) router.refresh();
  };

  const close = () => {
    if (!busy) onClose();
  };

  const title = preview.status === "ready" && preview.scope === "master" ? "Desejar posições que faltam" : "Desejar cartas que faltam";

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
            <DialogPrimitive.Title className={addStyles.panelTitle}>{title}</DialogPrimitive.Title>
            <DialogPrimitive.Close
              disabled={busy}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          {commit.status === "done" ? (
            <Done summary={commit.summary} onClose={onClose} />
          ) : preview.status === "loading" ? (
            <div className={addStyles.body}>
              <div className={addStyles.centerState} role="status">
                <Loader2 className={`h-5 w-5 ${addStyles.spin}`} aria-hidden="true" />
                Conferindo o que falta e a sua Lista de desejos…
              </div>
            </div>
          ) : preview.status === "error" ? (
            <>
              <div className={addStyles.body}>
                <Notice title="Não conseguimos preparar a lista">{FAILURE_TEXT[preview.reason]}</Notice>
              </div>
              <Footer>
                <Button variant="outline" onClick={onClose}>
                  Fechar
                </Button>
                <Button onClick={() => void load()}>Tentar novamente</Button>
              </Footer>
            </>
          ) : counts.direct + counts.choose === 0 ? (
            <>
              <div className={addStyles.body}>
                <div className={addStyles.done} role="status">
                  <h2 className={addStyles.doneTitle}>{items.length === 0 ? "Nada falta nesta coleção" : "Nada novo para desejar"}</h2>
                  <p className={addStyles.doneText}>
                    {items.length === 0
                      ? "Todas as posições já estão preenchidas."
                      : `${formatCount(counts.wished)} já ${counts.wished === 1 ? "está" : "estão"} na sua Lista de desejos${counts.none > 0 ? ` e ${formatCount(counts.none)} sem variante disponível no catálogo` : ""}.`}
                  </p>
                </div>
              </div>
              <Footer>
                <Button onClick={onClose}>Fechar</Button>
              </Footer>
            </>
          ) : step === "review" ? (
            <Review
              items={items}
              selection={selection}
              plan={plan}
              busy={busy}
              commit={commit}
              onBack={() => setStep("pick")}
              onConfirm={() => void confirm()}
            />
          ) : (
            <>
              <div className={addStyles.body}>
                <div className={addStyles.reviewHead}>
                  <span className={addStyles.reviewCount}>{formatCount(counts.direct + counts.choose)}</span>
                  <span className={addStyles.reviewLabel}>
                    {preview.scope === "master" ? "posições que faltam podem" : "cartas que faltam podem"} ir para a sua Lista de desejos.
                    Marque as que você quer — <strong>nada entra sem a sua confirmação</strong>.
                  </span>
                </div>
                <p className={addStyles.reviewNote}>
                  Os desejos entram como “qualquer idioma” e não ficam presos a esta coleção. A coleção, o acervo e o progresso
                  não mudam.
                </p>
                {preview.total > items.length ? (
                  <p className={styles.fieldHint}>
                    Mostrando as primeiras {formatCount(items.length)} de {formatCount(preview.total)}. Depois de incluir, abra de novo
                    para ver as demais.
                  </p>
                ) : null}

                {counts.direct > 0 ? (
                  <section aria-labelledby="desejo-lote-prontas">
                    <div className={styles.pickHead}>
                      <h3 id="desejo-lote-prontas" className={addStyles.sectionTitle}>
                        Prontas para incluir · {formatCount(counts.direct)}
                      </h3>
                      <span className={styles.pickTools}>
                        <Button variant="ghost" size="sm" onClick={() => setSelection((current) => selectAllDirect(current, items))}>
                          Marcar todas
                        </Button>
                        <Button variant="ghost" size="sm" disabled={selection.size === 0} onClick={() => setSelection(new Map())}>
                          Limpar
                        </Button>
                      </span>
                    </div>
                    <ul className={styles.pickList} aria-label="Prontas para incluir">
                      {items
                        .filter((item) => item.state === "direct")
                        .map((item) => (
                          <PickRow
                            key={item.key}
                            item={item}
                            picked={selection.has(item.key)}
                            detail={item.options[0]?.label ?? null}
                            onToggle={() => setSelection((current) => toggleBulkItem(current, item))}
                          />
                        ))}
                    </ul>
                  </section>
                ) : null}

                {counts.choose > 0 ? (
                  <section aria-labelledby="desejo-lote-escolha">
                    <div className={styles.pickHead}>
                      <h3 id="desejo-lote-escolha" className={addStyles.sectionTitle}>
                        Escolha a variante · {formatCount(counts.choose)}
                      </h3>
                    </div>
                    <p className={styles.fieldHint}>
                      {preview.scope === "master"
                        ? "Há mais de uma versão possível para estas posições. Escolha qual você quer — o MMKYU não decide por você."
                        : "Estas cartas têm mais de uma variante. Escolha qual você quer — o MMKYU não decide por você."}
                    </p>
                    <ul className={styles.pickList} aria-label="Escolha a variante">
                      {items
                        .filter((item) => item.state === "choose")
                        .map((item) => (
                          <PickRow
                            key={item.key}
                            item={item}
                            picked={selection.has(item.key)}
                            detail={null}
                            onToggle={() => setSelection((current) => toggleBulkItem(current, item))}
                          >
                            <ChooseVariant item={item} value={selection.get(item.key) ?? ""} onChange={(variantId) => setSelection((current) => chooseBulkVariant(current, item, variantId))} />
                          </PickRow>
                        ))}
                    </ul>
                  </section>
                ) : null}

                {counts.wished + counts.none > 0 ? (
                  <section aria-labelledby="desejo-lote-fora">
                    <h3 id="desejo-lote-fora" className={addStyles.sectionTitle}>
                      Fora deste lote
                    </h3>
                    <p className={styles.fieldHint}>
                      {counts.wished > 0 ? `${formatCount(counts.wished)} já ${counts.wished === 1 ? "está" : "estão"} na sua Lista de desejos.` : ""}
                      {counts.wished > 0 && counts.none > 0 ? " " : ""}
                      {counts.none > 0 ? `${formatCount(counts.none)} sem variante disponível no catálogo.` : ""}
                    </p>
                    <details className={styles.fieldHint}>
                      <summary>Ver quais</summary>
                      <ul className={addStyles.issueList}>
                        {items
                          .filter((item) => item.state === "wished" || item.state === "none")
                          .map((item) => (
                            <li key={item.key}>
                              {item.cardName} · {formatCollectorNumber(item.collectorNumber, item.collectorTotal)}
                              {item.finishLabel ? ` · ${item.finishLabel}` : ""} —{" "}
                              {item.state === "wished" ? "já na sua Lista" : "sem variante disponível"}
                            </li>
                          ))}
                      </ul>
                    </details>
                  </section>
                ) : null}
              </div>
              <Footer
                lead={
                  plan.ready + plan.pendingChoice === 0
                    ? "Nada marcado"
                    : plan.pendingChoice > 0
                      ? `${formatCount(plan.pendingChoice)} ${plan.pendingChoice === 1 ? "precisa" : "precisam"} de variante`
                      : `${formatCount(plan.variantIds.length)} ${plan.variantIds.length === 1 ? "desejo" : "desejos"}`
                }
              >
                <Button variant="outline" onClick={close}>
                  Cancelar
                </Button>
                <Button onClick={() => setStep("review")} disabled={plan.variantIds.length === 0 || plan.pendingChoice > 0}>
                  Revisar
                </Button>
              </Footer>
            </>
          )}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function PickRow({
  item,
  picked,
  detail,
  onToggle,
  children,
}: {
  item: BulkItem;
  picked: boolean;
  detail: string | null;
  onToggle: () => void;
  children?: ReactNode;
}) {
  const number = formatCollectorNumber(item.collectorNumber, item.collectorTotal);
  const name = [item.cardName, number, item.finishLabel].filter(Boolean).join(", ");
  return (
    <li className={styles.pickItem} data-picked={picked || undefined}>
      <label className={styles.pickRow}>
        <input type="checkbox" checked={picked} onChange={onToggle} className="sr-only" aria-label={detail ? `${name}, ${detail}` : name} />
        <span className={styles.pickArt} aria-hidden="true">
          <CardArt src={cardFrontUrl(SUPABASE_URL, item.imagePath)} alt="" name={item.cardName} caption={number} sizes="3.5rem" />
        </span>
        <span className="min-w-0 flex-1" aria-hidden="true">
          <span className={styles.pickName}>{item.cardName}</span>
          <span className={styles.pickNumber}>{number}</span>
          {item.finishLabel ? (
            <span className={msStyles.finishLine} data-secret={item.isSecret || undefined}>
              {item.isSecret ? <Sparkles className={msStyles.secretIcon} /> : null}
              <span className={msStyles.finishText}>{item.finishLabel}</span>
            </span>
          ) : null}
          {detail ? <span className={styles.pickNumber}>{detail}</span> : null}
        </span>
        <span className={styles.pickCheck} aria-hidden="true">
          {picked ? <Check className="h-4 w-4" /> : null}
        </span>
      </label>
      {children}
    </li>
  );
}

function ChooseVariant({ item, value, onChange }: { item: BulkItem; value: string; onChange: (variantId: string | null) => void }) {
  const id = `desejo-lote-variante-${item.key.replace(/[^a-z0-9-]/gi, "-")}`;
  return (
    <div>
      <label htmlFor={id} className="sr-only">
        Variante de {item.cardName}
      </label>
      <Select id={id} value={value} onChange={(event) => onChange(event.target.value || null)} invalid={false}>
        <option value="">Escolher variante…</option>
        {item.options.map((option) => (
          <option key={option.variantId} value={option.variantId}>
            {option.label}
            {option.isDefault ? " (padrão)" : ""}
          </option>
        ))}
      </Select>
    </div>
  );
}

function Review({
  items,
  selection,
  plan,
  busy,
  commit,
  onBack,
  onConfirm,
}: {
  items: readonly BulkItem[];
  selection: BulkSelection;
  plan: ReturnType<typeof bulkPlan>;
  busy: boolean;
  commit: Commit;
  onBack: () => void;
  onConfirm: () => void;
}) {
  const chosen = items.filter((item) => selection.get(item.key));
  const total = plan.variantIds.length;
  return (
    <>
      <div className={addStyles.body}>
        <div className={addStyles.reviewHead}>
          <span className={addStyles.reviewCount}>{formatCount(total)}</span>
          <span className={addStyles.reviewLabel}>
            {total === 1 ? "desejo vai" : "desejos vão"} para a sua Lista, como <strong>qualquer idioma</strong>.
          </span>
        </div>
        <p className={addStyles.reviewNote}>
          A coleção, o acervo e o progresso não mudam. Se algum já estiver na Lista, ele não é duplicado.
        </p>
        <ul className={addStyles.reviewList} aria-label="Desejos a incluir">
          {chosen.map((item) => {
            const variant = item.options.find((option) => option.variantId === selection.get(item.key));
            return (
              <li key={item.key} className={addStyles.reviewItem}>
                <span className={addStyles.reviewQty} aria-hidden="true">
                  <Bookmark className="h-4 w-4" />
                </span>
                <span className={addStyles.reviewName}>{item.cardName}</span>
                <span className={addStyles.reviewMeta}>
                  {[formatCollectorNumber(item.collectorNumber, item.collectorTotal), item.finishLabel, variant?.label].filter(Boolean).join(" · ")}
                </span>
              </li>
            );
          })}
        </ul>
        {commit.status === "error" ? <Notice title="Nenhum desejo foi incluído">{FAILURE_TEXT[commit.reason]}</Notice> : null}
      </div>
      <Footer lead={`${formatCount(total)} ${total === 1 ? "desejo" : "desejos"}`}>
        <Button variant="outline" onClick={onBack} disabled={busy}>
          Voltar
        </Button>
        <Button onClick={onConfirm} disabled={busy || total === 0} aria-busy={busy}>
          {busy ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
          {busy ? "Incluindo…" : commit.status === "error" ? "Tentar de novo" : `Incluir ${formatCount(total)} na Lista`}
        </Button>
      </Footer>
    </>
  );
}

function Done({ summary, onClose }: { summary: BulkConfirmationSummary; onClose: () => void }) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => headingRef.current?.focus(), []);
  const lines = [
    summary.created > 0 ? `${formatCount(summary.created)} ${summary.created === 1 ? "incluído" : "incluídos"}` : null,
    summary.existing + summary.alreadyWished > 0
      ? `${formatCount(summary.existing + summary.alreadyWished)} já ${summary.existing + summary.alreadyWished === 1 ? "existia" : "existiam"} na Lista`
      : null,
    summary.notMissing > 0
      ? `${formatCount(summary.notMissing)} ${summary.notMissing === 1 ? "posição já foi preenchida" : "posições já foram preenchidas"} — ${summary.notMissing === 1 ? "ignorada" : "ignoradas"}`
      : null,
    summary.rejected > 0 ? `${formatCount(summary.rejected)} ${summary.rejected === 1 ? "escolha recusada" : "escolhas recusadas"} — variante não corresponde à posição` : null,
    summary.unavailable > 0 ? `${formatCount(summary.unavailable)} indisponíve${summary.unavailable === 1 ? "l" : "is"} no catálogo — não ${summary.unavailable === 1 ? "incluído" : "incluídos"}` : null,
    summary.missing > 0 ? `${formatCount(summary.missing)} sem confirmação do servidor — confira na Lista` : null,
  ].filter((line): line is string => line !== null);
  return (
    <>
      <div className={addStyles.body}>
        <div className={addStyles.done} role="status">
          <span className={addStyles.doneIcon} aria-hidden="true">
            {summary.complete ? <CheckCircle2 className="h-6 w-6" /> : <AlertTriangle className="h-6 w-6" />}
          </span>
          <h2 ref={headingRef} tabIndex={-1} className={addStyles.doneTitle}>
            {bulkAddHeadline(summary)}
          </h2>
          <p className={addStyles.doneText}>{lines.join(" · ")}</p>
        </div>
        {!summary.complete ? (
          <Notice title="Parte do lote não entrou">
            Itens indisponíveis, recusados ou sem confirmação não foram contados como incluídos. Abra a Lista de desejos para
            conferir.
          </Notice>
        ) : null}
      </div>
      <Footer>
        <Button variant="outline" asChild>
          <Link href={WISHLIST_HREF}>Ver Lista de desejos</Link>
        </Button>
        <Button onClick={onClose}>Fechar</Button>
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
