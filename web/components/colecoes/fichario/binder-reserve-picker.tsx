"use client";

import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Bookmark, BookmarkX, Loader2, RotateCcw, Search, TriangleAlert, X } from "lucide-react";
import { readReservationCandidates } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import { cardFrontUrl, formatCollectorNumber } from "@/lib/colecoes/acervo";
import type { BinderSlot } from "@/lib/colecoes/binder";
import {
  DUPLICATE_RESERVATION_WARNING,
  type ReserveCandidate,
  type ReserveExcluded,
  type ReserveScope,
  type ReserveTarget,
  duplicateReservationCount,
  filterCandidates,
  sameReservation,
} from "@/lib/colecoes/binder-reserve";
import styles from "./binder-add-pages.module.css";
import { useDialogKeys } from "./binder-image-editor";
import own from "./binder-reserve.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
/** Posições mostradas por vez (as do objetivo chegam todas; a busca filtra todas). */
const SHOW_STEP = 60;

type Load =
  | { status: "loading" }
  | { status: "error" }
  | { status: "unsupported" }
  | {
      status: "ready";
      /** Coleção a que estas cartas pertencem (a escolha só grava quando é a mesma do seletor). */
      collectionId: string;
      scope: ReserveScope;
      items: ReserveCandidate[];
      total: number;
      complete: boolean;
      loadingMore?: boolean;
    };

/**
 * V1-07 — "Reservar para uma carta…" / "Trocar carta reservada": escolher a
 * carta para um bolso vazio. Mesmo diálogo escuro do "Adicionar carta"
 * (`binder-pocket-picker`, estilos `binder-add-pages`), mesmo teclado (Esc
 * fecha, Tab preso, foco volta ao bolso — `useDialogKeys`).
 *
 * Origem das cartas (D1), lida no servidor pela coleção: posições do objetivo
 * no Set padrão e no Master Set (busca local por nome, número ou acabamento);
 * busca no catálogo na coleção livre. Escolher marca a carta; o rodapé mostra
 * o que será reservado, o aviso de reserva duplicada (D5, só informativo) e a
 * confirmação. Nada é movido: reservar é registrar a intenção.
 *
 * Coleção da reserva (D3 revisada): com mais de uma coleção vinculada ao
 * fichário, "Reserva para a coleção" escolhe entre a dona e as convidadas; a
 * lista de cartas segue o tipo da coleção escolhida. Trocar de coleção limpa a
 * carta escolhida e a busca. Na troca de reserva, a coleção é a original (fixa).
 */
export function ReservePicker({
  host,
  target,
  pageNumber,
  collectionId,
  mode,
  targets,
  excluded = [],
  initialCollectionId,
  ownerCollectionId,
  loadedSlots,
  busy,
  onConfirm,
  onCollectionChange,
  onRelease,
  onClose,
}: {
  host: HTMLElement | null;
  target: BinderSlot;
  pageNumber: number;
  /** Coleção pela qual o fichário está aberto (contexto das leituras no servidor). */
  collectionId: string;
  mode: "reserve" | "change";
  /** Coleções do fichário que podem receber a reserva (proprietária primeiro). */
  targets: readonly ReserveTarget[];
  /** Coleções do fichário fora da escolha (arquivada, Pokédex) — só explicação. */
  excluded?: readonly ReserveExcluded[];
  /** Coleção inicial: a da reserva (troca) ou a última escolhida neste fichário. */
  initialCollectionId: string;
  ownerCollectionId: string;
  /** Bolsos já carregados (aviso de duplicidade sem leitura nova). */
  loadedSlots: readonly BinderSlot[];
  busy: boolean;
  onConfirm: (candidate: ReserveCandidate, reservationCollectionId: string) => void;
  /** Lembrar a escolha enquanto o fichário estiver aberto. */
  onCollectionChange?: (collectionId: string) => void;
  onRelease: () => void;
  onClose: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const searchId = useId();
  const collectionLabelId = useId();
  const [reserveCollection, setReserveCollection] = useState(initialCollectionId);
  const [load, setLoad] = useState<Load>({ status: "loading" });
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<ReserveCandidate | null>(null);
  const [shown, setShown] = useState(SHOW_STEP);
  const seq = useRef(0);
  const lastQuery = useRef<string | null>(null);
  const chosen = targets.find((t) => t.collectionId === reserveCollection) ?? null;
  // Troca de reserva: fica na coleção original; nova reserva: escolha quando há mais de uma coleção.
  const canSwitch = mode === "reserve" && targets.length > 1;

  const fetchPage = useCallback(
    async (q: string, offset: number) => {
      const id = ++seq.current;
      lastQuery.current = q;
      if (offset === 0) setLoad({ status: "loading" });
      else setLoad((prev) => (prev.status === "ready" ? { ...prev, loadingMore: true } : prev));
      const result = await readReservationCandidates({ collectionId, targetCollectionId: reserveCollection, query: q, offset }).catch(() => ({
        ok: false as const,
        reason: "unavailable" as const,
      }));
      if (id !== seq.current) return;
      if (!result.ok) {
        setLoad(result.reason === "unsupported" ? { status: "unsupported" } : { status: "error" });
        return;
      }
      setLoad((prev) => ({
        status: "ready",
        collectionId: reserveCollection,
        scope: result.scope,
        items: offset > 0 && prev.status === "ready" && prev.collectionId === reserveCollection ? [...prev.items, ...result.candidates] : result.candidates,
        total: result.total,
        complete: result.complete,
      }));
    },
    [collectionId, reserveCollection],
  );

  // Abre (e a cada coleção escolhida) carregando as posições do objetivo (Set/Master Set) ou o estado inicial da busca (livre).
  useEffect(() => {
    void fetchPage("", 0);
  }, [fetchPage]);

  const free = load.status === "ready" && load.scope === "FREE";
  // Coleção livre: busca no catálogo com espera curta; só a resposta mais recente vale.
  useEffect(() => {
    if (!free || query.trim() === lastQuery.current) return;
    const timer = window.setTimeout(() => void fetchPage(query.trim(), 0), 280);
    return () => window.clearTimeout(timer);
  }, [fetchPage, free, query]);

  const switchCollection = (next: string) => {
    if (next === reserveCollection || busy) return;
    // Nada da coleção anterior sobrevive: carta escolhida, busca e páginas.
    setSelected(null);
    setQuery("");
    setShown(SHOW_STEP);
    setLoad({ status: "loading" });
    setReserveCollection(next);
    onCollectionChange?.(next);
  };

  useDialogKeys(dialogRef, busy ? () => {} : onClose, !busy);

  const visible = useMemo(() => {
    if (load.status !== "ready" || load.collectionId !== reserveCollection) return [];
    const list = load.scope === "FREE" ? load.items : filterCandidates(load.items, query);
    // A reserva atual (troca) aparece primeiro.
    return mode === "change" ? [...list].sort((a, b) => Number(sameReservation(target, b)) - Number(sameReservation(target, a))) : list;
  }, [load, mode, query, reserveCollection, target]);

  const ready = load.status === "ready" && load.collectionId === reserveCollection;
  const duplicates = selected ? duplicateReservationCount(loadedSlots, selected, target.slotId, reserveCollection, ownerCollectionId) : 0;
  const roleText = (t: ReserveTarget) => (t.role === "OWNER" ? "Dona" : "Convidada");
  const unchanged = mode === "change" && selected !== null && sameReservation(target, selected) && (selected.variantTypeId ?? null) === (target.expectedVariantTypeId ?? null);

  if (!host) return null;
  const where = `Página ${pageNumber} · linha ${target.row}, coluna ${target.column}`;
  const describe = (c: ReserveCandidate) =>
    [c.collectorNumber ? formatCollectorNumber(c.collectorNumber, c.collectorTotal) : null, c.setCode?.toUpperCase() ?? null, c.finishName].filter(Boolean).join(" · ");

  return createPortal(
    <div className={styles.veil} onPointerDown={(event) => event.target === event.currentTarget && !busy && onClose()}>
      <div ref={dialogRef} role="dialog" aria-modal="true" aria-labelledby={titleId} aria-busy={busy || undefined} tabIndex={-1} className={styles.dialog} data-wide>
        <div className={styles.head}>
          <span className={styles.icon} aria-hidden>
            <Bookmark />
          </span>
          <div>
            <h2 id={titleId} className={styles.title}>
              {mode === "change" ? "Trocar carta reservada" : "Reservar para uma carta"}
            </h2>
            <p className={styles.lead}>
              {where}
              {mode === "change" && target.expected ? ` · reservado para ${target.expected.cardName}` : ""}
            </p>
          </div>
          <button type="button" className={styles.close} onClick={onClose} aria-label="Fechar" disabled={busy}>
            <X aria-hidden />
          </button>
        </div>

        {canSwitch ? (
          <div className={own.collections}>
            <p id={collectionLabelId} className={own.collectionsLabel}>
              Reserva para a coleção
            </p>
            <div role="radiogroup" aria-labelledby={collectionLabelId} className={own.collectionList}>
              {targets.map((t) => (
                <label key={t.collectionId} className={own.collectionOption} data-checked={t.collectionId === reserveCollection || undefined}>
                  <input
                    type="radio"
                    name={collectionLabelId}
                    value={t.collectionId}
                    checked={t.collectionId === reserveCollection}
                    onChange={() => switchCollection(t.collectionId)}
                    disabled={busy}
                  />
                  <span className={own.collectionName} title={t.name}>
                    {t.name}
                  </span>
                  <span className={own.collectionRole} data-owner={t.role === "OWNER" || undefined}>
                    {roleText(t)}
                  </span>
                </label>
              ))}
            </div>
            {excluded.length > 0 ? (
              <p className={own.collectionsNote}>
                {excluded.map((e) => `${e.name} (${e.reason === "pokedex" ? "Pokédex — organizada pela espécie" : e.reason === "archived" ? "arquivada" : "sem reserva por carta"})`).join(" · ")} não recebe reserva por carta.
              </p>
            ) : null}
          </div>
        ) : chosen && (targets.length > 1 || chosen.role === "GUEST") ? (
          <p className={own.collectionFixed}>
            {mode === "change" ? "Reserva da coleção" : "Reserva para a coleção"} <strong>{chosen.name}</strong>
            <span className={own.collectionRole} data-owner={chosen.role === "OWNER" || undefined}>
              {roleText(chosen)}
            </span>
          </p>
        ) : null}

        {load.status === "unsupported" ? (
          <p className={styles.emptyState}>
            <strong>Reserva por carta indisponível nesta coleção</strong>
            Nesta coleção o bolso é organizado pela espécie. Use “Adicionar carta” para colocar um exemplar.
          </p>
        ) : (
          <>
            <label htmlFor={searchId} className={own.search}>
              <Search aria-hidden />
              <span className="sr-only">{free ? "Buscar carta no catálogo" : "Buscar carta do objetivo"}</span>
              <input
                id={searchId}
                type="search"
                value={query}
                autoComplete="off"
                placeholder={free ? "Nome ou número da carta (ex.: Pikachu, 25/88)" : "Nome, número ou acabamento"}
                onChange={(event) => {
                  setQuery(event.target.value);
                  setShown(SHOW_STEP);
                }}
              />
            </label>

            {load.status === "loading" || (load.status === "ready" && !ready) ? (
              <ul className={styles.pickGrid} aria-busy="true" aria-label="Carregando cartas">
                {Array.from({ length: 6 }).map((_, index) => (
                  <li key={index} className={styles.skeletonCard} />
                ))}
              </ul>
            ) : load.status === "error" ? (
              <div className={styles.emptyState} role="alert">
                <strong>Não conseguimos carregar as cartas.</strong>
                Nada mudou no fichário.
                <div className={`${styles.loadMore} mt-3`}>
                  <button type="button" className={styles.secondary} onClick={() => void fetchPage(query.trim(), 0)}>
                    <RotateCcw className="h-3.5 w-3.5" aria-hidden />
                    Tentar de novo
                  </button>
                </div>
              </div>
            ) : visible.length === 0 ? (
              <p className={styles.emptyState}>
                {free && query.trim().length < 2 ? (
                  <>
                    <strong>Busque a carta no catálogo</strong>
                    Digite ao menos 2 letras do nome ou o número. Pode ser uma carta que você ainda não tem.
                  </>
                ) : (
                  <>
                    <strong>Nenhuma carta encontrada</strong>
                    Confira o nome ou tente pelo número.
                  </>
                )}
              </p>
            ) : (
              <ul className={styles.pickGrid} aria-label="Cartas — escolha a que este bolso vai guardar">
                {visible.slice(0, free ? visible.length : shown).map((c) => {
                  const current = mode === "change" && sameReservation(target, c);
                  const isSelected = selected?.key === c.key;
                  const detail = describe(c);
                  const src = cardFrontUrl(SUPABASE_URL, c.imagePath);
                  return (
                    <li key={c.key}>
                      <button
                        type="button"
                        className={styles.pick}
                        data-reserved={isSelected || undefined}
                        aria-pressed={isSelected}
                        aria-label={`${c.cardName}${detail ? `, ${detail}` : ""}${c.owned === false ? ", ainda falta na coleção" : ""}${current ? " (reserva atual)" : ""}`}
                        title={`${c.cardName}${detail ? ` — ${detail}` : ""}`}
                        onClick={() => setSelected(c)}
                        disabled={busy}
                      >
                        {src ? (
                          // eslint-disable-next-line @next/next/no-img-element -- mesmo asset dos bolsos (cache do navegador)
                          <img src={src} alt="" loading="lazy" decoding="async" draggable={false} />
                        ) : (
                          <span className={styles.pickFallback}>{c.cardName}</span>
                        )}
                        {current ? <span className={styles.pickBadge}>Reserva atual</span> : isSelected ? <span className={styles.pickBadge}>Escolhida</span> : null}
                      </button>
                      <p className={styles.pickCaption}>{detail || c.cardName}</p>
                    </li>
                  );
                })}
              </ul>
            )}

            {load.status === "ready" && !free && visible.length > shown ? (
              <div className={`${styles.loadMore} mt-1`}>
                <button type="button" className={styles.secondary} onClick={() => setShown((n) => n + SHOW_STEP)}>
                  Mostrar mais {(visible.length - shown).toLocaleString("pt-BR")}
                </button>
              </div>
            ) : null}
            {load.status === "ready" && free && !load.complete ? (
              <div className={`${styles.loadMore} mt-1`}>
                <button type="button" className={styles.secondary} onClick={() => void fetchPage(query.trim(), load.items.length)} disabled={load.loadingMore}>
                  {load.loadingMore ? <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden /> : null}
                  Mostrar mais
                </button>
              </div>
            ) : null}
            {load.status === "ready" && !free && !load.complete ? (
              <p className={own.notice} role="status">
                Algumas posições não carregaram agora; a lista pode estar incompleta.
              </p>
            ) : null}

            <div className={own.choice} aria-live="polite">
              {selected ? (
                <>
                  <p className={own.choiceText}>
                    Reservar para <strong>{selected.cardName}</strong>
                    {describe(selected) ? <span> · {describe(selected)}</span> : null}
                    {chosen && targets.length > 1 ? <span> · coleção {chosen.name}</span> : null}
                  </p>
                  {duplicates > 0 ? (
                    <p className={own.warning}>
                      <TriangleAlert aria-hidden />
                      {DUPLICATE_RESERVATION_WARNING}
                    </p>
                  ) : null}
                </>
              ) : (
                <p className={own.choiceHint}>Escolha a carta que este bolso vai guardar — pode ser uma que você ainda não tem.</p>
              )}
            </div>

            <div className={own.actions}>
              {mode === "change" ? (
                <button type="button" className={styles.secondary} onClick={onRelease} disabled={busy}>
                  <BookmarkX className="h-3.5 w-3.5" aria-hidden />
                  Liberar reserva
                </button>
              ) : null}
              <span className={own.spacer} />
              <button type="button" className={styles.secondary} onClick={onClose} disabled={busy}>
                Cancelar
              </button>
              <button
                type="button"
                className={styles.primary}
                onClick={() => selected && ready && onConfirm(selected, reserveCollection)}
                disabled={!selected || !ready || busy || unchanged}
              >
                {busy ? <Loader2 className="animate-spin" aria-hidden /> : <Bookmark aria-hidden />}
                {mode === "change" ? "Trocar reserva" : "Reservar bolso"}
              </button>
            </div>
          </>
        )}

        <p className={styles.note}>Reservar guarda o lugar para a carta: nada muda de lugar, e a reserva não conta como progresso.</p>
      </div>
    </div>,
    host,
  );
}
