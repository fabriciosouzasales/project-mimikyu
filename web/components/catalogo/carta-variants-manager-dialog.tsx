"use client";

import { AlertTriangle, Loader2, Star } from "lucide-react";
import { useCallback, useEffect, useId, useMemo, useState } from "react";
import {
  createCardVariant,
  getVariantAxisOptions,
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
import { buildVariantSummaryModel, VARIANT_LABEL_SEPARATOR } from "@/lib/catalogo/carta-variant-summary";
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

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onClose()}>
      <DialogContent
        size="lg"
        className="flex max-h-[min(720px,calc(100dvh-2rem))] w-[calc(100vw-1.5rem)] flex-col sm:w-full"
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Variações</DialogTitle>
          <DialogDescription>{carta ? `${carta.name} · Nº ${carta.collectorNumber}` : "Carta"}</DialogDescription>
        </DialogHeader>
        {open && carta && (
          <ManagerBody key={carta.id} carta={carta} onSaved={onSaved} onClose={onClose} onPendingChange={setPending} />
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
}: {
  carta: CartaCompletaRow;
  onSaved: () => void;
  onClose: () => void;
  onPendingChange: (pending: boolean) => void;
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
  const fieldId = useId();

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

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

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

  const existingLabels = model.kind === "LIST" ? new Set(model.lines.map((line) => line.label)) : new Set<string>();
  const looksDuplicate = preview !== null && existingLabels.has(preview.label);

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
                <li
                  key={line.id}
                  aria-label={line.isDefault ? `${line.label}, variante padrão` : line.label}
                  className="flex min-h-10 items-center gap-3 px-3 py-2 text-sm"
                >
                  <span aria-hidden="true" className="min-w-0 flex-1 leading-snug text-foreground">
                    {line.parts.map((part, index) => (
                      <span key={part.axis} className={cn(part.emphasis === "qualifier" && "text-muted-foreground")}>
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
                </li>
              ))}
            </ul>
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
            <fieldset disabled={pending || !carta.isActive} className="space-y-3">
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
                    Já existe uma variação com este rótulo nesta carta.
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
        <Button type="button" variant="outline" size="sm" onClick={onClose} disabled={pending}>
          Fechar
        </Button>
        <Button type="submit" size="sm" disabled={!finishId || pending || !options || !carta.isActive} aria-busy={pending || undefined}>
          {pending ? "Cadastrando…" : "Adicionar variação"}
        </Button>
      </DialogFooter>
    </form>
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
