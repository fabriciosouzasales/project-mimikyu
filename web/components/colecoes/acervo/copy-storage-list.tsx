"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useId, useMemo, useRef, useState, useTransition } from "react";
import { Box, Globe, Library, Loader2, MapPin, Star } from "lucide-react";
import { setMyCopiesStorage } from "@/app/colecoes/acervo/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { Select } from "@/components/ui/select";
import { type AcervoStorageFilter, formatCount, pluralize } from "@/lib/colecoes/acervo";
import { copyMatchesStorageFilter } from "@/lib/colecoes/acervo-storage-filter";
import {
  type CopyStorageFailure,
  STORAGE_BATCH_MAX,
  alreadyAtTarget,
  copyStorageFailureMessage,
  storageAssignConfirmation,
  storageAssignSuccess,
} from "@/lib/colecoes/copy-storage";
import { LOCAIS_PATH, type StorageLocation } from "@/lib/colecoes/storage-locations";
import { useDetailSheetLock } from "./acervo-detail-sheet";
import { CopyRemoveButton } from "./copy-remove-button";
import styles from "./acervo.module.css";
import local from "./copy-storage.module.css";

/**
 * WHERE-03 — "Seus exemplares" com a localização física de cada um.
 *
 * Cada linha mostra onde o exemplar está **guardado** (o local dele, C-58) e,
 * só como referência, o **local padrão da coleção** dele (preferência, NS-15)
 * — nunca aplicado sozinho. Marcar um ou mais exemplares abre, no rodapé do
 * painel, a escolha do local; gravar exige confirmação explícita a cada vez
 * (NS-13), inclusive para o "Local padrão". Identidade de local é sempre o id
 * (nunca o nome, que é renomeável).
 *
 * Escrita única: `setMyCopiesStorage` → `set_physical_cards_storage` (5024),
 * até 500 por vez, atômica e idempotente por estado. Só o local muda: coleção,
 * variante, idioma e quantidade ficam como estão.
 *
 * WHERE-04: com o filtro "Localização física" ativo na galeria, a lista continua
 * completa (todos os exemplares do item) e os que estão no local filtrado — ou
 * sem local — ganham destaque, com uma frase que explica por que os demais
 * também aparecem. Mover um exemplar atualiza o destaque na hora (mesmo
 * resultado provisório do WHERE-03) e a galeria por trás via `router.refresh()`.
 */

export type StorageCopy = {
  physicalCardId: string;
  copyNumber: number;
  collectionId: string | null;
  collectionName: string | null;
  storageName: string | null;
};

const CLEAR = "__clear__";
const ARIA_DISABLED_BUTTON = "aria-disabled:pointer-events-none aria-disabled:opacity-50";

type Step = { kind: "choose" } | { kind: "confirm" };

export function CopyStorageList({
  copies,
  languageName,
  copiesTotal,
  closeHref,
  storage,
  storageFilter = null,
}: {
  copies: StorageCopy[];
  languageName: string;
  copiesTotal: number;
  closeHref: string;
  /** `null` = contexto de localização indisponível (só leitura). */
  storage: {
    storageByCopy: Record<string, string | null>;
    locations: StorageLocation[];
    collectionDefaults: Record<string, string>;
  } | null;
  /** WHERE-04: filtro de local da galeria; `null` = sem filtro (sem destaque). */
  storageFilter?: { filter: AcervoStorageFilter; name: string | null } | null;
}) {
  const router = useRouter();
  const setSheetLocked = useDetailSheetLock();
  const selectId = useId();
  const confirmTitleId = useId();
  const confirmRef = useRef<HTMLHeadingElement>(null);
  const editable = storage !== null;
  // Um único exemplar já vem marcado: a escolha de local aparece direto, sem passo extra.
  const initialSelection = (): string[] => (copies.length === 1 && copies[0] ? [copies[0].physicalCardId] : []);
  const [selected, setSelected] = useState<string[]>(initialSelection);
  const [choice, setChoice] = useState<string>("");
  const [step, setStep] = useState<Step>({ kind: "choose" });
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<CopyStorageFailure | null>(null);
  // D3: o banco avisou que há exemplar num bolso do fichário digital — a próxima confirmação inclui tirar do bolso.
  const [binderConfirm, setBinderConfirm] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  // Resultado já gravado, mostrado até o servidor devolver a lista nova.
  const [patch, setPatch] = useState<{ ids: string[]; id: string | null; name: string | null } | null>(null);
  const inFlight = useRef(false);
  const [, startRefresh] = useTransition();

  // Lista nova do servidor: ela é a verdade — sai o resultado provisório e saem
  // da seleção exemplares que não existem mais (ex.: removidos na lixeira).
  useEffect(() => {
    setPatch(null);
    const present = new Set(copies.map((copy) => copy.physicalCardId));
    setSelected((current) => current.filter((id) => present.has(id)));
  }, [copies, storage]);
  useEffect(() => {
    if (step.kind === "confirm") confirmRef.current?.focus();
  }, [step]);

  const locationsById = useMemo(() => new Map((storage?.locations ?? []).map((l) => [l.id, l])), [storage]);
  const storageByCopy = useMemo(() => {
    const base = { ...(storage?.storageByCopy ?? {}) };
    if (patch) for (const id of patch.ids) base[id] = patch.id;
    return base;
  }, [storage, patch]);

  const nameOf = (copy: StorageCopy): string | null => {
    if (patch?.ids.includes(copy.physicalCardId)) return patch.name;
    return copy.storageName;
  };

  // WHERE-04: correspondência ao filtro por id do local (C-58). Sem o contexto de
  // localização, só "sem local" ainda é decidível (pelo nome ausente).
  const matchOf = (copy: StorageCopy): boolean | undefined => {
    if (!storageFilter) return undefined;
    if (copy.physicalCardId in storageByCopy) return copyMatchesStorageFilter(storageByCopy[copy.physicalCardId] ?? null, storageFilter.filter);
    if (storageFilter.filter.kind === "none") return nameOf(copy) === null;
    return undefined;
  };
  const matchStates = copies.map(matchOf);
  const matchKnown = storageFilter !== null && matchStates.every((m) => m !== undefined);
  const matchCount = matchStates.filter((m) => m === true).length;
  const filterWhere =
    storageFilter?.filter.kind === "none" ? "sem localização definida" : storageFilter?.name ? `em ${storageFilter.name}` : "no local filtrado";
  const matchPill = storageFilter?.filter.kind === "none" ? "Sem local" : "Neste local";

  // Locais que são o local padrão da coleção de algum exemplar marcado — só para identificar na lista.
  const suggested = useMemo(() => {
    const ids = new Set<string>();
    for (const copy of copies) {
      if (!selected.includes(copy.physicalCardId) || !copy.collectionId) continue;
      const preferred = storage?.collectionDefaults[copy.collectionId];
      if (preferred) ids.add(preferred);
    }
    return ids;
  }, [copies, selected, storage]);

  const target = choice === CLEAR ? null : choice || undefined;
  const targetLocation = target ? locationsById.get(target) ?? null : null;
  const already = target === undefined ? 0 : alreadyAtTarget(selected, storageByCopy, target);
  const toWrite = selected.length - already;
  const canProceed = editable && selected.length > 0 && target !== undefined && toWrite > 0 && !pending;
  const allSelected = selected.length === copies.length && copies.length > 0;

  const toggle = (id: string) => {
    if (pending) return;
    setNotice(null);
    setError(null);
    setStep({ kind: "choose" });
    setBinderConfirm(false);
    setSelected((current) => (current.includes(id) ? current.filter((x) => x !== id) : [...current, id]));
  };

  const save = async () => {
    if (inFlight.current || !canProceed || target === undefined) return;
    inFlight.current = true;
    setPending(true);
    setSheetLocked(true);
    setError(null);
    // Só os que mudam de fato; os que já estão no destino ficam como estão.
    const ids = selected.filter((id) => (storageByCopy[id] ?? null) !== target);
    try {
      const result = await setMyCopiesStorage({ physicalCardIds: ids, storageContainerId: target, unplaceFromBinder: binderConfirm }).catch(
        () => ({ ok: false, reason: "unavailable" }) as const,
      );
      if (!result.ok) {
        setError(result.reason);
        if (result.reason === "binder_positioned") {
          // Mantém a confirmação aberta: o próximo "Confirmar" tira do bolso e guarda, numa transação só.
          setBinderConfirm(true);
          setStep({ kind: "confirm" });
          return;
        }
        setBinderConfirm(false);
        setStep({ kind: "choose" });
        if (result.reason === "storage_gone") setChoice("");
        if (result.reason === "copies_gone") setSelected([]);
        if (result.reason === "storage_gone" || result.reason === "copies_gone") startRefresh(() => router.refresh());
        return;
      }
      const name = target === null ? null : (targetLocation?.name ?? null);
      setBinderConfirm(false);
      setPatch({ ids, id: target, name });
      setNotice(storageAssignSuccess(ids.length, name));
      setSelected(initialSelection());
      setChoice("");
      setStep({ kind: "choose" });
      startRefresh(() => router.refresh());
    } finally {
      inFlight.current = false;
      setPending(false);
      setSheetLocked(false);
    }
  };

  const confirmation =
    target === undefined
      ? null
      : storageAssignConfirmation({
          count: toWrite,
          targetName: target === null ? null : (targetLocation?.name ?? "local escolhido"),
          targetDefaultCollectionCount: targetLocation?.defaultCollectionCount ?? 0,
        });

  return (
    <>
      <div className={styles.sectionHead}>
        <h3 className={styles.sectionTitle}>Seus exemplares</h3>
        {editable && copies.length > 1 ? (
          <button
            type="button"
            className={local.selectAll}
            aria-disabled={pending || undefined}
            onClick={() => {
              if (pending) return;
              setNotice(null);
              setError(null);
              setStep({ kind: "choose" });
              setSelected(allSelected ? [] : copies.slice(0, STORAGE_BATCH_MAX).map((copy) => copy.physicalCardId));
            }}
          >
            {allSelected ? "Desmarcar todos" : "Marcar todos"}
          </button>
        ) : null}
      </div>
      {editable && copies.length > 1 ? (
        <p className={local.hint}>Marque os exemplares para escolher onde estão guardados.</p>
      ) : null}
      {!editable ? (
        <p className={local.hint}>Não foi possível carregar seus locais agora — a localização aparece só para consulta.</p>
      ) : null}

      {storageFilter ? (
        <p className={local.filterHint}>
          {!matchKnown
            ? "Mostrando todos os exemplares deste item."
            : matchCount === 0
              ? `Nenhum exemplar deste item está ${filterWhere} agora. Todos aparecem abaixo para você ver o item completo.`
              : matchCount === copies.length
                ? `${copies.length === 1 ? "Este exemplar está" : `Os ${formatCount(copies.length)} exemplares estão`} ${filterWhere}.`
                : `${formatCount(matchCount)} de ${pluralize(copies.length, "exemplar", "exemplares")} ${matchCount === 1 ? "está" : "estão"} ${filterWhere} — em destaque. Os demais aparecem para você ver o item completo.`}
        </p>
      ) : null}

      <div className={local.notice} role="status" aria-live="polite">
        {notice ? <InlineFeedback tone="success">{notice}</InlineFeedback> : null}
      </div>

      <ol className={styles.copies}>
        {copies.map((copy, index) => {
          const isSelected = selected.includes(copy.physicalCardId);
          const isMatch = matchKnown && matchStates[index] === true;
          const storedName = nameOf(copy);
          const preferredId = copy.collectionId ? storage?.collectionDefaults[copy.collectionId] : undefined;
          const preferred = preferredId ? locationsById.get(preferredId) ?? null : null;
          return (
            <li
              key={copy.physicalCardId}
              className={[styles.copy, editable ? local.copySelectable : null, isMatch ? local.copyMatch : null]
                .filter(Boolean)
                .join(" ")}
              data-selected={isSelected || undefined}
              data-match={isMatch || undefined}
            >
              {editable ? (
                <label className={local.check}>
                  <input
                    type="checkbox"
                    checked={isSelected}
                    aria-disabled={pending || undefined}
                    onChange={() => toggle(copy.physicalCardId)}
                    aria-label={`Marcar exemplar ${copy.copyNumber}`}
                  />
                </label>
              ) : null}
              <span className={styles.copyNumber} aria-hidden="true">
                {copy.copyNumber}
              </span>
              <div>
                <div className={styles.copyTitle}>
                  Exemplar {copy.copyNumber}
                  {isMatch ? (
                    <span className={local.matchPill}>
                      <MapPin className="h-3 w-3" aria-hidden="true" />
                      {matchPill}
                    </span>
                  ) : null}
                </div>
                <div className={styles.copyFacts}>
                  <span>
                    <Globe className="h-3 w-3" aria-hidden="true" />
                    {languageName}
                  </span>
                  <span>
                    <Library className="h-3 w-3" aria-hidden="true" />
                    {copy.collectionName ?? <span className={styles.unset}>Sem coleção</span>}
                  </span>
                  <span className={local.stored}>
                    <Box className="h-3 w-3" aria-hidden="true" />
                    {storedName ? (
                      <>
                        <span className={local.storedLabel}>Guardado em</span> {storedName}
                      </>
                    ) : (
                      <span className={styles.unset}>Sem localização definida</span>
                    )}
                  </span>
                </div>
                {preferred && copy.collectionName ? (
                  <p className={local.preference}>
                    <Star className="h-3 w-3" aria-hidden="true" />
                    Local padrão da coleção: {preferred.name} <span className="sr-only">(preferência, não a localização deste exemplar)</span>
                  </p>
                ) : null}
              </div>
              <CopyRemoveButton
                physicalCardId={copy.physicalCardId}
                copyNumber={copy.copyNumber}
                inCollection={copy.collectionName !== null}
                isLastCopy={copiesTotal === 1}
                closeHref={closeHref}
              />
            </li>
          );
        })}
      </ol>
      {copiesTotal > copies.length ? (
        <p className={styles.detailNote}>
          Mostrando os {formatCount(copies.length)} primeiros de {formatCount(copiesTotal)} exemplares.
        </p>
      ) : null}

      {editable && (selected.length > 0 || error) ? (
        <section
          className={local.bar}
          aria-label="Onde estão guardados os exemplares marcados"
          aria-busy={pending || undefined}
        >
          {step.kind === "choose" || !confirmation ? (
            <>
              <div className={local.barHead}>
                <span className={local.barCount}>
                  {selected.length === 0
                    ? "Nenhum exemplar marcado"
                    : `${pluralize(selected.length, "exemplar marcado", "exemplares marcados")}`}
                </span>
              </div>
              {storage.locations.length === 0 ? (
                <p className={local.barNote}>
                  Você ainda não tem locais.{" "}
                  <Link href={LOCAIS_PATH} className="text-primary-ink underline underline-offset-2">
                    Criar em Meus locais
                  </Link>
                </p>
              ) : null}
              <div className={local.barRow}>
                <div>
                  <label htmlFor={selectId} className="sr-only">
                    Guardar em
                  </label>
                  <Select
                    id={selectId}
                    value={choice}
                    className="h-11"
                    aria-disabled={pending || selected.length === 0 || undefined}
                    onChange={(event) => {
                      if (pending) return;
                      setChoice(event.target.value);
                      setError(null);
                      setNotice(null);
                      setBinderConfirm(false);
                    }}
                  >
                    <option value="" disabled>
                      Guardar em…
                    </option>
                    {storage.locations.map((location) => (
                      <option key={location.id} value={location.id}>
                        {location.name}
                        {location.kindLabel ? ` · ${location.kindLabel}` : ""}
                        {suggested.has(location.id) ? " · local padrão da coleção" : ""}
                      </option>
                    ))}
                    <option value={CLEAR}>Sem localização definida (remover local)</option>
                  </Select>
                </div>
                <Button
                  className={`min-h-11 px-5 ${ARIA_DISABLED_BUTTON}`}
                  aria-disabled={!canProceed || undefined}
                  onClick={() => {
                    if (!canProceed) return;
                    setError(null);
                    setStep({ kind: "confirm" });
                  }}
                >
                  <MapPin className="mr-1.5 h-4 w-4" aria-hidden="true" />
                  Guardar
                </Button>
              </div>
              {target !== undefined && selected.length > 0 && toWrite === 0 ? (
                <p className={local.barNote}>
                  {selected.length === 1 ? "Este exemplar já está" : "Todos os marcados já estão"}{" "}
                  {target === null ? "sem localização definida." : "nesse local."}
                </p>
              ) : target !== undefined && already > 0 ? (
                <p className={local.barNote}>
                  {pluralize(already, "exemplar já está", "exemplares já estão")} nesse destino e{" "}
                  {already === 1 ? "fica" : "ficam"} como {already === 1 ? "está" : "estão"}.
                </p>
              ) : null}
            </>
          ) : (
            <div role="group" aria-labelledby={confirmTitleId} className="flex flex-col gap-2.5">
              <h4 id={confirmTitleId} ref={confirmRef} tabIndex={-1} className={local.confirmTitle}>
                {confirmation.title}
              </h4>
              <p className={local.confirmBody}>{confirmation.body}</p>
              {confirmation.note ? <p className={local.barNote}>{confirmation.note}</p> : null}
              {binderConfirm ? (
                <p className={local.barNote}>Os exemplares que estão em bolsos do fichário digital saem dos bolsos ao confirmar.</p>
              ) : null}
              <div className={local.barRow}>
                <Button
                  className={`min-h-11 px-5 ${ARIA_DISABLED_BUTTON}`}
                  variant={target === null ? "outline" : "default"}
                  aria-disabled={pending || undefined}
                  onClick={() => void save()}
                >
                  {pending ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden="true" /> : null}
                  {pending ? "Guardando…" : binderConfirm ? "Tirar do fichário e guardar" : confirmation.action}
                </Button>
                <Button
                  variant="outline"
                  className={`min-h-11 ${ARIA_DISABLED_BUTTON}`}
                  aria-disabled={pending || undefined}
                  onClick={() => {
                    if (pending) return;
                    setBinderConfirm(false);
                    setStep({ kind: "choose" });
                  }}
                >
                  Voltar
                </Button>
              </div>
            </div>
          )}
          <div aria-live="assertive">{error ? <InlineFeedback tone="error">{copyStorageFailureMessage(error)}</InlineFeedback> : null}</div>
        </section>
      ) : null}
    </>
  );
}
