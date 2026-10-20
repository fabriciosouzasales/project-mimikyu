"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useRouter } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useRef, useState } from "react";
import { AlertTriangle, ArrowRight, Check, CheckCircle2, Layers, Loader2, X } from "lucide-react";
import { linkPokedexBulk, readPokedexBulkPreview } from "@/app/colecoes/colecoes/actions";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { SpeciesArtwork } from "@/components/pokedex/species-artwork";
import { Button } from "@/components/ui/button";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { cardFrontUrl, formatCount } from "@/lib/colecoes/acervo";
import { formatDex, generationTitle } from "@/lib/colecoes/pokedex";
import { type BulkPreviewItem, type LinkFailure, bulkLeftover, cardIdentityLine, linkFailureMessage } from "@/lib/colecoes/pokedex-link";
import { speciesArtworkUrl } from "@/lib/pokedex/artwork";
import { CardArt } from "../acervo/card-art";
import addStyles from "../acervo/acervo-add.module.css";
import acervoStyles from "../acervo/acervo.module.css";
import styles from "./colecoes.module.css";
import pkxStyles from "./pokedex.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

/**
 * "Completar com o acervo" (PKX-03) — inclusão em lote dos Pokémon que faltam.
 *
 * Prévia (5211): para cada Pokémon que falta (no filtro de geração atual) e
 * tem carta LIVRE da mesma espécie no acervo, a carta que o MMKYU sugere
 * (versão padrão, seu idioma, a mais antiga). Todas marcadas, com "Selecionar
 * todas" / "Limpar". Confirmação: UMA chamada à 5046 (até 500, tudo ou nada);
 * a 6119 cria os vínculos da mesma espécie. Nunca faz vínculo excepcional —
 * esses ficam no painel de cada Pokémon. O resultado diz o que entrou e o que
 * ficou de fora, e por quê.
 */
export function PokedexBulkLauncher({
  collectionId,
  generation,
  label = "Completar com o acervo",
  className = "h-8 gap-1.5 rounded-full px-3.5 text-[0.8125rem]",
  quietWhileFirstRun = false,
}: {
  collectionId: string;
  generation: string | null;
  /** Texto do botão (o aviso de primeiro uso usa outro). */
  label?: string;
  className?: string;
  /**
   * UX-05: enquanto o aviso de primeiro uso está na tela, o CTA dourado é o
   * dele — este botão fica contornado e volta ao destaque quando o aviso é
   * dispensado (ou some na primeira conquista, via nova renderização).
   */
  quietWhileFirstRun?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [quiet, setQuiet] = useState(quietWhileFirstRun);

  useEffect(() => {
    setQuiet(quietWhileFirstRun);
    if (!quietWhileFirstRun) return;
    const restore = () => setQuiet(false);
    window.addEventListener(POKEDEX_FIRST_RUN_DISMISSED_EVENT, restore);
    return () => window.removeEventListener(POKEDEX_FIRST_RUN_DISMISSED_EVENT, restore);
  }, [quietWhileFirstRun]);

  return (
    <>
      <Button size="sm" variant={quiet ? "outline" : "default"} className={className} onClick={() => setOpen(true)}>
        <Layers className="h-3.5 w-3.5" aria-hidden="true" />
        {label}
      </Button>
      {open ? (
        <PokedexBulkPanel
          collectionId={collectionId}
          generation={generation}
          onClose={() => {
            setOpen(false);
            // UX-05: a grade guarda o momento de conquista até o painel fechar.
            // Depois que o painel sai do DOM (dois quadros).
            window.requestAnimationFrame(() =>
              window.requestAnimationFrame(() => window.dispatchEvent(new Event(POKEDEX_DIALOG_CLOSED_EVENT))),
            );
          }}
        />
      ) : null}
    </>
  );
}

/** Disparado quando um painel da Pokédex fecha — a grade então celebra o que foi conquistado. */
export const POKEDEX_DIALOG_CLOSED_EVENT = "pkx:dialog-closed";

/** Disparado quando o aviso de primeiro uso é dispensado — o botão do topo volta ao destaque. */
export const POKEDEX_FIRST_RUN_DISMISSED_EVENT = "pkx:first-run-dismissed";

type Review =
  | { status: "loading" }
  | { status: "error"; reason: LinkFailure }
  | { status: "ready"; items: BulkPreviewItem[]; missingTotal: number; total: number };
type Commit =
  | { status: "idle" }
  | { status: "pending" }
  | { status: "error"; reason: LinkFailure }
  | { status: "done"; linked: number; offered: number; missingTotal: number };

function PokedexBulkPanel({ collectionId, generation, onClose }: { collectionId: string; generation: string | null; onClose: () => void }) {
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const [review, setReview] = useState<Review>({ status: "loading" });
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [commit, setCommit] = useState<Commit>({ status: "idle" });
  const busy = commit.status === "pending";

  const load = useCallback(async () => {
    setReview({ status: "loading" });
    setCommit({ status: "idle" });
    const result = await readPokedexBulkPreview({ collectionId, generation }).catch(() => ({ ok: false, reason: "unavailable" }) as const);
    if (!result.ok) {
      setReview({ status: "error", reason: result.reason });
      return;
    }
    setPicked(new Set(result.items.map((item) => item.physicalCardId)));
    setReview({ status: "ready", items: result.items, missingTotal: result.missingTotal, total: result.total });
  }, [collectionId, generation]);

  useEffect(() => {
    void load();
  }, [load]);

  const chosen = review.status === "ready" ? review.items.filter((item) => picked.has(item.physicalCardId)).map((item) => item.physicalCardId) : [];
  const chosenCount = chosen.length;
  const scopeLabel = generation ? generationTitle(generation) : "nesta Pokédex";

  const confirm = async () => {
    if (review.status !== "ready" || busy || chosenCount === 0) return;
    setCommit({ status: "pending" });
    const result = await linkPokedexBulk({ collectionId, physicalCardIds: chosen }).catch(() => ({ ok: false, reason: "unavailable" }) as const);
    if (!result.ok) {
      setCommit({ status: "error", reason: result.reason });
      return;
    }
    setCommit({ status: "done", linked: result.linked, offered: review.items.length, missingTotal: review.missingTotal });
    router.refresh();
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
          data-pkx-dialog=""
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => busy && event.preventDefault()}
          onPointerDownOutside={(event) => busy && event.preventDefault()}
          onCloseAutoFocus={restoreFocus}
        >
          <div className={acervoStyles.drawerHeader}>
            <DialogPrimitive.Title className={addStyles.panelTitle}>Completar com o acervo</DialogPrimitive.Title>
            <DialogPrimitive.Close
              disabled={busy}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          {commit.status === "done" ? (
            <Done commit={commit} onClose={onClose} />
          ) : review.status === "loading" ? (
            <div className={addStyles.body}>
              <div className={addStyles.centerState} role="status">
                <Loader2 className={`h-5 w-5 ${addStyles.spin}`} aria-hidden="true" />
                Procurando cartas para os Pokémon que faltam…
              </div>
            </div>
          ) : review.status === "error" ? (
            <>
              <div className={addStyles.body}>
                <Notice title="Não conseguimos preparar a revisão">{linkFailureMessage(review.reason)}</Notice>
              </div>
              <Footer>
                <Button variant="outline" onClick={onClose}>
                  Fechar
                </Button>
                <Button onClick={() => void load()}>Tentar novamente</Button>
              </Footer>
            </>
          ) : review.items.length === 0 ? (
            <>
              <div className={addStyles.body}>
                <div className={addStyles.done} role="status">
                  <span className={addStyles.doneIcon} aria-hidden="true">
                    <Pokeball className="h-6 w-6" />
                  </span>
                  <h2 className={addStyles.doneTitle}>Nada para completar agora</h2>
                  <p className={addStyles.doneText}>
                    {review.missingTotal > 0
                      ? `Faltam ${formatCount(review.missingTotal)} Pokémon ${scopeLabel}, mas nenhum tem carta livre da mesma espécie no seu acervo. Cartas em outras coleções não entram; para usar uma carta de outro Pokémon, abra o Pokémon na grade.`
                      : `Nenhum Pokémon falta ${scopeLabel}.`}
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
                  <span className={addStyles.reviewCount}>{formatCount(review.items.length)}</span>
                  <span className={addStyles.reviewLabel}>
                    {review.items.length === 1 ? "Pokémon que falta pode" : "Pokémon que faltam podem"} ser conquistados com cartas
                    livres do seu acervo — <strong>uma carta por Pokémon</strong>.
                  </span>
                </div>
                <p className={addStyles.reviewNote}>
                  Só entram cartas da mesma espécie que não estão em nenhuma coleção. Elas continuam no seu acervo, no mesmo lugar e
                  com os mesmos dados; a coleção só passa a contá-las.
                </p>

                <section aria-labelledby="pokedex-lote">
                  <div className={styles.pickHead}>
                    <h3 id="pokedex-lote" className={addStyles.sectionTitle}>
                      {formatCount(chosenCount)} de {formatCount(review.items.length)} marcados
                    </h3>
                    <span className={styles.pickTools}>
                      <Button
                        variant="ghost"
                        size="sm"
                        disabled={busy || chosenCount === review.items.length}
                        onClick={() => setPicked(new Set(review.items.map((item) => item.physicalCardId)))}
                      >
                        Selecionar todos
                      </Button>
                      <Button variant="ghost" size="sm" disabled={busy || chosenCount === 0} onClick={() => setPicked(new Set())}>
                        Limpar
                      </Button>
                    </span>
                  </div>
                  {review.total > review.items.length ? (
                    <p className={styles.fieldHint}>
                      Mostrando os primeiros {formatCount(review.items.length)}. Depois de confirmar, abra de novo para ver os demais.
                    </p>
                  ) : null}
                  <ul className={styles.pickList} aria-label="Pokémon que podem ser conquistados">
                    {review.items.map((item) => (
                      <PickRow
                        key={item.physicalCardId}
                        item={item}
                        picked={picked.has(item.physicalCardId)}
                        disabled={busy}
                        onToggle={() =>
                          setPicked((current) => {
                            const next = new Set(current);
                            if (next.has(item.physicalCardId)) next.delete(item.physicalCardId);
                            else next.add(item.physicalCardId);
                            return next;
                          })
                        }
                      />
                    ))}
                  </ul>
                </section>

                {commit.status === "error" ? <Notice title="Nenhum Pokémon foi conquistado">{linkFailureMessage(commit.reason)}</Notice> : null}
              </div>
              <Footer lead={chosenCount === 0 ? "Nenhum Pokémon marcado" : `${formatCount(chosenCount)} Pokémon`}>
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

function PickRow({ item, picked, disabled, onToggle }: { item: BulkPreviewItem; picked: boolean; disabled: boolean; onToggle: () => void }) {
  const dex = `#${formatDex(item.number)}`;
  const identity = cardIdentityLine(item);
  const artUrl = speciesArtworkUrl(item.artworkPath);
  const extra = item.eligibleCount > 1 ? ` · ${formatCount(item.eligibleCount)} livres` : "";
  return (
    <li className={styles.pickItem} data-picked={picked || undefined}>
      <label className={styles.pickRow}>
        <input
          type="checkbox"
          checked={picked}
          disabled={disabled}
          onChange={onToggle}
          className="sr-only"
          aria-label={`${dex} ${item.speciesName} com ${item.cardName}, ${identity}, ${item.languageName}`}
        />
        <span className={pkxStyles.bulkRow} aria-hidden="true" style={{ flex: 1, minWidth: 0 }}>
          <span className={pkxStyles.bulkSpecies}>
            {artUrl ? <SpeciesArtwork src={artUrl} priority={false} /> : <Pokeball className="text-foreground/10" strokeWidth={1.25} />}
          </span>
          <span className="min-w-0">
            <span className={styles.pickName}>
              {item.speciesName} <span className="font-normal text-muted-foreground">{dex}</span>
            </span>
            <span className={styles.pickNumber}>
              <ArrowRight className="mr-1 inline h-3 w-3" />
              {item.cardName} · {[identity, item.languageName, item.variantLabel].filter(Boolean).join(" · ")}
              {extra}
            </span>
          </span>
          <span className={pkxStyles.bulkCard}>
            <CardArt src={cardFrontUrl(SUPABASE_URL, item.imagePath)} alt="" name={item.cardName} caption={identity} sizes="2.25rem" />
          </span>
          <span className={styles.pickCheck}>{picked ? <Check className="h-4 w-4" /> : null}</span>
        </span>
      </label>
    </li>
  );
}

function Done({ commit, onClose }: { commit: { linked: number; offered: number; missingTotal: number }; onClose: () => void }) {
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => headingRef.current?.focus(), []);
  const leftover = bulkLeftover(commit);
  return (
    <>
      <div className={addStyles.body}>
        <div className={addStyles.done} role="status">
          <span className={addStyles.doneIcon} aria-hidden="true">
            <CheckCircle2 className="h-6 w-6" />
          </span>
          <h2 ref={headingRef} tabIndex={-1} className={addStyles.doneTitle}>
            {commit.linked === 1 ? "1 Pokémon conquistado" : `${formatCount(commit.linked)} Pokémon conquistados`}
          </h2>
          <p className={addStyles.doneText}>
            O progresso da Pokédex já está atualizado. As cartas continuam no seu acervo, no mesmo lugar.
          </p>
          {leftover ? <p className={addStyles.doneText}>Ficou de fora: {leftover}</p> : null}
        </div>
      </div>
      <Footer>
        <Button onClick={onClose}>Ver a Pokédex</Button>
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
