"use client";

import { AlertTriangle, Pencil, Plus, RefreshCw, Tag } from "lucide-react";
import { useActionState, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  createRarityMapping,
  createRarityWithMapping,
  revalidarTudo,
  updateRarity,
  type RarityActionState,
  type RevalidarTudoState,
} from "@/app/catalogo/raridades/actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  DataTable,
  DataTableCell,
  DataTableHead,
  DataTableHeadCell,
  DataTableHeadRow,
  DataTableRow,
} from "@/components/ui/data-table";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { InlineFeedback } from "@/components/ui/feedback";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import { formatarData } from "@/lib/format-date";
import { RaritySymbol } from "@/components/catalogo/rarity-symbol";
import type { RaridadeRow, RevalidacaoPendenteResumo } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

/** Mesmas chaves de `SYMBOL_MAP` em `rarity-symbol.tsx` — mantidas em sincronia manualmente (nenhum dos dois lados é gerado a partir do outro). */
const SYMBOL_OPTIONS = [
  { value: "BLACK_CIRCLE", label: "Círculo preto" },
  { value: "BLACK_DIAMOND", label: "Losango preto" },
  { value: "BLACK_STAR", label: "Estrela preta" },
  { value: "BLACK_DOUBLE_STAR", label: "2 estrelas pretas" },
  { value: "SILVER_DOUBLE_STAR", label: "2 estrelas prateadas" },
  { value: "MEGA_ATTACK", label: "Raio (Mega Ataque)" },
  { value: "GOLD_STAR", label: "Estrela dourada" },
  { value: "GOLD_DOUBLE_STAR", label: "2 estrelas douradas" },
  { value: "GOLD_TRIPLE_STAR", label: "3 estrelas douradas" },
  { value: "GOLD_DIAMOND", label: "Losango dourado" },
  { value: "ACE_SPEC", label: "Estrela rosa (ACE SPEC)" },
  { value: "GOLD_SPARKLE", label: "Estrela borda dourada" },
  { value: "GOLD_DOUBLE_SPARKLE", label: "2 estrelas borda dourada" },
  { value: "BLACK_WHITE_STAR", label: "Estrela cheia + vazia" },
  { value: "WHITE_STAR", label: "Estrela branca" },
] as const;

const selectClassName = "h-9 w-full rounded-md border border-border bg-background px-3 text-sm";

const initialEntityState: RarityActionState = { error: null };
const initialRevalidarState: RevalidarTudoState = { error: null };

/**
 * Tela /catalogo/raridades (task #336, ciclo de cadastro self-service de
 * Raridade — ver `docs/log.md` 2026-08-06/07). Duas metades:
 *
 * 1. Cadastro das raridades canônicas — mesmo padrão de `JogosTable`
 *    (Dialog de criação/edição, `useAdminListState`).
 * 2. Pendências de revalidação — valores externos de raridade ainda sem
 *    mapeamento (`getRevalidacaoPendenteResumo`), cada um com um botão
 *    "Resolver" que abre o mesmo Dialog de cadastro já com o valor externo
 *    preenchido, e um botão único "Revalidar tudo" (decisão de Fabrício,
 *    2026-08-07: revalida todos os jobs elegíveis numa chamada só, nunca
 *    job por job) que dispara `revalidate-catalog-import-rows` sem
 *    `job_ids`.
 */
export function RaridadesTable({
  raridades,
  pendente,
}: {
  raridades: RaridadeRow[];
  pendente: RevalidacaoPendenteResumo;
}) {
  const router = useRouter();
  const state = useAdminListState();
  const [resolveDialogValue, setResolveDialogValue] = useState<string | null>(null);

  const editingRaridade = raridades.find((r) => r.id === state.editingId) ?? null;
  const nextDisplayOrder = raridades.reduce((max, r) => Math.max(max, r.displayOrder), 0) + 1;

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    setResolveDialogValue(null);
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <div className="flex items-center gap-2">
            <Tag className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
            <PageTitle>Raridades</PageTitle>
          </div>
          <PageDescription>
            Raridades canônicas do catálogo e seus mapeamentos por fonte externa (TCGdex).
          </PageDescription>
        </PageHeading>
      </PageHeader>

      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      <PendenciasRevalidacao pendente={pendente} onResolver={(rawValue) => setResolveDialogValue(rawValue)} />

      <div className="space-y-2">
        <div className="flex justify-end">
          <Button type="button" size="sm" onClick={() => setResolveDialogValue("")}>
            <Plus className="h-3.5 w-3.5" />
            Nova Raridade
          </Button>
        </div>

        <Card density="compact" className="overflow-hidden">
          <CardContent density="compact" className="px-0 pb-0">
            {raridades.length === 0 ? (
              <EmptyState
                title="Nenhuma raridade cadastrada ainda"
                description='Use o botão "Nova Raridade" para começar.'
              />
            ) : (
              <DataTable>
                <DataTableHead>
                  <DataTableHeadRow className="bg-surface-muted">
                    <DataTableHeadCell align="center" className="pl-4">
                      Símbolo
                    </DataTableHeadCell>
                    <DataTableHeadCell align="center">Nome</DataTableHeadCell>
                    <DataTableHeadCell align="center">Código</DataTableHeadCell>
                    <DataTableHeadCell align="center">Mapeamentos externos</DataTableHeadCell>
                    <DataTableHeadCell align="center">Atualizado em</DataTableHeadCell>
                    <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                      Ações
                    </DataTableHeadCell>
                  </DataTableHeadRow>
                </DataTableHead>
                <tbody>
                  {raridades.map((raridade) => (
                    <DataTableRow key={raridade.id} highlighted={state.highlightId === raridade.id}>
                      <DataTableCell align="center" className="pl-4">
                        <RaritySymbol symbolCode={raridade.symbolCode} className="h-3 w-3" />
                      </DataTableCell>
                      <DataTableCell align="center" className="text-foreground">
                        {raridade.name}
                      </DataTableCell>
                      <DataTableCell align="center">
                        <code className="text-xs text-muted-foreground">{raridade.code}</code>
                      </DataTableCell>
                      <DataTableCell align="center">
                        {raridade.mapeamentos.length === 0 ? (
                          <span className="text-xs text-muted-foreground">Nenhum</span>
                        ) : (
                          <div className="flex flex-wrap justify-center gap-1">
                            {raridade.mapeamentos.map((mapeamento) => (
                              <span
                                key={mapeamento.id}
                                className="rounded-full border border-border bg-surface-muted px-2 py-0.5 text-xs text-muted-foreground"
                                title={`Fonte: ${mapeamento.assetSourceCode}`}
                              >
                                {mapeamento.externalValue}
                              </span>
                            ))}
                          </div>
                        )}
                      </DataTableCell>
                      <DataTableCell align="center">{formatarData(raridade.updatedAt)}</DataTableCell>
                      <DataTableCell align="center" className="pr-4 last:pr-4">
                        <div className="flex justify-center">
                          <Button
                            type="button"
                            variant="outline"
                            size="icon-sm"
                            aria-label={`Editar ${raridade.name}`}
                            onClick={() => state.startEdit(raridade.id)}
                          >
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                        </div>
                      </DataTableCell>
                    </DataTableRow>
                  ))}
                </tbody>
              </DataTable>
            )}
          </CardContent>
        </Card>
      </div>

      <ResolverRaridadeDialog
        open={resolveDialogValue !== null}
        externalValue={resolveDialogValue ?? ""}
        raridades={raridades}
        nextDisplayOrder={nextDisplayOrder}
        onSaved={handleSaved}
        onCancel={() => setResolveDialogValue(null)}
      />

      <EditRaridadeDialog
        open={editingRaridade !== null}
        raridade={editingRaridade}
        onSaved={handleSaved}
        onCancel={state.cancelEdit}
      />
    </div>
  );
}

function PendenciasRevalidacao({
  pendente,
  onResolver,
}: {
  pendente: RevalidacaoPendenteResumo;
  onResolver: (rawValue: string) => void;
}) {
  const router = useRouter();
  const [revalidarState, revalidarAction, revalidarPending] = useActionState(revalidarTudo, initialRevalidarState);

  // Bug real reportado por Fabrício (2026-08-07): sem isto, a lista de
  // pendências ficava presa no estado de ANTES da revalidação — a Server
  // Action já resolve tudo certinho no banco (confirmado via SQL), mas o
  // Server Component pai (`page.tsx`) só é buscado de novo com um refresh
  // explícito do router. `revalidatePath` dentro da action invalida o
  // cache do Next, mas não força sozinho o re-render de uma página já
  // montada — mesmo raciocínio de `handleSaved` nos Dialogs de
  // criar/editar, replicado aqui.
  useEffect(() => {
    if (revalidarState.success) {
      router.refresh();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [revalidarState.success]);

  const semPendencia = pendente.totalLinhasPendentes === 0;

  return (
    <div className="space-y-2">
      {/* Botão fora do card, imediatamente acima dele (2026-08-07, ajuste
          de Fabrício: "ficou muito discreto... use o mesmo padrão de todo
          sistema") — mesma posição/hierarquia de "Nova Raridade"/"Novo
          Jogo" logo abaixo, não mais dentro do card junto do aviso. */}
      <div className="flex justify-end">
        <form action={revalidarAction}>
          <Button type="submit" size="sm" disabled={revalidarPending || semPendencia}>
            <RefreshCw className={revalidarPending ? "h-3.5 w-3.5 animate-spin" : "h-3.5 w-3.5"} />
            {revalidarPending ? "Revalidando…" : "Revalidar tudo"}
          </Button>
        </form>
      </div>

      <Card density="compact">
        <CardContent density="compact" className="space-y-3">
          <div className="flex items-center gap-2">
            <AlertTriangle
              className={semPendencia ? "h-4 w-4 text-muted-foreground" : "h-4 w-4 text-warning-foreground"}
              aria-hidden="true"
            />
            <span className="text-sm font-medium text-foreground">
              {semPendencia
                ? "Nada pendente de revalidação"
                : `${formatNumber(pendente.totalLinhasPendentes)} linha(s) sem raridade mapeada, em ${formatNumber(pendente.totalJobsRevalidaveis)} job(s)`}
            </span>
          </div>

          {revalidarState.error && <InlineFeedback tone="error">{revalidarState.error}</InlineFeedback>}

          {revalidarState.success && (
            <InlineFeedback tone="success">
              {formatNumber(revalidarState.jobsProcessados ?? 0)} job(s) processado(s),{" "}
              {formatNumber(revalidarState.linhasAtualizadas ?? 0)} linha(s) atualizada(s)
              {revalidarState.linhasDestravadas
                ? `, ${formatNumber(revalidarState.linhasDestravadas)} destravada(s)`
                : ""}
              .
              {revalidarState.falhas && revalidarState.falhas.length > 0 && (
                <> {formatNumber(revalidarState.falhas.length)} job(s) falharam — ver logs.</>
              )}
            </InlineFeedback>
          )}

          {!semPendencia && (
            <div className="divide-y divide-border rounded-md border border-border">
              {pendente.valoresNaoMapeados.map((valor) => (
                <div key={valor.rawValue} className="flex items-center justify-between gap-3 px-3 py-2">
                  <div className="min-w-0">
                    <div className="truncate text-sm text-foreground">
                      "{valor.rawValue}" <span className="text-muted-foreground">— {valor.totalLinhas} linha(s)</span>
                    </div>
                    <div className="truncate text-xs text-muted-foreground">{valor.cardSets.join(", ")}</div>
                  </div>
                  <Button type="button" size="sm" variant="outline" onClick={() => onResolver(valor.rawValue)}>
                    Resolver
                  </Button>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function ResolverRaridadeDialog({
  open,
  externalValue,
  raridades,
  nextDisplayOrder,
  onSaved,
  onCancel,
}: {
  open: boolean;
  externalValue: string;
  raridades: RaridadeRow[];
  nextDisplayOrder: number;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);
  const [mode, setMode] = useState<"nova" | "existente">(raridades.length > 0 ? "existente" : "nova");

  // Reseta o modo a cada abertura (2026-08-07, bug real reportado por
  // Fabrício): sem isto, `mode` persiste da última interação — se o
  // administrador trocasse para "Nova raridade" numa resolução e depois
  // abrisse o Dialog de novo para OUTRO valor pendente, ele continuava em
  // "Nova raridade" mesmo quando a raridade já existe (caso mais comum:
  // valor externo com grafia diferente de uma raridade já cadastrada).
  useEffect(() => {
    if (open) {
      setMode(raridades.length > 0 ? "existente" : "nova");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, externalValue]);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        className="max-w-lg"
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Resolver raridade</DialogTitle>
          <DialogDescription>
            Vincule o valor externo a uma raridade já cadastrada, ou crie uma raridade nova.
          </DialogDescription>
        </DialogHeader>

        {open && (
          <>
            {raridades.length > 0 && (
              <div className="flex gap-2 px-6">
                <Button
                  type="button"
                  size="sm"
                  variant={mode === "existente" ? "default" : "outline"}
                  onClick={() => setMode("existente")}
                  disabled={pending}
                >
                  Raridade existente
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant={mode === "nova" ? "default" : "outline"}
                  onClick={() => setMode("nova")}
                  disabled={pending}
                >
                  Nova raridade
                </Button>
              </div>
            )}

            {mode === "existente" && raridades.length > 0 ? (
              <VincularRaridadeForm
                externalValue={externalValue}
                raridades={raridades}
                onSaved={onSaved}
                onCancel={onCancel}
                onPendingChange={setPending}
              />
            ) : (
              <NovaRaridadeForm
                externalValue={externalValue}
                nextDisplayOrder={nextDisplayOrder}
                onSaved={onSaved}
                onCancel={onCancel}
                onPendingChange={setPending}
              />
            )}
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

function NovaRaridadeForm({
  externalValue,
  nextDisplayOrder,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  externalValue: string;
  nextDisplayOrder: number;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(createRarityWithMapping, initialEntityState);
  const [symbolCode, setSymbolCode] = useState<string>(SYMBOL_OPTIONS[0].value);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Raridade cadastrada com sucesso.", state.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <DialogBody className="space-y-3">
        <div className="grid grid-cols-[minmax(7rem,1fr)_2fr] gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-rarity-code">Código</Label>
            <Input id="new-rarity-code" name="code" placeholder="Ex.: RARE_HOLO" required maxLength={50} />
          </div>
          <div className="space-y-1">
            <Label htmlFor="new-rarity-name">Nome</Label>
            <Input id="new-rarity-name" name="name" placeholder="Ex.: Rara Holo" required maxLength={150} />
          </div>
        </div>

        <div className="grid grid-cols-[2fr_minmax(6rem,1fr)] gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-rarity-symbol">Símbolo</Label>
            <div className="flex items-center gap-2">
              <select
                id="new-rarity-symbol"
                name="symbolCode"
                required
                value={symbolCode}
                onChange={(event) => setSymbolCode(event.target.value)}
                className={selectClassName}
              >
                {SYMBOL_OPTIONS.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
              <RaritySymbol symbolCode={symbolCode} className="h-3 w-3 shrink-0" />
            </div>
          </div>
          <div className="space-y-1">
            <Label htmlFor="new-rarity-order">Ordem</Label>
            <Input
              id="new-rarity-order"
              name="displayOrder"
              type="number"
              min={1}
              defaultValue={nextDisplayOrder}
              required
            />
          </div>
        </div>

        <div className="space-y-1">
          <Label htmlFor="new-rarity-external-value">Valor na fonte externa (TCGdex)</Label>
          <Input
            id="new-rarity-external-value"
            name="externalValue"
            placeholder='Ex.: "Rare Holo" (exatamente como aparece na fonte)'
            defaultValue={externalValue}
            required
            maxLength={150}
          />
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Cadastrar Raridade"}
        </Button>
      </DialogFooter>
    </form>
  );
}

function VincularRaridadeForm({
  externalValue,
  raridades,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  externalValue: string;
  raridades: RaridadeRow[];
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(createRarityMapping, initialEntityState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Mapeamento cadastrado com sucesso.", state.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <DialogBody className="space-y-3">
        <div className="space-y-1">
          <Label htmlFor="link-rarity-id">Raridade</Label>
          <select id="link-rarity-id" name="rarityId" required defaultValue="" className={selectClassName}>
            <option value="" disabled>
              Selecione…
            </option>
            {raridades.map((raridade) => (
              <option key={raridade.id} value={raridade.id}>
                {raridade.name} ({raridade.code})
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1">
          <Label htmlFor="link-external-value">Valor na fonte externa (TCGdex)</Label>
          <Input
            id="link-external-value"
            name="externalValue"
            placeholder='Ex.: "Rara Holo" (exatamente como aparece na fonte)'
            defaultValue={externalValue}
            required
            maxLength={150}
          />
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Vincular"}
        </Button>
      </DialogFooter>
    </form>
  );
}

function EditRaridadeDialog({
  open,
  raridade,
  onSaved,
  onCancel,
}: {
  open: boolean;
  raridade: RaridadeRow | null;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        className="max-w-lg"
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Editar Raridade</DialogTitle>
          <DialogDescription>Código é imutável após o cadastro.</DialogDescription>
        </DialogHeader>

        {open && raridade && (
          <EditRaridadeForm
            key={raridade.id}
            raridade={raridade}
            onSaved={onSaved}
            onCancel={onCancel}
            onPendingChange={setPending}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function EditRaridadeForm({
  raridade,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  raridade: RaridadeRow;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(updateRarity, initialEntityState);
  const [symbolCode, setSymbolCode] = useState(raridade.symbolCode);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Raridade atualizada com sucesso.", raridade.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={raridade.id} />
      <DialogBody className="space-y-3">
        <div className="grid grid-cols-[minmax(7rem,1fr)_2fr] gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-rarity-code-${raridade.id}`} className="text-muted-foreground">
              Código (imutável)
            </Label>
            <Input id={`edit-rarity-code-${raridade.id}`} value={raridade.code} disabled />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-rarity-name-${raridade.id}`}>Nome</Label>
            <Input
              id={`edit-rarity-name-${raridade.id}`}
              name="name"
              defaultValue={raridade.name}
              required
              maxLength={150}
            />
          </div>
        </div>

        <div className="grid grid-cols-[2fr_minmax(6rem,1fr)] gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-rarity-symbol-${raridade.id}`}>Símbolo</Label>
            <div className="flex items-center gap-2">
              <select
                id={`edit-rarity-symbol-${raridade.id}`}
                name="symbolCode"
                required
                value={symbolCode}
                onChange={(event) => setSymbolCode(event.target.value)}
                className={selectClassName}
              >
                {SYMBOL_OPTIONS.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </select>
              <RaritySymbol symbolCode={symbolCode} className="h-3 w-3 shrink-0" />
            </div>
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-rarity-order-${raridade.id}`}>Ordem</Label>
            <Input
              id={`edit-rarity-order-${raridade.id}`}
              name="displayOrder"
              type="number"
              min={1}
              defaultValue={raridade.displayOrder}
              required
            />
          </div>
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Salvar"}
        </Button>
      </DialogFooter>
    </form>
  );
}
