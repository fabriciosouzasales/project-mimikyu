"use client";

import { useRouter } from "next/navigation";
import { type FormEvent, useEffect, useId, useRef, useState } from "react";
import { Check, Loader2, Pencil } from "lucide-react";
import { renameCollection, setCollectionCoverCode } from "@/app/colecoes/colecoes/actions";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  COLLECTION_NAME_MAX,
  type CollectionFailure,
  collectionFailureMessage,
  normalizeCollectionName,
} from "@/lib/colecoes/colecoes";
import { COVER_CODE_MAX, normalizeCoverCode, sanitizeCoverCodeInput } from "@/lib/colecoes/free-collection";
import acervoStyles from "../acervo/acervo.module.css";
import styles from "./colecoes.module.css";

/**
 * Título da coleção com "Renomear" no próprio lugar (contrato 5035).
 * Editar troca o título por um campo com Salvar/Cancelar; Esc cancela,
 * Enter salva. Durante a gravação o formulário fica bloqueado (sem envio
 * duplicado). O resultado aparece por alguns segundos ao lado do título.
 * Coleção arquivada não mostra a ação (o banco também recusaria).
 *
 * Coleção livre (`coverCode` informado): a mesma edição traz o Código
 * opcional da capa (5180), logo abaixo do nome — fora da edição ele não
 * aparece como campo, só na própria capa. Nome e código são gravados em
 * sequência, cada um só se mudou; vazio remove o código.
 */
export function CollectionTitle({
  collectionId,
  name,
  editable,
  coverCode,
}: {
  collectionId: string;
  name: string;
  editable: boolean;
  /** Presente só na Coleção livre com o recurso ligado: `null` = sem código. */
  coverCode?: string | null;
}) {
  const codeId = useId();
  const withCode = coverCode !== undefined;
  const [codeDraft, setCodeDraft] = useState(coverCode ?? "");
  const router = useRouter();
  const inputId = useId();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(name);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<CollectionFailure | null>(null);
  const [saved, setSaved] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const editRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (editing) inputRef.current?.select();
  }, [editing]);

  useEffect(() => {
    if (!saved) return;
    const timer = window.setTimeout(() => setSaved(false), 4000);
    return () => window.clearTimeout(timer);
  }, [saved]);

  const normalized = normalizeCollectionName(draft);
  const normalizedCode = withCode ? normalizeCoverCode(codeDraft) : null;
  const codeInvalid = normalizedCode === "invalid";
  const codeChanged = withCode && !codeInvalid && normalizedCode !== (coverCode ?? null);
  const unchanged = normalized === name && !codeChanged;

  const close = () => {
    setEditing(false);
    setError(null);
    setDraft(name);
    setCodeDraft(coverCode ?? "");
    // Devolve o foco ao botão que abriu a edição.
    window.requestAnimationFrame(() => editRef.current?.focus());
  };

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (pending || !normalized || codeInvalid) return;
    if (unchanged) {
      close();
      return;
    }
    setPending(true);
    setError(null);
    const fallback = { ok: false as const, reason: "unavailable" as const };
    if (normalized !== name) {
      const result = await renameCollection({ collectionId, name: normalized }).catch(() => fallback);
      if (!result.ok) {
        setPending(false);
        setError(result.reason);
        return;
      }
      setDraft(result.name);
    }
    if (codeChanged) {
      const result = await setCollectionCoverCode({ collectionId, code: normalizedCode === "invalid" ? null : normalizedCode }).catch(
        () => fallback,
      );
      if (!result.ok) {
        setPending(false);
        setError(result.reason);
        // O nome (se mudou) já foi gravado: a página reflete e o campo segue aberto para o código.
        router.refresh();
        return;
      }
      setCodeDraft(result.code ?? "");
    }
    setPending(false);
    setEditing(false);
    setSaved(true);
    router.refresh();
    window.requestAnimationFrame(() => editRef.current?.focus());
  };

  if (editing) {
    return (
      <form onSubmit={submit} className={styles.renameForm} onKeyDown={(event) => event.key === "Escape" && !pending && close()}>
        <label htmlFor={inputId} className="sr-only">
          Nome da coleção
        </label>
        <Input
          ref={inputRef}
          id={inputId}
          value={draft}
          maxLength={COLLECTION_NAME_MAX}
          onChange={(event) => setDraft(event.target.value)}
          disabled={pending}
          autoComplete="off"
          invalid={normalized === null || error !== null}
          aria-describedby={error ? `${inputId}-erro` : undefined}
          className={styles.renameInput}
        />
        {withCode ? (
          <div className={styles.renameCode}>
            <label htmlFor={codeId} className={styles.renameCodeLabel}>
              Código da capa <span className={styles.coverCodeOptional}>(opcional)</span>
            </label>
            <Input
              id={codeId}
              value={codeDraft}
              maxLength={COVER_CODE_MAX}
              onChange={(event) => setCodeDraft(sanitizeCoverCodeInput(event.target.value))}
              placeholder="Ex.: MMK"
              disabled={pending}
              autoComplete="off"
              spellCheck={false}
              invalid={codeInvalid}
              aria-describedby={`${codeId}-dica`}
              className={styles.coverCodeInput}
            />
            <span id={`${codeId}-dica`} className={styles.renameHint}>
              {codeInvalid ? "Use de 2 a 6 letras ou números — ou deixe em branco." : "De 2 a 6 letras ou números. Aparece na capa do fichário."}
            </span>
          </div>
        ) : null}
        <div className={styles.renameActions}>
          <Button type="submit" disabled={pending || normalized === null || codeInvalid} aria-busy={pending}>
            {pending ? <Loader2 className="h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden="true" /> : null}
            {pending ? "Salvando…" : "Salvar"}
          </Button>
          <Button type="button" variant="outline" onClick={close} disabled={pending}>
            Cancelar
          </Button>
        </div>
        {normalized === null ? <p className={styles.renameHint}>O nome não pode ficar vazio.</p> : null}
        {error ? (
          <p id={`${inputId}-erro`} className={styles.renameError} role="alert">
            {error === "not_found"
              ? "Esta coleção não pode ser renomeada agora (ela pode ter sido arquivada)."
              : collectionFailureMessage(error)}
          </p>
        ) : null}
      </form>
    );
  }

  return (
    <div className={styles.titleRow}>
      <h1 className={acervoStyles.title}>{name}</h1>
      {editable ? (
        <button
          ref={editRef}
          type="button"
          className={styles.renameButton}
          onClick={() => {
            setSaved(false);
            setDraft(name);
            setCodeDraft(coverCode ?? "");
            setEditing(true);
          }}
          aria-label={withCode ? "Editar nome e código da coleção" : "Renomear coleção"}
          title={withCode ? "Editar nome e código" : "Renomear"}
        >
          <Pencil className="h-4 w-4" aria-hidden="true" />
        </button>
      ) : null}
      <span className={styles.renameSaved} role="status" aria-live="polite">
        {saved ? (
          <>
            <Check className="h-3.5 w-3.5" aria-hidden="true" />
            {withCode ? "Alterações salvas" : "Nome atualizado"}
          </>
        ) : null}
      </span>
    </div>
  );
}
