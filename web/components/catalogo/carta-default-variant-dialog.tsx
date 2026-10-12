"use client";

import { AlertTriangle, Star } from "lucide-react";
import { useEffect, useId, useState } from "react";
import { setCardVariantDefault } from "@/app/catalogo/cartas/actions";
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
import { buildVariantSummaryModel, VARIANT_LABEL_SEPARATOR, type VariantSummaryLine } from "@/lib/catalogo/carta-variant-summary";
import type { CartaCompletaRow } from "@/lib/catalogo/queries";
import { cn } from "@/lib/utils";

/**
 * P1 — Gestão administrativa da variante padrão (2026-10-11, Query 2264).
 *
 * Escolha manual e explícita: lista as variações da carta com o rótulo
 * completo dos três eixos (mesmo modelo do indicador da galeria,
 * `buildVariantSummaryModel`) e grava só quando o admin confirma. Nada é
 * pré-escolhido para cartas sem padrão (empates da regra automática): o
 * botão fica desabilitado até haver uma escolha diferente da atual.
 *
 * O padrão atual é identificado por texto + ícone ("Padrão" com estrela),
 * nunca só por cor. Grupo de rádio nativo: setas movem a seleção, Tab sai do
 * grupo, Esc fecha (bloqueado enquanto salva).
 */
export function CartaDefaultVariantDialog({
  open,
  carta,
  onSaved,
  onCancel,
}: {
  open: boolean;
  carta: CartaCompletaRow | null;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        size="lg"
        className="flex max-h-[min(640px,calc(100dvh-2rem))] w-[calc(100vw-1.5rem)] flex-col sm:w-full"
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Variante padrão</DialogTitle>
          <DialogDescription>
            {carta ? `${carta.name} · Nº ${carta.collectorNumber}. ` : ""}
            É a variação usada para representar a carta quando nenhuma outra é indicada. Importações futuras não
            alteram esta escolha.
          </DialogDescription>
        </DialogHeader>

        {open && carta && (
          <DefaultVariantForm
            key={carta.id}
            carta={carta}
            onSaved={onSaved}
            onCancel={onCancel}
            onPendingChange={setPending}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function DefaultVariantForm({
  carta,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  carta: CartaCompletaRow;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const model = buildVariantSummaryModel(carta.variantView, carta.name);
  const currentId = model.kind === "LIST" ? (model.defaultLine?.id ?? null) : null;
  const [selectedId, setSelectedId] = useState<string | null>(currentId);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const groupName = useId();

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  if (model.kind !== "LIST") {
    return (
      <>
        <DialogBody>
          <InlineFeedback tone="warning">
            {model.kind === "HIDDEN"
              ? "Esta carta não tem variações cadastradas."
              : "Os detalhes das variações desta carta estão indisponíveis; não é possível escolher o padrão agora."}
          </InlineFeedback>
        </DialogBody>
        <DialogFooter>
          <Button type="button" variant="outline" size="sm" onClick={onCancel}>
            Fechar
          </Button>
        </DialogFooter>
      </>
    );
  }

  const selectedLine = model.lines.find((line) => line.id === selectedId) ?? null;
  const canSave = selectedLine !== null && selectedLine.id !== currentId && !pending;

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!canSave || !selectedLine) return;
    setPending(true);
    setError(null);
    const result = await setCardVariantDefault(selectedLine.id);
    setPending(false);
    if (result.error) {
      setError(result.error);
      return;
    }
    onSaved(
      result.changed === false
        ? `${selectedLine.label} já era a variante padrão de ${carta.name}.`
        : `Variante padrão de ${carta.name}: ${selectedLine.label}.`,
      carta.id,
    );
  }

  return (
    <form onSubmit={handleSubmit} className="flex min-h-0 flex-1 flex-col">
      <DialogBody className="min-h-0 flex-1 space-y-3 overflow-y-auto">
        {currentId === null && (
          <InlineFeedback tone="warning">Esta carta ainda não tem variante padrão. Escolha uma abaixo.</InlineFeedback>
        )}

        <fieldset disabled={pending} className="space-y-1.5">
          <legend className="sr-only">Variações de {carta.name}</legend>
          {model.lines.map((line) => (
            <VariantOption
              key={line.id}
              line={line}
              name={groupName}
              checked={selectedId === line.id}
              onSelect={() => setSelectedId(line.id)}
            />
          ))}
        </fieldset>

        {error && (
          <div role="alert">
            <InlineFeedback tone="error">{error}</InlineFeedback>
          </div>
        )}
      </DialogBody>

      <DialogFooter className="flex-col-reverse gap-2 sm:flex-row">
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={!canSave} aria-busy={pending || undefined}>
          {pending ? "Salvando…" : "Definir como padrão"}
        </Button>
      </DialogFooter>
    </form>
  );
}

function VariantOption({
  line,
  name,
  checked,
  onSelect,
}: {
  line: VariantSummaryLine;
  name: string;
  checked: boolean;
  onSelect: () => void;
}) {
  return (
    <label
      className={cn(
        "flex min-h-11 cursor-pointer items-center gap-3 rounded-md border border-border px-3 py-2 transition-colors hover:bg-surface-muted",
        "has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-ring",
        checked && "border-primary/40 bg-primary/5 hover:bg-primary/5",
      )}
    >
      <input
        type="radio"
        name={name}
        value={line.id}
        checked={checked}
        onChange={onSelect}
        className="h-4 w-4 shrink-0 accent-primary focus-visible:outline-none"
        aria-describedby={line.isDefault ? `${line.id}-current` : undefined}
      />
      <span className="min-w-0 flex-1 text-sm leading-snug text-foreground">
        {line.parts.map((part, index) => (
          <span key={part.axis} className={cn(part.emphasis === "qualifier" && "text-muted-foreground")}>
            {index > 0 ? VARIANT_LABEL_SEPARATOR : null}
            {part.text}
          </span>
        ))}
        {line.repeatedLabel ? (
          <span className="ml-1.5 inline-flex items-center gap-1 text-xs text-muted-foreground">
            <AlertTriangle className="h-3 w-3 text-warning" aria-hidden="true" />
            rótulo repetido
          </span>
        ) : null}
      </span>
      {line.isDefault ? (
        <span
          id={`${line.id}-current`}
          className="inline-flex shrink-0 items-center gap-1 rounded-full border border-primary/40 bg-primary/5 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide text-primary-ink"
        >
          <Star className="h-3 w-3 fill-current" aria-hidden="true" />
          Padrão atual
        </span>
      ) : null}
    </label>
  );
}
