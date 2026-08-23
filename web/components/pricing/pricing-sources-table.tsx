"use client";

import { Pencil } from "lucide-react";
import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { atualizarFontePreco, type AtualizarFontePrecoState } from "@/app/pricing/fontes/actions";
import { Badge } from "@/components/ui/badge";
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
import { Select } from "@/components/ui/select";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import type { PricingSource } from "@/lib/pricing/queries";

const initialState: AtualizarFontePrecoState = { error: null };

/**
 * Cadastro de Fontes de Preço (Bloco 4 do Pricing Admin, migration 3942) —
 * sem criação/exclusão nesta V1 (hoje só JUSTTCG, cadastrada via migration
 * 3910; novas fontes continuam sendo um evento raro de migration, não um
 * fluxo de UI): só edição de metadados via Dialog, mesmo esqueleto de
 * `PoliticaSincronizacaoPanel`. `code`/`source_type`/`default_market_scope`/
 * `base_currency` ficam de fora do formulário — identidade estrutural da
 * fonte, imutável por este caminho (mesma disciplina de `card_set.code`
 * antes de ganhar Cards).
 */
export function PricingSourcesTable({ sources }: { sources: PricingSource[] }) {
  const router = useRouter();
  const state = useAdminListState();
  const editingSource = sources.find((s) => s.id === state.editingId) ?? null;

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  return (
    <div className="space-y-3">
      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      <Card>
        <CardContent className="p-0">
          {sources.length === 0 ? (
            <EmptyState
              title="Nenhuma fonte de preço cadastrada"
              description="Fontes novas são cadastradas via migration — não existe criação por aqui nesta versão."
              className="py-10"
            />
          ) : (
            <DataTable>
              <DataTableHead>
                <DataTableHeadRow className="bg-surface-muted">
                  <DataTableHeadCell className="pl-4">Fonte</DataTableHeadCell>
                  <DataTableHeadCell>Tipo</DataTableHeadCell>
                  <DataTableHeadCell>Escopo de mercado</DataTableHeadCell>
                  <DataTableHeadCell>Moeda</DataTableHeadCell>
                  <DataTableHeadCell align="center">API</DataTableHeadCell>
                  <DataTableHeadCell align="center">Status</DataTableHeadCell>
                  <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                    Ações
                  </DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {sources.map((source) => (
                  <DataTableRow key={source.id} highlighted={state.highlightId === source.id}>
                    <DataTableCell className="pl-4">
                      <p className="text-sm font-medium text-foreground">{source.name}</p>
                      <p className="text-xs uppercase text-muted-foreground">{source.code}</p>
                    </DataTableCell>
                    <DataTableCell>
                      <span className="text-xs text-muted-foreground">{source.sourceType}</span>
                    </DataTableCell>
                    <DataTableCell>
                      <span className="text-xs text-muted-foreground">{source.defaultMarketScope}</span>
                    </DataTableCell>
                    <DataTableCell>
                      <span className="text-xs uppercase text-muted-foreground">{source.baseCurrency}</span>
                    </DataTableCell>
                    <DataTableCell align="center">
                      {source.supportsApi ? <Badge variant="outline">Sim</Badge> : <Badge variant="warning">Não</Badge>}
                    </DataTableCell>
                    <DataTableCell align="center">
                      {source.isActive ? <Badge variant="outline">Ativa</Badge> : <Badge variant="warning">Inativa</Badge>}
                    </DataTableCell>
                    <DataTableCell align="center" className="pr-4 last:pr-4">
                      <Button
                        type="button"
                        variant="outline"
                        size="icon-sm"
                        aria-label={`Editar ${source.name}`}
                        onClick={() => state.startEdit(source.id)}
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </Button>
                    </DataTableCell>
                  </DataTableRow>
                ))}
              </tbody>
            </DataTable>
          )}
        </CardContent>
      </Card>

      <EditPricingSourceDialog
        open={editingSource !== null}
        source={editingSource}
        onSaved={handleSaved}
        onCancel={state.cancelEdit}
      />
    </div>
  );
}

function EditPricingSourceDialog({
  open,
  source,
  onSaved,
  onCancel,
}: {
  open: boolean;
  source: PricingSource | null;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        size="lg"
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Editar Fonte de Preço</DialogTitle>
          <DialogDescription>
            {source ? `${source.code} · ${source.sourceType} · ${source.baseCurrency}` : "Identidade estrutural imutável."}
          </DialogDescription>
        </DialogHeader>

        {open && source && (
          <EditPricingSourceForm key={source.id} source={source} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function EditPricingSourceForm({
  source,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  source: PricingSource;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(atualizarFontePreco, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Fonte de preço atualizada com sucesso.", source.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="pricingSourceId" value={source.id} />
      <DialogBody className="space-y-3">
        <div className="space-y-1">
          <Label htmlFor={`edit-source-name-${source.id}`}>Nome</Label>
          <Input id={`edit-source-name-${source.id}`} name="name" defaultValue={source.name} required maxLength={100} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-source-base-url-${source.id}`}>URL do site</Label>
            <Input id={`edit-source-base-url-${source.id}`} name="base_url" type="url" defaultValue={source.baseUrl ?? ""} />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-source-api-url-${source.id}`}>URL da API</Label>
            <Input id={`edit-source-api-url-${source.id}`} name="api_base_url" type="url" defaultValue={source.apiBaseUrl ?? ""} />
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-source-docs-url-${source.id}`}>URL da documentação</Label>
            <Input
              id={`edit-source-docs-url-${source.id}`}
              name="documentation_url"
              type="url"
              defaultValue={source.documentationUrl ?? ""}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-source-terms-url-${source.id}`}>URL dos termos de uso</Label>
            <Input id={`edit-source-terms-url-${source.id}`} name="terms_url" type="url" defaultValue={source.termsUrl ?? ""} />
          </div>
        </div>

        <div className="space-y-1">
          <Label htmlFor={`edit-source-attribution-${source.id}`}>Texto de atribuição</Label>
          <Input
            id={`edit-source-attribution-${source.id}`}
            name="attribution_text"
            defaultValue={source.attributionText ?? ""}
            maxLength={300}
          />
        </div>

        <div className="grid grid-cols-3 gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-source-active-${source.id}`}>Status</Label>
            <Select id={`edit-source-active-${source.id}`} name="is_active" defaultValue={source.isActive ? "on" : ""}>
              <option value="on">Ativa</option>
              <option value="">Inativa</option>
            </Select>
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-source-api-${source.id}`}>Suporta API</Label>
            <Select id={`edit-source-api-${source.id}`} name="supports_api" defaultValue={source.supportsApi ? "on" : ""}>
              <option value="on">Sim</option>
              <option value="">Não</option>
            </Select>
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-source-agreement-${source.id}`}>Exige acordo comercial</Label>
            <Select
              id={`edit-source-agreement-${source.id}`}
              name="requires_commercial_agreement"
              defaultValue={source.requiresCommercialAgreement ? "on" : ""}
            >
              <option value="on">Sim</option>
              <option value="">Não</option>
            </Select>
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
