"use client";

import { ChevronLeft, ChevronRight, Loader2, Pencil, RefreshCw, ShieldCheck, ShieldX } from "lucide-react";
import Link from "next/link";
import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import {
  atualizarDetalhesMapeamentoSet,
  confirmarCorrespondenciaSet,
  preverCorrespondenciaSet,
  reclassificarMapeamentoSet,
  type AtualizarDetalhesMapeamentoSetState,
  type PreverCorrespondenciaSetResult,
  type ReclassificarMapeamentoSetState,
} from "@/app/pricing/mapeamentos-sets/actions";
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
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { MapeamentosSetsFiltros } from "@/components/pricing/mapeamentos-sets-filtros";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import {
  PRICING_SET_MAPPINGS_PAGE_SIZE,
  type PricingSetMappingItem,
  type PricingSource,
} from "@/lib/pricing/queries";
import { formatarData } from "@/lib/format-date";
import { cn, formatNumber } from "@/lib/utils";

const STATUS_LABEL: Record<string, string> = {
  CONFIRMED: "Confirmado",
  PENDING: "Pendente",
  NOT_FOUND: "Não encontrado",
  REJECTED: "Rejeitado",
  // P16.1 (migration 3950) — pseudo-status sintético para Sets elegíveis sem nenhuma linha em
  // pricing_set_mapping ainda; nunca gravado no banco, ver PricingSetMappingStatus em queries.ts.
  UNMAPPED: "Sem mapeamento",
};

const STATUS_TONE: Record<string, StateTone> = {
  CONFIRMED: "success",
  PENDING: "warning",
  NOT_FOUND: "muted",
  REJECTED: "danger",
  UNMAPPED: "muted",
};

/**
 * P16.4.1 (migration 3952) — estado visual da linha combina `matchStatus` (identidade externa
 * confirmada ou não) com `refreshStatus` (estado operacional de sincronização, derivado de
 * `pricing_set_refresh_state`). Os dois são conceitualmente distintos e nunca devem ser
 * confundidos (ver Seção 8 do pedido de Fabrício): um Set pode estar CONFIRMED e ainda assim
 * nunca ter sincronizado (ONBOARDING_PENDING) — a linha reflete isso, o `match_status` físico
 * nunca é alterado por esta função, é só camada de apresentação.
 */
function deriveRowStatus(item: PricingSetMappingItem): { tone: StateTone; label: string } {
  if (item.matchStatus !== "CONFIRMED" || !item.refreshStatus) {
    return { tone: STATUS_TONE[item.matchStatus] ?? "muted", label: STATUS_LABEL[item.matchStatus] ?? item.matchStatus };
  }

  switch (item.refreshStatus) {
    case "ONBOARDING_PENDING":
      return { tone: "warning", label: "Aguardando primeira sincronização" };
    case "PROCESSING":
      return { tone: "warning", label: "Sincronizando" };
    case "PROBLEM":
      return { tone: "danger", label: "Com problema" };
    case "PAUSED":
      return { tone: "muted", label: "Pausado" };
    case "HEALTHY":
    default:
      return { tone: "success", label: "Confirmado" };
  }
}

const textareaClassName =
  "flex min-h-16 w-full rounded-md border border-input bg-surface px-3 py-2 text-sm shadow-subtle transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50";

function formatDate(value: string | null): string {
  if (!value) return "—";
  return formatarData(value);
}

/**
 * Cadastro de Mapeamentos de Sets (Bloco 4 do Pricing Admin, migration
 * 3942) — todos os 4 status (diferente de `/pricing/pendencias`, que trava
 * em PENDING/NOT_FOUND). `external_set_name` sempre editável;
 * `external_set_id` e a reclassificação CONFIRMED→REJECTED ficam
 * bloqueados quando `hasDependency` (ícone de cadeado) — a mesma fonte
 * única de verdade da migration 3942 (`pricing_set_mapping_dependency_exists`),
 * a UI só espelha o que a RPC decide.
 */
export function MapeamentosSetsTable({
  items,
  totalCount,
  page,
  search,
  status,
  pricingSourceId,
  sources,
}: {
  items: PricingSetMappingItem[];
  totalCount: number;
  page: number;
  search: string;
  status: string;
  pricingSourceId: string;
  sources: PricingSource[];
}) {
  const router = useRouter();
  const state = useAdminListState();
  const [reclassifying, setReclassifying] = useState<PricingSetMappingItem | null>(null);
  // P16.3 (Descoberta de Correspondência) — Set UNMAPPED selecionado para a jornada de preview
  // via "Sincronizar". Só controla qual Dialog está aberto; nenhuma escrita acontece aqui.
  const [syncingItem, setSyncingItem] = useState<PricingSetMappingItem | null>(null);
  // P16.1 fix (bug objetivo pós-aplicação, 2026-08-25): `useAdminListState().editingId` começa
  // `null` (nenhuma edição em andamento). Antes do P16.1, `item.id` era sempre um UUID real, então
  // `i.id === state.editingId` nunca colava em `null`. Com a linha UNMAPPED sintética (id NULL),
  // o mesmo `.find()` casava `null === null` na primeira renderização e abria "Editar Mapeamento
  // de Set" sozinho para o primeiro Set sem mapeamento (ex.: SWSH8) — sem nenhum clique do usuário.
  // Guarda explícita: só procura quando há de fato uma edição em andamento.
  const editingItem = state.editingId !== null ? (items.find((i) => i.id === state.editingId) ?? null) : null;
  const totalPages = Math.max(1, Math.ceil(totalCount / PRICING_SET_MAPPINGS_PAGE_SIZE));

  function buildPageHref(targetPage: number): string {
    const params = new URLSearchParams();
    if (search) params.set("q", search);
    if (status) params.set("status", status);
    if (pricingSourceId) params.set("source", pricingSourceId);
    if (targetPage > 0) params.set("page", String(targetPage));
    const qs = params.toString();
    return qs ? `/pricing/mapeamentos-sets?${qs}` : "/pricing/mapeamentos-sets";
  }

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  const hasFilter = Boolean(search || status || pricingSourceId);

  // Fonte só ganha presença visual por linha quando pode variar de fato:
  // há mais de uma fonte cadastrada E a tela não está já filtrada para uma
  // única fonte (nesse caso repetir o código em cada linha é ruído puro —
  // o filtro já deixou o contexto claro). Com 1 fonte só (estado atual,
  // JUSTTCG), nunca aparece. Não é uma regra permanente amarrada a
  // "só existe JUSTTCG hoje": em produto vira `sources.length > 1`
  // automaticamente no dia em que uma segunda fonte for cadastrada.
  const activeSource = sources.find((s) => s.id === pricingSourceId);
  const showSourceInline = sources.length > 1 && !activeSource;

  return (
    <div className="space-y-3">
      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      <Card>
        <div className="border-b border-border px-4 py-3">
          <MapeamentosSetsFiltros initialSearch={search} status={status} pricingSourceId={pricingSourceId} sources={sources} />
        </div>
        <CardContent className="p-0">
          {items.length === 0 ? (
            <EmptyState
              title={hasFilter ? "Nenhum mapeamento para este filtro" : "Nenhum mapeamento de Set cadastrado"}
              description={hasFilter ? "Troque os filtros para ver outros mapeamentos." : undefined}
              className="py-10"
            />
          ) : (
            <DataTable>
              <DataTableHead>
                <DataTableHeadRow className="bg-surface-muted">
                  <DataTableHeadCell className="pl-4">Set local</DataTableHeadCell>
                  <DataTableHeadCell>Mapeamento externo</DataTableHeadCell>
                  <DataTableHeadCell align="center">Status</DataTableHeadCell>
                  <DataTableHeadCell align="center">Última verificação</DataTableHeadCell>
                  <DataTableHeadCell align="center" className="pr-4 last:pr-4">
                    Ações
                  </DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {items.map((item) => {
                  const unmapped = item.matchStatus === "UNMAPPED";
                  return (
                    <DataTableRow key={item.id ?? item.cardSetId} highlighted={state.highlightId === item.id}>
                      <DataTableCell className="pl-4">
                        <div className="flex flex-col">
                          <span className="text-sm font-medium text-foreground">{item.cardSetName}</span>
                          <span className="text-xs text-muted-foreground">{item.cardSetCode}</span>
                        </div>
                      </DataTableCell>
                      <DataTableCell>
                        {unmapped ? (
                          <span className="text-sm italic text-muted-foreground">Sem mapeamento</span>
                        ) : (
                          <div className="flex max-w-[170px] flex-col gap-0.5 sm:max-w-[220px]">
                            <span className="truncate text-sm text-foreground" title={item.externalSetName ?? undefined}>
                              {item.externalSetName ?? "—"}
                            </span>
                            <div className="flex min-w-0 items-center gap-1.5">
                              {showSourceInline && (
                                <span className="shrink-0 text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
                                  {item.pricingSourceCode}
                                </span>
                              )}
                              <code
                                className="truncate text-xs text-muted-foreground"
                                title={item.externalSetId ?? undefined}
                              >
                                {item.externalSetId ?? "—"}
                              </code>
                            </div>
                          </div>
                        )}
                      </DataTableCell>
                      <DataTableCell align="center">
                        {(() => {
                          const rowStatus = deriveRowStatus(item);
                          return <StateBadge tone={rowStatus.tone}>{rowStatus.label}</StateBadge>;
                        })()}
                      </DataTableCell>
                      <DataTableCell align="center">
                        <span className="text-xs text-muted-foreground">{unmapped ? "—" : formatDate(item.lastCheckedAt)}</span>
                      </DataTableCell>
                      <DataTableCell align="center" className="pr-4 last:pr-4">
                        {unmapped ? (
                          // P16.3 (Descoberta de Correspondência) — a linguagem visual do P16.1
                          // (botão sempre desabilitado) foi um placeholder deliberado até a
                          // function de preview existir; ela existe e está deployada, então o
                          // botão abre a jornada DESCOBRIR → CLASSIFICAR → APRESENTAR. Elegibilidade
                          // (Set + fonte ativa) e papel admin já são a própria razão de esta linha
                          // aparecer na tabela (admin_list_pricing_set_mappings, migration 3950,
                          // e o guard de página) — nenhuma condição adicional aqui.
                          <div className="flex justify-center">
                            <Button
                              type="button"
                              variant="outline"
                              size="sm"
                              title="Descobrir correspondência na fonte externa (JustTCG) — não salva nada automaticamente."
                              className="gap-1.5"
                              onClick={() => setSyncingItem(item)}
                            >
                              <RefreshCw className="h-3.5 w-3.5" />
                              Sincronizar
                            </Button>
                          </div>
                        ) : (
                          <div className="flex justify-center gap-2">
                            <Button
                              type="button"
                              variant="outline"
                              size="icon-sm"
                              aria-label={`Editar mapeamento de ${item.cardSetName}`}
                              title="Editar identificador e nome externos"
                              onClick={() => state.startEdit(item.id as string)}
                            >
                              <Pencil className="h-3.5 w-3.5" />
                            </Button>
                            {item.matchStatus === "CONFIRMED" && (
                              <Button
                                type="button"
                                variant="outline"
                                size="icon-sm"
                                aria-label={`Rejeitar mapeamento de ${item.cardSetName}`}
                                disabled={item.hasDependency}
                                title={
                                  item.hasDependency
                                    ? "Protegido: existe mapeamento de carta confirmado ou dado de preço vinculado a este Set."
                                    : "Rejeitar este mapeamento (marca como não correspondente)"
                                }
                                onClick={() => setReclassifying(item)}
                              >
                                <ShieldX className={cn("h-3.5 w-3.5", !item.hasDependency && "text-destructive")} />
                              </Button>
                            )}
                            {item.matchStatus === "REJECTED" && (
                              <Button
                                type="button"
                                variant="outline"
                                size="icon-sm"
                                aria-label={`Confirmar mapeamento de ${item.cardSetName}`}
                                title="Confirmar este mapeamento novamente"
                                onClick={() => setReclassifying(item)}
                              >
                                <ShieldCheck className="h-3.5 w-3.5 text-success" />
                              </Button>
                            )}
                          </div>
                        )}
                      </DataTableCell>
                    </DataTableRow>
                  );
                })}
              </tbody>
            </DataTable>
          )}
        </CardContent>

        {totalCount > 0 && (
          <div className="flex items-center justify-between border-t border-border px-4 py-3">
            <span className="text-sm text-muted-foreground">
              Mostrando <span className="font-medium text-foreground">{page * PRICING_SET_MAPPINGS_PAGE_SIZE + 1}</span>–
              <span className="font-medium text-foreground">
                {Math.min((page + 1) * PRICING_SET_MAPPINGS_PAGE_SIZE, totalCount)}
              </span>{" "}
              de <span className="font-medium text-foreground">{formatNumber(totalCount)}</span>
            </span>
            <div className="flex items-center gap-1.5">
              {page === 0 ? (
                <Button type="button" variant="outline" size="icon-sm" disabled aria-label="Página anterior">
                  <ChevronLeft className="h-3.5 w-3.5" />
                </Button>
              ) : (
                <Button asChild variant="outline" size="icon-sm" aria-label="Página anterior">
                  <Link href={buildPageHref(page - 1)}>
                    <ChevronLeft className="h-3.5 w-3.5" />
                  </Link>
                </Button>
              )}
              <span className="min-w-[2.5rem] text-center text-sm text-muted-foreground">
                {page + 1}/{totalPages}
              </span>
              {page >= totalPages - 1 ? (
                <Button type="button" variant="outline" size="icon-sm" disabled aria-label="Próxima página">
                  <ChevronRight className="h-3.5 w-3.5" />
                </Button>
              ) : (
                <Button asChild variant="outline" size="icon-sm" aria-label="Próxima página">
                  <Link href={buildPageHref(page + 1)}>
                    <ChevronRight className="h-3.5 w-3.5" />
                  </Link>
                </Button>
              )}
            </div>
          </div>
        )}
      </Card>

      <EditSetMappingDialog open={editingItem !== null} item={editingItem} onSaved={handleSaved} onCancel={state.cancelEdit} />

      <ReclassifySetMappingDialog
        open={reclassifying !== null}
        item={reclassifying}
        onSaved={(message, id) => {
          setReclassifying(null);
          handleSaved(message, id);
        }}
        onCancel={() => setReclassifying(null)}
      />

      <SincronizarSetDialog
        open={syncingItem !== null}
        item={syncingItem}
        onClose={() => setSyncingItem(null)}
        onConfirmed={(message) => {
          setSyncingItem(null);
          handleSaved(message);
        }}
      />
    </div>
  );
}

/**
 * P16.3 (Descoberta de Correspondência) + P16.4 (Confirmação do Mapping) — Dialog acionado pelo
 * botão "Sincronizar" de uma linha UNMAPPED. Dispara `preverCorrespondenciaSet` (Edge Function
 * REAL `pricing-set-matching-preview`) assim que abre, mesma disciplina de "carregar só quando
 * aberto" de SyncRunDetailDialog. Quando o resultado é SAFE_CANDIDATE, habilita a ação explícita
 * "Confirmar correspondência" — nunca confirma sozinho ao abrir o Dialog — que chama
 * `confirmarCorrespondenciaSet` (RPC `admin_confirm_pricing_set_mapping`, migration 3951).
 */
function SincronizarSetDialog({
  open,
  item,
  onClose,
  onConfirmed,
}: {
  open: boolean;
  item: PricingSetMappingItem | null;
  onClose: () => void;
  onConfirmed: (message: string) => void;
}) {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<PreverCorrespondenciaSetResult | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [confirmError, setConfirmError] = useState<string | null>(null);

  useEffect(() => {
    if (!open || !item) {
      return;
    }
    let cancelled = false;
    setLoading(true);
    setResult(null);
    setConfirmError(null);
    preverCorrespondenciaSet(item.cardSetId).then((r) => {
      if (!cancelled) {
        setResult(r);
        setLoading(false);
      }
    });
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, item?.cardSetId]);

  function handleOpenChange(next: boolean) {
    if (!next && !confirming) {
      onClose();
      // Estado só é limpo depois que o Dialog já fechou (evita "piscar" o conteúdo anterior
      // durante a animação de saída) — mesmo raciocínio de outros Dialogs sob demanda deste
      // módulo.
      setTimeout(() => {
        setResult(null);
        setLoading(false);
        setConfirmError(null);
      }, 200);
    }
  }

  async function handleConfirm() {
    if (!result || result.state !== "SAFE_CANDIDATE" || !result.local || !result.candidate) {
      return;
    }
    setConfirming(true);
    setConfirmError(null);
    const { local, candidate } = result;
    // Hardening P16.4 (2026-08-26): só `cardSetId` + o candidato que o admin VIU são enviados
    // — a Server Action repete o preview real server-side e usa exclusivamente esse resultado
    // fresco para persistir; `expectedExternalSetId` aqui só detecta "mudou desde que abri o
    // Dialog", nunca é gravado diretamente.
    const { error } = await confirmarCorrespondenciaSet({
      cardSetId: local.cardSetId,
      expectedExternalSetId: candidate.externalSetId,
    });
    setConfirming(false);
    if (error) {
      setConfirmError(error);
      return;
    }
    onConfirmed(`Correspondência confirmada: ${candidate.externalSetName}.`);
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent
        onEscapeKeyDown={(event) => confirming && event.preventDefault()}
        onInteractOutside={(event) => confirming && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Sincronizar Set</DialogTitle>
          <DialogDescription>
            {item ? `${item.cardSetName} (${item.cardSetCode}) · JustTCG` : "Descobrindo correspondência na fonte externa."}
          </DialogDescription>
        </DialogHeader>

        <DialogBody className="space-y-3">
          {loading && (
            <div className="flex items-center justify-center gap-2 py-8 text-sm text-muted-foreground">
              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
              Consultando a JustTCG…
            </div>
          )}

          {!loading && result?.error && <InlineFeedback tone="error">{result.error}</InlineFeedback>}

          {!loading && !result?.error && result?.state === "SET_NOT_ELIGIBLE" && (
            <InlineFeedback tone="warning">Este Set não é elegível para sincronização de preços.</InlineFeedback>
          )}

          {!loading && !result?.error && result?.state === "NO_ACTIVE_SOURCE" && (
            <InlineFeedback tone="warning">Nenhuma fonte de preço está ativa no momento.</InlineFeedback>
          )}

          {!loading && !result?.error && result?.state === "ALREADY_CONFIRMED" && result.alreadyConfirmed && (
            <InlineFeedback tone="success">
              Este Set já está confirmado como{" "}
              <strong>{result.alreadyConfirmed.externalSetName ?? result.alreadyConfirmed.externalSetId}</strong>. Atualize a
              página — este mapeamento não deveria mais aparecer como "Sem mapeamento".
            </InlineFeedback>
          )}

          {!loading && !result?.error && result?.state === "SAFE_CANDIDATE" && result.candidate && (
            <div className="space-y-2 rounded-md border border-success/30 bg-success/5 p-3">
              <p className="text-sm font-medium text-foreground">Correspondência encontrada na JustTCG</p>
              <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
                <dt className="text-muted-foreground">Nome externo</dt>
                <dd className="text-foreground">{result.candidate.externalSetName}</dd>
                <dt className="text-muted-foreground">ID externo</dt>
                <dd>
                  <code className="text-xs text-foreground">{result.candidate.externalSetId}</code>
                </dd>
                <dt className="text-muted-foreground">Lançamento (fonte)</dt>
                <dd className="text-foreground">{result.candidate.releaseDateRaw ?? "—"}</dd>
              </dl>
              <p className="text-xs text-muted-foreground">
                Nada foi salvo ainda — confirme abaixo para gravar este mapeamento. Nenhuma sincronização de preços é
                disparada automaticamente; o Set fica aguardando a primeira execução programada.
              </p>
              {confirmError && <InlineFeedback tone="error">{confirmError}</InlineFeedback>}
            </div>
          )}

          {!loading && !result?.error && result?.state === "AMBIGUOUS" && result.candidates && (
            <div className="space-y-2">
              <p className="text-sm text-foreground">
                Mais de um Set externo corresponde a este Set local — nenhum foi escolhido automaticamente.
              </p>
              <ul className="space-y-1.5">
                {result.candidates.map((c) => (
                  <li key={c.externalSetId} className="rounded-md border border-border p-2 text-sm">
                    <div className="font-medium text-foreground">{c.externalSetName}</div>
                    <div className="text-xs text-muted-foreground">
                      <code>{c.externalSetId}</code> · {c.releaseDateRaw ?? "—"}
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {!loading && !result?.error && result?.state === "NOT_FOUND" && (
            <InlineFeedback tone="warning">
              Nenhuma correspondência foi encontrada na JustTCG para este Set no momento.
            </InlineFeedback>
          )}
        </DialogBody>

        <DialogFooter>
          <Button type="button" variant="outline" size="sm" onClick={onClose} disabled={confirming}>
            Fechar
          </Button>
          {!loading && !result?.error && result?.state === "SAFE_CANDIDATE" && (
            <Button type="button" size="sm" onClick={handleConfirm} disabled={confirming}>
              {confirming ? "Confirmando…" : "Confirmar correspondência"}
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function EditSetMappingDialog({
  open,
  item,
  onSaved,
  onCancel,
}: {
  open: boolean;
  item: PricingSetMappingItem | null;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Editar Mapeamento de Set</DialogTitle>
          <DialogDescription>
            {item ? `${item.cardSetName} (${item.cardSetCode}) · ${item.pricingSourceCode}` : "Identidade externa deste Set."}
          </DialogDescription>
        </DialogHeader>

        {open && item && <EditSetMappingForm key={item.id} item={item} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />}
      </DialogContent>
    </Dialog>
  );
}

function EditSetMappingForm({
  item,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  item: PricingSetMappingItem;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const initialState: AtualizarDetalhesMapeamentoSetState = { error: null };
  const [state, formAction, pending] = useActionState(atualizarDetalhesMapeamentoSet, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      // P16.1: `item.id` é `string | null` no tipo geral (Sets sem mapeamento, UNMAPPED), mas
      // este formulário só é renderizado a partir do botão de edição, que não existe mais na
      // linha UNMAPPED (ver "Sincronizar" desabilitado em mapeamentos-sets-table.tsx) — `?? undefined`
      // só satisfaz o compilador, nunca é o caminho real.
      onSaved("Mapeamento de Set atualizado com sucesso.", item.id ?? undefined);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={item.id ?? ""} />
      <DialogBody className="space-y-3">
        <div className="space-y-1">
          <Label htmlFor={`edit-set-mapping-external-id-${item.id}`}>
            ID externo {item.hasDependency && <span className="text-muted-foreground">(protegido)</span>}
          </Label>
          <Input
            id={`edit-set-mapping-external-id-${item.id}`}
            name="external_set_id"
            defaultValue={item.externalSetId ?? ""}
            readOnly={item.hasDependency}
            aria-readonly={item.hasDependency}
            className={item.hasDependency ? "cursor-not-allowed bg-surface-muted opacity-70" : undefined}
          />
          {item.hasDependency && (
            <p className="text-xs text-muted-foreground">
              Este Set já tem mapeamento de carta confirmado ou dado de preço vinculado a esta fonte — o identificador externo
              não pode mais ser alterado por aqui.
            </p>
          )}
        </div>

        <div className="space-y-1">
          <Label htmlFor={`edit-set-mapping-external-name-${item.id}`}>Nome externo (descritivo)</Label>
          <Input
            id={`edit-set-mapping-external-name-${item.id}`}
            name="external_set_name"
            defaultValue={item.externalSetName ?? ""}
            maxLength={200}
          />
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

function ReclassifySetMappingDialog({
  open,
  item,
  onSaved,
  onCancel,
}: {
  open: boolean;
  item: PricingSetMappingItem | null;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>{item?.matchStatus === "CONFIRMED" ? "Rejeitar" : "Confirmar"} Mapeamento de Set</DialogTitle>
          <DialogDescription>
            {item ? `${item.cardSetName} (${item.cardSetCode}) · ${item.pricingSourceCode}` : ""} — informe o motivo desta
            reclassificação, registrado no log de auditoria.
          </DialogDescription>
        </DialogHeader>

        {open && item && (
          <ReclassifySetMappingForm key={item.id} item={item} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function ReclassifySetMappingForm({
  item,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  item: PricingSetMappingItem;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const initialState: ReclassificarMapeamentoSetState = { error: null };
  const [state, formAction, pending] = useActionState(reclassificarMapeamentoSet, initialState);
  const newStatus = item.matchStatus === "CONFIRMED" ? "REJECTED" : "CONFIRMED";

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      // P16.1: mesmo caso do EditSetMappingForm acima — este formulário só existe para Sets já
      // mapeados, `item.id` nunca é null no caminho real, `?? undefined` só satisfaz o tipo geral.
      onSaved(
        newStatus === "REJECTED" ? "Mapeamento rejeitado com sucesso." : "Mapeamento confirmado com sucesso.",
        item.id ?? undefined,
      );
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={item.id ?? ""} />
      <input type="hidden" name="new_status" value={newStatus} />
      <DialogBody className="space-y-3">
        <div className="space-y-1">
          <Label htmlFor={`reclassify-set-mapping-reason-${item.id}`}>Motivo</Label>
          <textarea
            id={`reclassify-set-mapping-reason-${item.id}`}
            name="reason"
            required
            maxLength={500}
            placeholder="Explique por que este mapeamento está sendo reclassificado."
            className={textareaClassName}
          />
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" variant={newStatus === "REJECTED" ? "destructive" : "default"} disabled={pending}>
          {pending ? "Salvando…" : newStatus === "REJECTED" ? "Rejeitar" : "Confirmar"}
        </Button>
      </DialogFooter>
    </form>
  );
}
