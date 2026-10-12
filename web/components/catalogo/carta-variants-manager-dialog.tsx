"use client";

import { AlertTriangle, EyeOff, Loader2, Star } from "lucide-react";
import { useCallback, useEffect, useId, useMemo, useRef, useState, type MutableRefObject } from "react";
import {
  createCardVariant,
  getVariantAxisOptions,
  setCardVariantActive,
  type CreateVariantPricing,
  type VariantAxisOptions,
} from "@/app/catalogo/cartas/actions";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { InlineFeedback } from "@/components/ui/feedback";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import {
  buildVariantSummaryModel,
  VARIANT_LABEL_SEPARATOR,
  type VariantSummaryLine,
} from "@/lib/catalogo/carta-variant-summary";
import type { CartaCompletaRow } from "@/lib/catalogo/queries";
import { cn } from "@/lib/utils";

/**
 * P2a (2026-10-11) — "Variações" da carta: lista as cadastradas (rótulo dos
 * três eixos + selo "Padrão" da P1) e permite adicionar uma nova, sem
 * reimportar o Set (RPC `admin_create_card_variant`, Query 2267).
 *
 * - Acabamento obrigatório; Impressão e Contexto de edição opcionais ("Sem …"
 *   = eixo não declarado). As opções vêm sob demanda, já filtradas ao Game da
 *   carta e a itens ativos.
 * - Prévia do rótulo final antes de salvar e aviso quando o mesmo rótulo já
 *   existe; a recusa definitiva de duplicata é do servidor.
 * - O resultado do cadastro e o da ligação de preços aparecem separados: um
 *   problema de Pricing nunca é mostrado como falha do cadastro.
 * - O diálogo fica aberto após salvar (vários cadastros seguidos); a lista se
 *   atualiza pelo `onSaved` (router.refresh no pai).
 *
 * P2b (2026-10-11, Query 2270) — cada linha ganha o estado "Inativa" (texto +
 * ícone, nunca só cor) e a ação Desativar/Reativar. Desativar pede confirmação
 * na própria linha; reativar é direto. Bloqueios conhecidos (variante padrão,
 * única ativa, carta inativa) deixam o botão focável com `aria-disabled` e
 * explicam o motivo ao serem acionados; o servidor valida tudo de novo.
 * Esc fecha primeiro a confirmação aberta, depois o diálogo.
 */
export function CartaVariantsManagerDialog({
  open,
  carta,
  onSaved,
  onClose,
}: {
  open: boolean;
  carta: CartaCompletaRow | null;
  onSaved: () => void;
  onClose: () => void;
}) {
  const [pending, setPending] = useState(false);
  const escapeRef = useRef<(() => boolean) | null>(null);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onClose()}>
      <DialogContent
        size="lg"
        className="flex max-h-[min(720px,calc(100dvh-2rem))] w-[calc(100vw-1.5rem)] flex-col sm:w-full"
        onEscapeKeyDown={(event) => {
          if (pending || escapeRef.current?.()) event.preventDefault();
        }}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Variações</DialogTitle>
          <DialogDescription>{carta ? `${carta.name} · Nº ${carta.collectorNumber}` : "Carta"}</DialogDescription>
        </DialogHeader>
        {open && carta && (
          <ManagerBody
            key={carta.id}
            carta={carta}
            onSaved={onSaved}
            onClose={onClose}
            onPendingChange={setPending}
            escapeRef={escapeRef}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

type Result = { label: string; isDefault: boolean; pricing: CreateVariantPricing };

function ManagerBody({
  carta,
  onSaved,
  onClose,
  onPendingChange,
  escapeRef,
}: {
  carta: CartaCompletaRow;
  onSaved: () => void;
  onClose: () => void;
  onPendingChange: (pending: boolean) => void;
  escapeRef: MutableRefObject<(() => boolean) | null>;
}) {
  const model = buildVariantSummaryModel(carta.variantView, carta.name);
  const [options, setOptions] = useState<VariantAxisOptions | null>(null);
  const [optionsError, setOptionsError] = useState<string | null>(null);
  const [finishId, setFinishId] = useState("");
  const [printingId, setPrintingId] = useState("");
  const [editionId, setEditionId] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<Result | null>(null);
  const [confirmId, setConfirmId] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [rowNote, setRowNote] = useState<{ id: string; text: string } | null>(null);
  const [stateFeedback, setStateFeedback] = useState<{ tone: "success" | "error"; text: string } | null>(null);
  const fieldId = useId();

  useEffect(() => {
    escapeRef.current = () => {
      if (confirmId === null) return false;
      setConfirmId(null);
      return true;
    };
    return () => {
      escapeRef.current = null;
    };
  }, [confirmId, escapeRef]);

  const loadOptions = useCallback(async () => {
    setOptionsError(null);
    const response = await getVariantAxisOptions(carta.id);
    if (response.error || !response.options) {
      setOptionsError(response.error ?? "Não foi possível carregar as opções.");
      return;
    }
    setOptions(response.options);
  }, [carta.id]);

  useEffect(() => {
    void loadOptions();
  }, [loadOptions]);

  const busy = pending || busyId !== null;
  useEffect(() => {
    onPendingChange(busy);
  }, [busy, onPendingChange]);

  const activeCount = model.kind === "LIST" ? model.lines.filter((line) => line.isActive).length : 0;

  function blockedReason(line: VariantSummaryLine): string | null {
    if (line.isActive) {
      if (line.isDefault) return "É a variante padrão. Defina outra variação como padrão antes de desativá-la.";
      if (activeCount <= 1) return "É a única variação ativa. A carta precisa manter ao menos uma.";
      return null;
    }
    if (!carta.isActive) return "Reative a carta antes de reativar esta variação.";
    return null;
  }

  function requestToggle(line: VariantSummaryLine) {
    if (busy) return;
    setStateFeedback(null);
    const reason = blockedReason(line);
    if (reason) {
      setConfirmId(null);
      setRowNote({ id: line.id, text: reason });
      return;
    }
    setRowNote(null);
    if (line.isActive) {
      setConfirmId(line.id);
      return;
    }
    void applyToggle(line, true);
  }

  async function applyToggle(line: VariantSummaryLine, active: boolean) {
    setBusyId(line.id);
    setStateFeedback(null);
    const response = await setCardVariantActive(line.id, active);
    setBusyId(null);
    setConfirmId(null);
    if (response.error) {
      setStateFeedback({ tone: "error", text: response.error });
      return;
    }
    const label = response.label ?? line.label;
    const linked = response.linkedPricingProducts ?? 0;
    setStateFeedback({
      tone: "success",
      text: active
        ? `Variação reativada: ${label}. Ela volta a aceitar novos vínculos.`
        : `Variação desativada: ${label}. Não aparece mais em novas seleções` +
          (linked > 0
            ? `; ${linked} ${linked === 1 ? "produto de preço continua ligado" : "produtos de preço continuam ligados"} a ela como histórico.`
            : "; o histórico foi preservado."),
    });
    if (response.changed) onSaved();
  }

  const preview = useMemo(() => {
    if (!options || !finishId) return null;
    const finish = options.finishes.find((o) => o.id === finishId)?.name;
    if (!finish) return null;
    const qualifiers = [
      options.printings.find((o) => o.id === printingId)?.name,
      options.editionContexts.find((o) => o.id === editionId)?.name,
    ].filter((name): name is string => Boolean(name));
    return { finish, qualifiers, label: [finish, ...qualifiers].join(VARIANT_LABEL_SEPARATOR) };
  }, [options, finishId, printingId, editionId]);

  const sameLabelLine =
    preview !== null && model.kind === "LIST" ? (model.lines.find((line) => line.label === preview.label) ?? null) : null;
  const looksDuplicate = sameLabelLine !== null;

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!finishId || pending) return;
    setPending(true);
    setError(null);
    setResult(null);
    const response = await createCardVariant({
      cardId: carta.id,
      variantTypeId: finishId,
      printingProfileId: printingId || null,
      editionContextProfileId: editionId || null,
    });
    setPending(false);
    if (response.error || !response.pricing) {
      setError(response.error ?? "Não foi possível cadastrar a variação.");
      return;
    }
    setResult({ label: response.label ?? preview?.label ?? "", isDefault: response.isDefault === true, pricing: response.pricing });
    setFinishId("");
    setPrintingId("");
    setEditionId("");
    onSaved();
  }

  return (
    <form onSubmit={handleSubmit} className="flex min-h-0 flex-1 flex-col">
      <DialogBody className="min-h-0 flex-1 space-y-5 overflow-y-auto">
        <section aria-labelledby={`${fieldId}-list`} className="space-y-2">
          <h3 id={`${fieldId}-list`} className="text-xs font-medium text-muted-foreground">
            Cadastradas{model.kind === "LIST" ? ` (${model.count})` : ""}
          </h3>
          {model.kind === "HIDDEN" ? (
            <p className="text-sm text-muted-foreground">Nenhuma variação cadastrada ainda.</p>
          ) : model.kind === "UNAVAILABLE" ? (
            <InlineFeedback tone="warning">Os detalhes das variações desta carta estão indisponíveis.</InlineFeedback>
          ) : (
            <ul className="divide-y divide-border rounded-md border border-border">
              {model.lines.map((line) => (
                <VariantRow
                  key={line.id}
                  line={line}
                  blocked={blockedReason(line) !== null}
                  confirming={confirmId === line.id}
                  busy={busyId === line.id}
                  disabled={busy && busyId !== line.id}
                  note={rowNote?.id === line.id ? rowNote.text : null}
                  onRequest={() => requestToggle(line)}
                  onCancel={() => setConfirmId(null)}
                  onConfirm={() => void applyToggle(line, false)}
                />
              ))}
            </ul>
          )}
          {stateFeedback && (
            <div role={stateFeedback.tone === "error" ? "alert" : "status"}>
              <InlineFeedback tone={stateFeedback.tone}>{stateFeedback.text}</InlineFeedback>
            </div>
          )}
        </section>

        <section aria-labelledby={`${fieldId}-add`} className="space-y-3">
          <h3 id={`${fieldId}-add`} className="text-xs font-medium text-muted-foreground">
            Adicionar variação
          </h3>

          {optionsError ? (
            <div role="alert" className="space-y-2">
              <InlineFeedback tone="error">{optionsError}</InlineFeedback>
              <Button type="button" variant="outline" size="sm" onClick={() => void loadOptions()}>
                Tentar novamente
              </Button>
            </div>
          ) : !options ? (
            <p className="flex items-center gap-2 text-sm text-muted-foreground" role="status">
              <Loader2 className="h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden="true" />
              Carregando opções…
            </p>
          ) : (
            <fieldset disabled={busy || !carta.isActive} className="space-y-3">
              {!carta.isActive && (
                <InlineFeedback tone="warning">Reative a carta para cadastrar variações.</InlineFeedback>
              )}
              <div className="grid gap-3 sm:grid-cols-3">
                <div className="space-y-1">
                  <Label htmlFor={`${fieldId}-finish`}>Acabamento</Label>
                  <Select
                    id={`${fieldId}-finish`}
                    value={finishId}
                    onChange={(event) => setFinishId(event.target.value)}
                    required
                  >
                    <option value="" disabled>
                      Selecione…
                    </option>
                    {options.finishes.map((option) => (
                      <option key={option.id} value={option.id}>
                        {option.name}
                      </option>
                    ))}
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label htmlFor={`${fieldId}-printing`}>Impressão</Label>
                  <Select id={`${fieldId}-printing`} value={printingId} onChange={(event) => setPrintingId(event.target.value)}>
                    <option value="">Sem impressão declarada</option>
                    {options.printings.map((option) => (
                      <option key={option.id} value={option.id}>
                        {option.name}
                      </option>
                    ))}
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label htmlFor={`${fieldId}-edition`}>Contexto de edição</Label>
                  <Select id={`${fieldId}-edition`} value={editionId} onChange={(event) => setEditionId(event.target.value)}>
                    <option value="">Sem contexto de edição</option>
                    {options.editionContexts.map((option) => (
                      <option key={option.id} value={option.id}>
                        {option.name}
                      </option>
                    ))}
                  </Select>
                </div>
              </div>
              <p className="text-xs text-muted-foreground">
                Impressão e contexto de edição são opcionais: deixe &ldquo;Sem…&rdquo; quando a carta não os declara.
              </p>

              <div
                aria-live="polite"
                className={cn(
                  "rounded-md border px-3 py-2 text-sm",
                  looksDuplicate ? "border-warning/40 bg-warning/10" : "border-border bg-surface-muted/50",
                )}
              >
                <span className="text-xs text-muted-foreground">Prévia: </span>
                {preview ? (
                  <span className="text-foreground">
                    {preview.finish}
                    {preview.qualifiers.map((q) => (
                      <span key={q} className="text-muted-foreground">
                        {VARIANT_LABEL_SEPARATOR}
                        {q}
                      </span>
                    ))}
                  </span>
                ) : (
                  <span className="text-muted-foreground">escolha o acabamento</span>
                )}
                {looksDuplicate ? (
                  <span className="mt-1 flex items-center gap-1.5 text-xs text-warning">
                    <AlertTriangle className="h-3.5 w-3.5" aria-hidden="true" />
                    {sameLabelLine && !sameLabelLine.isActive
                      ? "Esta variação já existe e está inativa: reative-a na lista acima."
                      : "Já existe uma variação com este rótulo nesta carta."}
                  </span>
                ) : null}
              </div>
            </fieldset>
          )}

          {error && (
            <div role="alert">
              <InlineFeedback tone="error">{error}</InlineFeedback>
            </div>
          )}
          {result && <ResultFeedback result={result} />}
        </section>
      </DialogBody>

      <DialogFooter className="flex-col-reverse gap-2 sm:flex-row">
        <Button type="button" variant="outline" size="sm" onClick={onClose} disabled={busy}>
          Fechar
        </Button>
        <Button type="submit" size="sm" disabled={!finishId || busy || !options || !carta.isActive} aria-busy={pending || undefined}>
          {pending ? "Cadastrando…" : "Adicionar variação"}
        </Button>
      </DialogFooter>
    </form>
  );
}

/**
 * P2b — uma variação na lista: rótulo dos três eixos, selos (Padrão / Inativa)
 * e a ação Desativar/Reativar com confirmação contextual na própria linha.
 */
function VariantRow({
  line,
  blocked,
  confirming,
  busy,
  disabled,
  note,
  onRequest,
  onCancel,
  onConfirm,
}: {
  line: VariantSummaryLine;
  blocked: boolean;
  confirming: boolean;
  busy: boolean;
  disabled: boolean;
  note: string | null;
  onRequest: () => void;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const rowId = useId();
  const cancelRef = useRef<HTMLButtonElement>(null);
  const actionLabel = line.isActive ? "Desativar" : "Reativar";
  const states = [line.isDefault ? "variante padrão" : null, line.isActive ? null : "inativa"].filter(Boolean);

  useEffect(() => {
    if (confirming) cancelRef.current?.focus();
  }, [confirming]);

  return (
    <li className="px-3 py-2 text-sm" aria-label={[line.label, ...states].join(", ")}>
      <div className="flex min-h-8 flex-wrap items-center gap-x-3 gap-y-1.5">
        <span
          aria-hidden="true"
          className={cn("min-w-0 flex-1 basis-40 leading-snug", line.isActive ? "text-foreground" : "text-muted-foreground")}
        >
          {line.parts.map((part, index) => (
            <span
              key={part.axis}
              className={cn(line.isActive && part.emphasis === "qualifier" && "text-muted-foreground")}
            >
              {index > 0 ? VARIANT_LABEL_SEPARATOR : null}
              {part.text}
            </span>
          ))}
        </span>
        {line.isDefault ? (
          <span
            aria-hidden="true"
            className="inline-flex shrink-0 items-center gap-1 rounded-full border border-primary/40 bg-primary/5 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide text-primary-ink"
          >
            <Star className="h-3 w-3 fill-current" />
            Padrão
          </span>
        ) : null}
        {!line.isActive ? (
          <span
            aria-hidden="true"
            className="inline-flex shrink-0 items-center gap-1 rounded-full border border-border bg-surface-muted px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide text-muted-foreground"
          >
            <EyeOff className="h-3 w-3" />
            Inativa
          </span>
        ) : null}
        {!confirming ? (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={onRequest}
            disabled={disabled || busy}
            aria-disabled={blocked || undefined}
            aria-describedby={note ? `${rowId}-note` : undefined}
            aria-busy={busy || undefined}
            aria-label={`${actionLabel} ${line.label}`}
            className={cn(
              "shrink-0 text-muted-foreground hover:text-foreground",
              blocked && "cursor-not-allowed opacity-60 hover:bg-transparent hover:text-muted-foreground",
            )}
          >
            {busy ? <Loader2 className="h-3.5 w-3.5 animate-spin motion-reduce:animate-none" aria-hidden="true" /> : null}
            {busy ? (line.isActive ? "Desativando…" : "Reativando…") : actionLabel}
          </Button>
        ) : null}
      </div>

      {note ? (
        <p id={`${rowId}-note`} role="status" className="mt-1.5 flex items-start gap-1.5 text-xs text-muted-foreground">
          <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0 text-warning" aria-hidden="true" />
          {note}
        </p>
      ) : null}

      {confirming ? (
        <div
          role="group"
          aria-labelledby={`${rowId}-confirm`}
          className="mt-2 space-y-2 rounded-md border border-border bg-surface-muted/50 p-3"
        >
          <p id={`${rowId}-confirm`} className="text-xs leading-relaxed text-muted-foreground">
            <span className="font-medium text-foreground">Desativar {line.label}?</span> Ela deixa de aparecer em novas
            seleções e não recebe novos vínculos. Preços, inventário e coleções que já a usam continuam preservados, e
            você pode reativá-la depois.
          </p>
          <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <Button ref={cancelRef} type="button" variant="outline" size="sm" onClick={onCancel} disabled={busy}>
              Cancelar
            </Button>
            <Button type="button" variant="outline-primary" size="sm" onClick={onConfirm} disabled={busy} aria-busy={busy || undefined}>
              {busy ? "Desativando…" : "Desativar variação"}
            </Button>
          </div>
        </div>
      ) : null}
    </li>
  );
}

/** Cadastro e Pricing em mensagens separadas: o cadastro já está salvo em qualquer resultado de preço. */
function ResultFeedback({ result }: { result: Result }) {
  const { pricing } = result;
  const others = pricing.linked - pricing.linkedToNew;
  let pricingText: string;
  let pricingWarning = false;
  if (pricing.status === "ERROR") {
    pricingWarning = true;
    pricingText = "A ligação de preços não pôde ser feita agora; a variação continua cadastrada.";
  } else if (pricing.status === "NO_CANDIDATES") {
    pricingText = "Nenhum produto de preço pendente para esta carta.";
  } else if (pricing.linked === 0) {
    pricingText = `${pricing.candidates} ${pricing.candidates === 1 ? "produto pendente" : "produtos pendentes"} nesta carta; nenhum corresponde a esta variação.`;
  } else {
    pricingText =
      `${pricing.linkedToNew} ${pricing.linkedToNew === 1 ? "produto ligado" : "produtos ligados"} a esta variação` +
      (others > 0 ? ` e ${others} a outras variações da carta` : "") +
      ".";
  }

  return (
    <div role="status" className="space-y-2">
      <InlineFeedback tone="success">
        Variação cadastrada: {result.label}.{result.isDefault ? " Ela passou a ser a padrão da carta." : ""}
      </InlineFeedback>
      <p
        className={cn(
          "flex items-start gap-1.5 rounded-md border px-3 py-2 text-xs",
          pricingWarning ? "border-warning/40 bg-warning/10 text-warning" : "border-border text-muted-foreground",
        )}
      >
        {pricingWarning ? <AlertTriangle className="mt-px h-3.5 w-3.5 shrink-0" aria-hidden="true" /> : null}
        <span>
          <span className="font-medium text-foreground">Preços: </span>
          {pricingText}
        </span>
      </p>
    </div>
  );
}
