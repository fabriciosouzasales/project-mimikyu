"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useId, useRef, useState } from "react";
import { AlertTriangle, CheckCircle2, Crown, Loader2, Plus, Search, Sparkles, X } from "lucide-react";
import {
  linkPokedexCopy,
  readPokedexLinkCandidates,
  readPokedexPositionCopies,
  removePokedexLink,
  setPokedexRepresentative,
  unlinkCopyFromCollection,
} from "@/app/colecoes/colecoes/actions";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { SpeciesArtwork } from "@/components/pokedex/species-artwork";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { cardFrontUrl, formatCount } from "@/lib/colecoes/acervo";
import { collectionFailureMessage } from "@/lib/colecoes/colecoes";
import { type PokedexPosition, formatDex } from "@/lib/colecoes/pokedex";
import {
  type LinkFailure,
  type LinkScope,
  type PokedexLinkCandidate,
  type PokedexPositionCopy,
  LINK_QUERY_MAX,
  cardIdentityLine,
  copyAttributesLine,
  exceptionNote,
  exceptionWarning,
  linkFailureMessage,
} from "@/lib/colecoes/pokedex-link";
import { speciesArtworkUrl } from "@/lib/pokedex/artwork";
import { CardArt } from "../acervo/card-art";
import addStyles from "../acervo/acervo-add.module.css";
import acervoStyles from "../acervo/acervo.module.css";
import styles from "./pokedex.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const SEARCH_DEBOUNCE_MS = 300;

type ListState<T> =
  | { status: "loading" }
  | { status: "error"; reason: LinkFailure }
  | { status: "ready"; items: T[]; total: number; loadingMore: boolean };

/** Ação em andamento ou confirmação aberta — uma por vez no painel inteiro. */
type Pending =
  | { kind: "idle" }
  | { kind: "busy"; id: string }
  | { kind: "confirm-exception"; candidate: PokedexLinkCandidate }
  | { kind: "confirm-unlink"; copy: PokedexPositionCopy }
  | { kind: "confirm-remove"; copy: PokedexPositionCopy };

/**
 * Painel de uma posição da Pokédex (PKX-03) — abre ao tocar um Pokémon da
 * grade.
 *
 * - **Nesta posição** (5209): as cartas que representam este Pokémon, com
 *   idioma, acabamento e local. Escolher a representante (6125). Duas saídas
 *   distintas e sempre confirmadas: "Retirar desta posição" (6124 — a carta
 *   continua na coleção) e "Tirar da coleção" (5047 — volta a ficar livre no
 *   acervo).
 * - **Adicionar** (5208): "Mesmo Pokémon" lista os exemplares da espécie
 *   (vínculo normal, um toque). "Outra carta" busca no acervo e, ao escolher,
 *   mostra o aviso de divergência; só depois da confirmação explícita a 5210
 *   faz alocação e vínculo juntos. Nenhuma associação automática por nome.
 *
 * Toda escrita relê as listas e atualiza a página (grade e progresso).
 */
export function PokedexPositionPanel({
  collectionId,
  position,
  onClose,
}: {
  collectionId: string;
  position: PokedexPosition;
  onClose: () => void;
}) {
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const searchId = useId();
  const [copies, setCopies] = useState<ListState<PokedexPositionCopy>>({ status: "loading" });
  const [scope, setScope] = useState<LinkScope>("SPECIES");
  const [query, setQuery] = useState("");
  const [candidates, setCandidates] = useState<ListState<PokedexLinkCandidate>>({ status: "loading" });
  const [pending, setPending] = useState<Pending>({ kind: "idle" });
  const [feedback, setFeedback] = useState<{ tone: "success" | "error"; text: string } | null>(null);
  const requestRef = useRef(0);

  const dex = `#${formatDex(position.number)}`;
  const busy = pending.kind === "busy";
  const artUrl = speciesArtworkUrl(position.artworkPath);

  const loadCopies = useCallback(async () => {
    const result = await readPokedexPositionCopies({ collectionId, positionId: position.positionId }).catch(
      () => ({ ok: false, reason: "unavailable" }) as const,
    );
    setCopies(result.ok ? { status: "ready", items: result.items, total: result.total, loadingMore: false } : { status: "error", reason: result.reason });
  }, [collectionId, position.positionId]);

  const loadCandidates = useCallback(
    async (nextScope: LinkScope, nextQuery: string) => {
      const ticket = ++requestRef.current;
      setCandidates({ status: "loading" });
      const result = await readPokedexLinkCandidates({
        collectionId,
        positionId: position.positionId,
        scope: nextScope,
        query: nextQuery,
        offset: 0,
      }).catch(() => ({ ok: false, reason: "unavailable" }) as const);
      if (ticket !== requestRef.current) return; // resposta antiga (troca de aba/busca)
      setCandidates(result.ok ? { status: "ready", items: result.items, total: result.total, loadingMore: false } : { status: "error", reason: result.reason });
    },
    [collectionId, position.positionId],
  );

  useEffect(() => {
    void loadCopies();
  }, [loadCopies]);

  // Mesma espécie carrega na hora; a busca da exceção espera o usuário parar de digitar.
  useEffect(() => {
    if (scope === "SPECIES") {
      void loadCandidates("SPECIES", "");
      return;
    }
    const timer = window.setTimeout(() => void loadCandidates("ACERVO", query), SEARCH_DEBOUNCE_MS);
    return () => window.clearTimeout(timer);
  }, [scope, query, loadCandidates]);

  const loadMore = async () => {
    if (candidates.status !== "ready" || candidates.loadingMore || candidates.items.length >= candidates.total) return;
    const ticket = requestRef.current;
    setCandidates({ ...candidates, loadingMore: true });
    const result = await readPokedexLinkCandidates({
      collectionId,
      positionId: position.positionId,
      scope,
      query,
      offset: candidates.items.length,
    }).catch(() => ({ ok: false, reason: "unavailable" }) as const);
    if (ticket !== requestRef.current) return;
    if (!result.ok) {
      setCandidates({ ...candidates, loadingMore: false });
      setFeedback({ tone: "error", text: linkFailureMessage(result.reason) });
      return;
    }
    const known = new Set(candidates.items.map((item) => item.physicalCardId));
    setCandidates({
      status: "ready",
      items: [...candidates.items, ...result.items.filter((item) => !known.has(item.physicalCardId))],
      total: result.total,
      loadingMore: false,
    });
  };

  /** Depois de qualquer escrita: relê o painel e a página (grade + progresso). */
  const afterWrite = async (text: string) => {
    setFeedback({ tone: "success", text });
    setPending({ kind: "idle" });
    router.refresh();
    await Promise.all([loadCopies(), loadCandidates(scope, query)]);
  };

  const fail = (text: string) => {
    setFeedback({ tone: "error", text });
    setPending({ kind: "idle" });
  };

  const link = async (candidate: PokedexLinkCandidate, confirmException: boolean) => {
    if (busy) return;
    setFeedback(null);
    setPending({ kind: "busy", id: candidate.physicalCardId });
    const result = await linkPokedexCopy({
      collectionId,
      positionId: position.positionId,
      physicalCardId: candidate.physicalCardId,
      confirmException,
    }).catch(() => ({ ok: false, reason: "unavailable" }) as const);
    if (!result.ok) return fail(linkFailureMessage(result.reason));
    await afterWrite(
      result.basis === "USER_OVERRIDE"
        ? `${candidate.cardName} agora representa ${position.speciesName} nesta coleção (exceção).`
        : `${candidate.cardName} entrou em ${dex} ${position.speciesName}.`,
    );
  };

  const choose = (candidate: PokedexLinkCandidate) => {
    if (busy) return;
    setFeedback(null);
    if (candidate.speciesMatch) void link(candidate, false);
    else setPending({ kind: "confirm-exception", candidate });
  };

  const makeRepresentative = async (copy: PokedexPositionCopy) => {
    if (busy) return;
    setFeedback(null);
    setPending({ kind: "busy", id: copy.allocationId });
    const result = await setPokedexRepresentative({ collectionId, allocationId: copy.allocationId }).catch(
      () => ({ ok: false, reason: "unavailable" }) as const,
    );
    if (!result.ok) return fail(linkFailureMessage(result.reason));
    await afterWrite(`${copy.cardName} agora é a carta de ${position.speciesName} na grade.`);
  };

  const unlinkFromPosition = async (copy: PokedexPositionCopy) => {
    setPending({ kind: "busy", id: copy.allocationId });
    const result = await removePokedexLink({ collectionId, physicalCardId: copy.physicalCardId }).catch(
      () => ({ ok: false, reason: "unavailable" }) as const,
    );
    if (!result.ok) return fail(linkFailureMessage(result.reason));
    await afterWrite(`${copy.cardName} saiu desta posição e continua na coleção.`);
  };

  const removeFromCollection = async (copy: PokedexPositionCopy) => {
    setPending({ kind: "busy", id: copy.allocationId });
    const result = await unlinkCopyFromCollection({ collectionId, physicalCardId: copy.physicalCardId }).catch(
      () => ({ ok: false, reason: "unavailable" }) as const,
    );
    if (!result.ok) return fail(collectionFailureMessage(result.reason));
    await afterWrite(`${copy.cardName} saiu da coleção e está livre no seu acervo.`);
  };

  const linkedCount = copies.status === "ready" ? copies.total : position.copiesInCollection;
  const stateLine =
    linkedCount > 0 ? (
      <>
        <strong>Conquistado</strong> · {formatCount(linkedCount)} {linkedCount === 1 ? "carta nesta posição" : "cartas nesta posição"}
      </>
    ) : position.copiesAvailable > 0 ? (
      <>
        <strong>Falta</strong> · {formatCount(position.copiesAvailable)}{" "}
        {position.copiesAvailable === 1 ? "carta livre no seu acervo" : "cartas livres no seu acervo"}
      </>
    ) : position.copiesElsewhere > 0 ? (
      <>
        <strong>Falta</strong> · você tem {position.speciesName} em outra coleção
      </>
    ) : (
      <>
        <strong>Falta</strong> · nenhuma carta deste Pokémon no seu acervo
      </>
    );

  return (
    <DialogPrimitive.Root open onOpenChange={(next) => !next && !busy && onClose()}>
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
            <DialogPrimitive.Title className={addStyles.panelTitle}>
              {dex} · {position.speciesName}
            </DialogPrimitive.Title>
            <DialogPrimitive.Close
              disabled={busy}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          <div className={addStyles.body}>
            <div className={styles.panelHero}>
              <div className={styles.panelArt} aria-hidden="true">
                {artUrl ? <SpeciesArtwork src={artUrl} priority={false} /> : <Pokeball className="text-foreground/10" strokeWidth={1.25} />}
              </div>
              <div>
                <div className={styles.panelDex}>{dex}</div>
                <div className={styles.panelName}>{position.speciesName}</div>
                <p className={styles.panelState}>{stateLine}</p>
              </div>
            </div>

            <p className="sr-only" role="status" aria-live="polite">
              {feedback?.tone === "success" ? feedback.text : ""}
            </p>
            {feedback ? (
              feedback.tone === "success" ? (
                <div className={styles.statusLine} aria-hidden="true">
                  <CheckCircle2 className="h-4 w-4 shrink-0" />
                  {feedback.text}
                </div>
              ) : (
                <Notice title="Nada foi alterado">{feedback.text}</Notice>
              )
            ) : null}

            {/* ---- Nesta posição ---- */}
            {copies.status === "error" ? (
              <Notice title="Não conseguimos ler as cartas desta posição">{linkFailureMessage(copies.reason)}</Notice>
            ) : copies.status === "ready" && copies.items.length > 0 ? (
              <section className={styles.panelSection} aria-labelledby={`${searchId}-here`}>
                <div className={styles.panelSectionHead}>
                  <h3 id={`${searchId}-here`} className={styles.panelSectionTitle}>
                    Nesta posição
                  </h3>
                  {copies.items.length > 1 ? <span className={styles.panelSectionMeta}>a primeira aparece na grade</span> : null}
                </div>
                <ul className={styles.copyList}>
                  {copies.items.map((copy) => (
                    <LinkedCopy
                      key={copy.allocationId}
                      copy={copy}
                      showRepresentative={copies.items.length > 1}
                      pending={pending}
                      onRepresentative={() => void makeRepresentative(copy)}
                      onAskUnlink={() => setPending({ kind: "confirm-unlink", copy })}
                      onAskRemove={() => setPending({ kind: "confirm-remove", copy })}
                      onCancel={() => setPending({ kind: "idle" })}
                      onConfirmUnlink={() => void unlinkFromPosition(copy)}
                      onConfirmRemove={() => void removeFromCollection(copy)}
                    />
                  ))}
                </ul>
              </section>
            ) : null}

            {/* ---- Adicionar ---- */}
            <section className={styles.panelSection} aria-labelledby={`${searchId}-add`}>
              <div className={styles.panelSectionHead}>
                <h3 id={`${searchId}-add`} className={styles.panelSectionTitle}>
                  {linkedCount > 0 ? "Adicionar outra carta" : "Adicionar a esta posição"}
                </h3>
              </div>
              <div className={styles.segment} role="tablist" aria-label="De onde vem a carta">
                <button
                  type="button"
                  role="tab"
                  aria-selected={scope === "SPECIES"}
                  className={styles.segmentButton}
                  onClick={() => {
                    setPending({ kind: "idle" });
                    setScope("SPECIES");
                  }}
                  disabled={busy}
                >
                  {position.speciesName}
                  {scope === "SPECIES" && candidates.status === "ready" ? (
                    <span className={styles.segmentCount}>({formatCount(candidates.total)})</span>
                  ) : null}
                </button>
                <button
                  type="button"
                  role="tab"
                  aria-selected={scope === "ACERVO"}
                  className={styles.segmentButton}
                  onClick={() => {
                    setPending({ kind: "idle" });
                    setScope("ACERVO");
                  }}
                  disabled={busy}
                >
                  Outra carta
                </button>
              </div>

              {scope === "ACERVO" ? (
                <>
                  <p className={addStyles.hint}>
                    Use quando a carta mostra {position.speciesName}, mas o catálogo a registra com outro Pokémon. Você confirma
                    antes de qualquer mudança.
                  </p>
                  <div className={addStyles.searchWrap}>
                    <Search className={addStyles.searchIcon} aria-hidden="true" />
                    <label htmlFor={`${searchId}-q`} className="sr-only">
                      Buscar no seu acervo por nome, Set ou número
                    </label>
                    <Input
                      id={`${searchId}-q`}
                      className={addStyles.searchInput}
                      placeholder="Nome, Set ou número"
                      value={query}
                      maxLength={LINK_QUERY_MAX}
                      onChange={(event) => {
                        setPending({ kind: "idle" });
                        setQuery(event.target.value);
                      }}
                      autoComplete="off"
                    />
                  </div>
                </>
              ) : null}

              <CandidateList
                scope={scope}
                state={candidates}
                pending={pending}
                speciesName={position.speciesName}
                onChoose={choose}
                onLoadMore={() => void loadMore()}
                renderConfirm={(candidate) => {
                  const warning = exceptionWarning({
                    cardName: candidate.cardName,
                    cardSpeciesName: candidate.cardSpeciesName,
                    cardSpeciesNumber: candidate.cardSpeciesNumber,
                    positionSpeciesName: position.speciesName,
                    positionNumber: position.number,
                  });
                  return (
                    <div className={styles.confirm} data-tone="warning" role="alertdialog" aria-labelledby={`${searchId}-ex`}>
                      <p id={`${searchId}-ex`} className={styles.confirmTitle}>
                        <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
                        {warning.title}
                      </p>
                      <p>{warning.body}</p>
                      <div className={styles.confirmActions}>
                        <Button variant="outline" size="sm" onClick={() => setPending({ kind: "idle" })}>
                          Voltar
                        </Button>
                        <Button size="sm" onClick={() => void link(candidate, true)} autoFocus>
                          Confirmar exceção
                        </Button>
                      </div>
                    </div>
                  );
                }}
              />
            </section>
          </div>

          <div className={addStyles.footer}>
            <Link href={`/pokedex/${position.number}`} className="text-sm font-semibold text-muted-foreground underline-offset-4 hover:underline" prefetch={false}>
              Ver {position.speciesName} na Pokédex
            </Link>
            <div className={addStyles.footerActions}>
              <Button variant="outline" onClick={onClose} disabled={busy}>
                Fechar
              </Button>
            </div>
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function LinkedCopy({
  copy,
  showRepresentative,
  pending,
  onRepresentative,
  onAskUnlink,
  onAskRemove,
  onCancel,
  onConfirmUnlink,
  onConfirmRemove,
}: {
  copy: PokedexPositionCopy;
  showRepresentative: boolean;
  pending: Pending;
  onRepresentative: () => void;
  onAskUnlink: () => void;
  onAskRemove: () => void;
  onCancel: () => void;
  onConfirmUnlink: () => void;
  onConfirmRemove: () => void;
}) {
  const busyHere = pending.kind === "busy" && pending.id === copy.allocationId;
  const anyBusy = pending.kind === "busy";
  const askingUnlink = pending.kind === "confirm-unlink" && pending.copy.allocationId === copy.allocationId;
  const askingRemove = pending.kind === "confirm-remove" && pending.copy.allocationId === copy.allocationId;
  const exception = copy.basis === "USER_OVERRIDE";
  const identity = cardIdentityLine(copy);
  return (
    <li
      className={styles.copyItem}
      data-representative={showRepresentative && copy.isRepresentative ? "" : undefined}
      data-exception={exception ? "" : undefined}
    >
      <span className={styles.copyArt} aria-hidden="true">
        <CardArt src={cardFrontUrl(SUPABASE_URL, copy.imagePath)} alt="" name={copy.cardName} caption={identity} sizes="3.75rem" />
      </span>
      <div className={styles.copyBody}>
        <span className={styles.copyName}>{copy.cardName}</span>
        <span className={styles.copyMeta}>{[identity, copyAttributesLine(copy)].filter(Boolean).join(" · ")}</span>
        {(showRepresentative && copy.isRepresentative) || exception ? (
          <span className={styles.copyBadges}>
            {showRepresentative && copy.isRepresentative ? (
              <span className={`${styles.badge} ${styles.badgeRep}`}>
                <Crown className="h-3 w-3" aria-hidden="true" />
                Na grade
              </span>
            ) : null}
            {exception ? (
              <span className={`${styles.badge} ${styles.badgeException}`}>
                <Sparkles className="h-3 w-3" aria-hidden="true" />
                {exceptionNote(copy)}
              </span>
            ) : null}
          </span>
        ) : null}
        {!askingUnlink && !askingRemove ? (
          <span className={styles.copyActions}>
            {showRepresentative && !copy.isRepresentative ? (
              <button type="button" className={styles.copyAction} onClick={onRepresentative} disabled={anyBusy}>
                {busyHere ? "Salvando…" : "Mostrar na grade"}
              </button>
            ) : null}
            <button type="button" className={styles.copyAction} data-tone="quiet" onClick={onAskUnlink} disabled={anyBusy}>
              Retirar desta posição
            </button>
            <button type="button" className={styles.copyAction} data-tone="quiet" onClick={onAskRemove} disabled={anyBusy}>
              Tirar da coleção
            </button>
          </span>
        ) : null}
      </div>
      {askingUnlink || askingRemove ? (
        <div className={styles.confirm} role="alertdialog" aria-label={askingUnlink ? "Retirar desta posição" : "Tirar da coleção"}>
          <p className={styles.confirmTitle}>{askingUnlink ? "Retirar desta posição?" : "Tirar da coleção?"}</p>
          <p>
            {askingUnlink
              ? "A carta continua nesta coleção, sem posição — você pode colocá-la em outra depois. O Pokémon volta a faltar se for a única."
              : "A carta sai desta coleção e volta a ficar livre no seu acervo, no mesmo lugar. Nada muda no exemplar."}
          </p>
          <div className={styles.confirmActions}>
            <Button variant="outline" size="sm" onClick={onCancel} disabled={anyBusy}>
              Cancelar
            </Button>
            <Button
              size="sm"
              variant={askingRemove ? "destructive" : "default"}
              onClick={askingUnlink ? onConfirmUnlink : onConfirmRemove}
              disabled={anyBusy}
              aria-busy={busyHere}
              autoFocus
            >
              {busyHere ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : null}
              {askingUnlink ? "Retirar da posição" : "Tirar da coleção"}
            </Button>
          </div>
        </div>
      ) : null}
    </li>
  );
}

function CandidateList({
  scope,
  state,
  pending,
  speciesName,
  onChoose,
  onLoadMore,
  renderConfirm,
}: {
  scope: LinkScope;
  state: ListState<PokedexLinkCandidate>;
  pending: Pending;
  speciesName: string;
  onChoose: (candidate: PokedexLinkCandidate) => void;
  onLoadMore: () => void;
  renderConfirm: (candidate: PokedexLinkCandidate) => ReactNode;
}) {
  if (state.status === "loading") {
    return (
      <div className={addStyles.centerState} role="status">
        <Loader2 className={`h-5 w-5 ${addStyles.spin}`} aria-hidden="true" />
        Conferindo o seu acervo…
      </div>
    );
  }
  if (state.status === "error") return <Notice title="Não conseguimos ler o seu acervo">{linkFailureMessage(state.reason)}</Notice>;
  if (state.items.length === 0) {
    return (
      <p className={styles.emptyNote}>
        {scope === "SPECIES"
          ? `Nenhuma carta livre de ${speciesName} no seu acervo. Cartas em outras coleções não aparecem aqui.`
          : "Nenhuma carta livre encontrada. Tente outro nome, Set ou número."}
      </p>
    );
  }
  const anyBusy = pending.kind === "busy";
  return (
    <>
      <ul className={styles.copyList} aria-label={scope === "SPECIES" ? `Cartas de ${speciesName}` : "Outras cartas do acervo"}>
        {state.items.map((candidate) => {
          const busyHere = pending.kind === "busy" && pending.id === candidate.physicalCardId;
          const confirming = pending.kind === "confirm-exception" && pending.candidate.physicalCardId === candidate.physicalCardId;
          const identity = cardIdentityLine(candidate);
          const species =
            !candidate.speciesMatch && candidate.cardSpeciesName
              ? `${candidate.cardSpeciesName} (#${formatDex(candidate.cardSpeciesNumber ?? 0)})`
              : !candidate.speciesMatch
                ? "sem Pokémon catalogado"
                : null;
          return (
            <li key={candidate.physicalCardId} className={styles.copyItem}>
              <span className={styles.copyArt} aria-hidden="true">
                <CardArt src={cardFrontUrl(SUPABASE_URL, candidate.imagePath)} alt="" name={candidate.cardName} caption={identity} sizes="3.75rem" />
              </span>
              <div className={styles.copyBody}>
                <span className={styles.copyName}>{candidate.cardName}</span>
                <span className={styles.copyMeta}>{[identity, copyAttributesLine(candidate)].filter(Boolean).join(" · ")}</span>
                {species || candidate.inThisCollection ? (
                  <span className={styles.copyBadges}>
                    {species ? <span className={styles.badge}>{species}</span> : null}
                    {candidate.inThisCollection ? <span className={styles.badge}>Já nesta coleção, sem posição</span> : null}
                  </span>
                ) : null}
                {!confirming ? (
                  <span className={styles.copyActions}>
                    <Button
                      size="sm"
                      variant={candidate.speciesMatch ? "default" : "outline"}
                      className="h-9 gap-1.5"
                      onClick={() => onChoose(candidate)}
                      disabled={anyBusy}
                      aria-busy={busyHere}
                      aria-label={`${candidate.speciesMatch ? "Adicionar" : "Usar como exceção"}: ${candidate.cardName}, ${identity}`}
                    >
                      {busyHere ? <Loader2 className={`h-4 w-4 ${addStyles.spin}`} aria-hidden="true" /> : <Plus className="h-3.5 w-3.5" aria-hidden="true" />}
                      {busyHere ? "Adicionando…" : candidate.speciesMatch ? "Adicionar" : "Usar nesta posição"}
                    </Button>
                  </span>
                ) : null}
              </div>
              {confirming ? renderConfirm(candidate) : null}
            </li>
          );
        })}
      </ul>
      {state.items.length < state.total ? (
        <div className={styles.listMore}>
          <Button variant="ghost" size="sm" onClick={onLoadMore} disabled={state.loadingMore || anyBusy} aria-busy={state.loadingMore}>
            {state.loadingMore ? "Carregando…" : `Mostrar mais (${formatCount(state.total - state.items.length)})`}
          </Button>
        </div>
      ) : null}
    </>
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
