"use client";

import { useRouter } from "next/navigation";
import { type FormEvent, useEffect, useId, useRef, useState } from "react";
import { ImagePlus, Loader2, Trash2 } from "lucide-react";
import { renameCollection, setCollectionCoverCode } from "@/app/colecoes/colecoes/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  COLLECTION_NAME_MAX,
  type CollectionFailure,
  collectionFailureMessage,
  normalizeCollectionName,
} from "@/lib/colecoes/colecoes";
import { COVER_CODE_MAX, normalizeCoverCode, sanitizeCoverCodeInput } from "@/lib/colecoes/free-collection";
import { useCoverLogo } from "./cover-logo-uploader";
import styles from "./collection-manage.module.css";

/**
 * Ajustes → Identidade (UX-06, decisão de Fabrício, 2026-10-19): nome, código
 * e imagem da capa deixam a página da coleção e passam a ser editados aqui,
 * junto com a cor do fichário — em todas as coleções, cada uma com o que já
 * suportava (código e imagem: Coleção livre e Pokédex).
 *
 * Mesmos contratos de antes, sem SQL novo: renomear (5035), código da capa
 * (5180) e imagem (5178, envio seguro em `useCoverLogo`).
 */

/** Nome e (quando a coleção tem) código da capa. Salvar só com mudança válida. */
export function IdentityNameForm({
  collectionId,
  name,
  coverCode,
  onBusyChange,
}: {
  collectionId: string;
  name: string;
  /** `undefined` = a coleção não tem código; `null` = sem código. */
  coverCode?: string | null;
  onBusyChange: (busy: boolean) => void;
}) {
  const router = useRouter();
  const nameId = useId();
  const codeId = useId();
  const withCode = coverCode !== undefined;
  const [draft, setDraft] = useState(name);
  const [codeDraft, setCodeDraft] = useState(coverCode ?? "");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<{ reason: CollectionFailure; source: "name" | "code" } | null>(null);
  const [saved, setSaved] = useState(false);

  // Depois de salvar, a página recarrega com os valores gravados.
  const lastName = useRef(name);
  const lastCode = useRef(coverCode ?? "");
  useEffect(() => {
    if (lastName.current !== name) {
      lastName.current = name;
      setDraft(name);
    }
    if (lastCode.current !== (coverCode ?? "")) {
      lastCode.current = coverCode ?? "";
      setCodeDraft(coverCode ?? "");
    }
  }, [name, coverCode]);

  useEffect(() => {
    if (!saved) return;
    const timer = window.setTimeout(() => setSaved(false), 4000);
    return () => window.clearTimeout(timer);
  }, [saved]);

  const normalized = normalizeCollectionName(draft);
  const normalizedCode = withCode ? normalizeCoverCode(codeDraft) : null;
  const codeInvalid = normalizedCode === "invalid";
  const nameChanged = normalized !== null && normalized !== name;
  const codeChanged = withCode && !codeInvalid && normalizedCode !== (coverCode ?? null);
  const canSave = !pending && normalized !== null && !codeInvalid && (nameChanged || codeChanged);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!canSave || normalized === null) return;
    setPending(true);
    onBusyChange(true);
    setError(null);
    setSaved(false);
    const fallback = { ok: false as const, reason: "unavailable" as const };
    try {
      if (nameChanged) {
        const result = await renameCollection({ collectionId, name: normalized }).catch(() => fallback);
        if (!result.ok) {
          setError({ reason: result.reason, source: "name" });
          return;
        }
        setDraft(result.name);
      }
      if (codeChanged) {
        const result = await setCollectionCoverCode({ collectionId, code: normalizedCode === "invalid" ? null : normalizedCode }).catch(
          () => fallback,
        );
        if (!result.ok) {
          setError({ reason: result.reason, source: "code" });
          // O nome (se mudou) já foi gravado: a página reflete; o código segue no campo para nova tentativa.
          router.refresh();
          return;
        }
        setCodeDraft(result.code ?? "");
      }
      setSaved(true);
      router.refresh();
    } finally {
      setPending(false);
      onBusyChange(false);
    }
  };

  return (
    <form className={styles.identityForm} onSubmit={submit} noValidate>
      <div className={styles.identityField}>
        <Label htmlFor={nameId}>Nome</Label>
        <Input
          id={nameId}
          value={draft}
          maxLength={COLLECTION_NAME_MAX}
          onChange={(event) => {
            setDraft(event.target.value);
            setSaved(false);
          }}
          disabled={pending}
          autoComplete="off"
          invalid={normalized === null || error?.source === "name"}
          aria-describedby={normalized === null ? `${nameId}-dica` : undefined}
        />
        {normalized === null ? (
          <span id={`${nameId}-dica`} className={styles.identityHint}>
            O nome não pode ficar vazio.
          </span>
        ) : null}
      </div>

      {withCode ? (
        <div className={styles.identityField}>
          <Label htmlFor={codeId}>
            Código da capa <span className={styles.identityOptional}>(opcional)</span>
          </Label>
          <Input
            id={codeId}
            value={codeDraft}
            maxLength={COVER_CODE_MAX}
            onChange={(event) => {
              setCodeDraft(sanitizeCoverCodeInput(event.target.value));
              setSaved(false);
            }}
            placeholder="Ex.: MMK"
            disabled={pending}
            autoComplete="off"
            spellCheck={false}
            invalid={codeInvalid || error?.source === "code"}
            aria-describedby={`${codeId}-dica`}
            className={styles.identityCodeInput}
          />
          <span id={`${codeId}-dica`} className={styles.identityHint}>
            {codeInvalid ? "Use de 2 a 6 letras ou números — ou deixe em branco." : "De 2 a 6 letras ou números. Aparece na capa do fichário."}
          </span>
        </div>
      ) : null}

      <div className={styles.identityActions}>
        <Button type="submit" className="min-h-11" disabled={!canSave} aria-busy={pending}>
          {pending ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden="true" /> : null}
          {pending ? "Salvando…" : "Salvar"}
        </Button>
      </div>

      <div aria-live="polite">
        {saved ? <InlineFeedback tone="success">{withCode ? "Nome e código salvos." : "Nome atualizado."}</InlineFeedback> : null}
        {error ? (
          <InlineFeedback tone="error">
            {error.reason === "not_found"
              ? error.source === "code"
                ? "Não foi possível salvar o código desta coleção agora. Nada foi alterado no código."
                : "Esta coleção não pode ser renomeada agora (ela pode ter sido arquivada)."
              : collectionFailureMessage(error.reason)}
          </InlineFeedback>
        ) : null}
      </div>
    </form>
  );
}

/** Imagem da capa do fichário: escolher/trocar e remover. */
export function IdentityCoverImage({
  collectionId,
  userId,
  hasLogo,
  onBusyChange,
}: {
  collectionId: string;
  userId: string;
  hasLogo: boolean;
  onBusyChange: (busy: boolean) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const titleId = useId();
  const { state, upload, clear } = useCoverLogo(collectionId, userId);
  const busy = state.status === "busy";

  useEffect(() => {
    onBusyChange(busy);
  }, [busy, onBusyChange]);

  return (
    <div className={styles.identityField} role="group" aria-labelledby={titleId}>
      <span id={titleId} className="text-sm font-medium leading-none">
        Imagem da capa
      </span>
      <p className={styles.identityHint}>
        {hasLogo ? "A capa mostra a sua imagem." : "Sem imagem: a capa mostra o nome da coleção."} PNG, JPEG ou WEBP, até 1 MB.
      </p>
      <div className={styles.identityImageActions}>
        <Button type="button" variant="outline" className="min-h-11 gap-1.5" onClick={() => inputRef.current?.click()} disabled={busy}>
          {busy ? (
            <Loader2 className="h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden="true" />
          ) : (
            <ImagePlus className="h-4 w-4" aria-hidden="true" />
          )}
          {busy ? state.label : hasLogo ? "Trocar imagem" : "Escolher imagem"}
        </Button>
        {hasLogo && !busy ? (
          <Button type="button" variant="outline" className="min-h-11 gap-1.5" onClick={() => void clear()}>
            <Trash2 className="h-4 w-4" aria-hidden="true" />
            Remover
          </Button>
        ) : null}
      </div>
      <input
        ref={inputRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        className="sr-only"
        tabIndex={-1}
        aria-hidden="true"
        onChange={(event) => {
          const file = event.target.files?.[0];
          event.target.value = "";
          if (file) void upload(file);
        }}
      />
      <div aria-live="polite">
        {state.status === "done" ? <InlineFeedback tone="success">{state.message}</InlineFeedback> : null}
        {state.status === "error" ? <InlineFeedback tone="error">{state.message}</InlineFeedback> : null}
      </div>
    </div>
  );
}
