"use client";

import { ArrowLeft, ArrowRight } from "lucide-react";
import Link from "next/link";
import { useMemo, useState } from "react";
import {
  confirmarCandidatoMapeamentoPricing,
  confirmarMapeamentoPricing,
  marcarMapeamentoComoNaoEncontrado,
  rejeitarMapeamentoPricing,
} from "@/app/pricing/resolucao-mapeamentos/actions";
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
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
import type { PricingMappingDetail, PricingMappingDetailIdentity } from "@/lib/pricing/queries";
import { cn } from "@/lib/utils";

const textareaClassName =
  "flex min-h-20 w-full rounded-md border border-input bg-surface px-3 py-2 text-sm shadow-subtle transition-colors placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50";

const IDENTITY_STATUS_LABEL: Record<string, string> = {
  PENDING: "Pendente",
  CONFIRMED: "Confirmada",
  REJECTED: "Rejeitada",
};

const IDENTITY_STATUS_TONE: Record<string, StateTone> = {
  PENDING: "warning",
  CONFIRMED: "success",
  REJECTED: "danger",
};

function formatPrice(price: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency: currencyCode }).format(price);
  } catch {
    return `${price.toFixed(2)} ${currencyCode}`;
  }
}

function formatDateTime(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

function IdentityPrices({ prices }: { prices: PricingMappingDetailIdentity["prices"] }) {
  if (prices.length === 0) {
    return <p className="text-xs text-muted-foreground">Sem preços observados ainda para esta identidade.</p>;
  }
  return (
    <div className="flex flex-wrap gap-1.5">
      {prices.map((price, index) => (
        <span
          key={`${price.conditionId}-${price.priceType}-${index}`}
          className="inline-flex items-center rounded-full border border-border bg-surface-muted/60 px-2 py-0.5 text-[11px] text-foreground"
        >
          {price.marketLabel ?? price.priceType}: {formatPrice(price.price, price.currencyCode)}
        </span>
      ))}
    </div>
  );
}

/**
 * Detalhe + resolução de um mapping pendente (Bloco 2 do Pricing Admin,
 * migration 3940; extensão NOT_FOUND manual, migration 3963; confirmação
 * por candidato de `match_evidence`, migration 3964) — carta, variantes
 * locais, candidatas e a decisão em si. Duas fontes de candidata,
 * mutuamente exclusivas por mapping: `identities` (1..N
 * `pricing_source_card_identity` já persistidas — caminho original, migration
 * 3940, hoje raro para PENDING recém-classificado) e `mapping.candidates`
 * (brutos de `match_evidence.candidatos`, migration 3964 — caso comum: a
 * última classificação automática achou 2+ candidatas, nenhuma foi
 * materializada como identity ainda). Nunca as duas ao mesmo tempo na
 * prática, mas a UI prioriza `identities` se ambas existirem (não deveria
 * acontecer, mas evita ambiguidade). Três ações possíveis: com qualquer
 * candidata disponível, Confirmar (1..N via identities, ou exatamente 1 via
 * candidato bruto) ou Rejeitar (motivo obrigatório); sem candidata alguma,
 * Marcar como Não Encontrado substitui as duas — o backend bloqueia
 * NOT_FOUND se `match_evidence.candidatos` ainda tiver algo (migration
 * 3964). Mesma disciplina de `ResolverMapeamentoDialog`: confirmação
 * explícita via Dialog antes do write, `pending`/`error` locais. Decisão
 * bem-sucedida nunca volta um valor para este componente — a Server Action
 * termina em `redirect("/pricing/mapeamentos-cartas")` (2026-08-27,
 * correção de gap de UX); só o caminho de erro resolve normalmente com
 * `{ error }`, ver `actions.ts`.
 *
 * Regra de Principal (PRIMARY): só uma identidade incluída pode ser
 * Principal por vez (mesma trava de `uq_pricing_source_card_identity_active_primary_per_mapping`
 * no banco — aqui é só UX, a garantia real é a RPC). As demais incluídas
 * viram ALTERNATE. ALIAS não aparece como opção nesta V1: a trigger
 * `validate_pricing_source_card_identity_canonical` exige que o canonical já
 * esteja CONFIRMED antes do write, então nenhuma candidata PENDING chega com
 * `identity_role = ALIAS` — ver nota na migration 3940.
 *
 * Candidato bruto (`mapping.candidates`): nunca é selecionável em múltiplos
 * — o backend só aceita exatamente 1 `p_candidate_external_card_id` por
 * chamada. Radio-select simples, sem noção de PRIMARY/ALTERNATE (a identity
 * criada é sempre PRIMARY, única, na própria RPC).
 */
export function ResolucaoMapeamentoDetail({ detail }: { detail: PricingMappingDetail }) {
  const pendingIdentities = useMemo(() => detail.identities.filter((i) => i.matchStatus === "PENDING"), [detail.identities]);
  const rawCandidates = detail.mapping.candidates;
  const hasIdentities = detail.identities.length > 0;

  const [included, setIncluded] = useState<Set<string>>(new Set());
  const [primaryId, setPrimaryId] = useState<string | null>(null);
  const [variantTypeByIdentity, setVariantTypeByIdentity] = useState<Record<string, string>>({});
  const [selectedCandidateId, setSelectedCandidateId] = useState<string | null>(null);
  const [confirmDialogOpen, setConfirmDialogOpen] = useState(false);
  const [confirmCandidateDialogOpen, setConfirmCandidateDialogOpen] = useState(false);
  const [rejectDialogOpen, setRejectDialogOpen] = useState(false);
  const [rejectReason, setRejectReason] = useState("");
  const [notFoundDialogOpen, setNotFoundDialogOpen] = useState(false);
  const [notFoundReason, setNotFoundReason] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const hasCandidates = hasIdentities || rawCandidates.length > 0;

  function toggleIncluded(identityId: string) {
    setIncluded((prev) => {
      const next = new Set(prev);
      if (next.has(identityId)) {
        next.delete(identityId);
        if (primaryId === identityId) setPrimaryId(null);
      } else {
        next.add(identityId);
        if (!primaryId) setPrimaryId(identityId);
      }
      return next;
    });
  }

  const canConfirm = included.size > 0 && primaryId !== null;

  function handleConfirmSubmit() {
    if (!canConfirm || !primaryId) return;
    setPending(true);
    setError(null);
    const assignments = Array.from(included).map((identityId) => ({
      identityId,
      identityRole: (identityId === primaryId ? "PRIMARY" : "ALTERNATE") as "PRIMARY" | "ALTERNATE",
      canonicalIdentityId: null,
      cardVariantTypeId: variantTypeByIdentity[identityId] || null,
    }));
    // Sucesso: a Server Action chama `redirect()` internamente e o Next.js
    // navega direto para a fila antes deste `.then()` resolver de fato — só
    // o caminho de erro chega até aqui (ver comentário em `actions.ts`).
    confirmarMapeamentoPricing(detail.mapping.id, assignments).then((res) => {
      setPending(false);
      if (res?.error) {
        setError(res.error);
      }
    });
  }

  function handleConfirmCandidateSubmit() {
    if (!selectedCandidateId) return;
    setPending(true);
    setError(null);
    confirmarCandidatoMapeamentoPricing(detail.mapping.id, selectedCandidateId).then((res) => {
      setPending(false);
      if (res?.error) {
        setError(res.error);
      }
    });
  }

  function handleRejectSubmit() {
    if (!rejectReason.trim()) {
      setError("Informe o motivo da rejeição.");
      return;
    }
    setPending(true);
    setError(null);
    rejeitarMapeamentoPricing(detail.mapping.id, rejectReason.trim()).then((res) => {
      setPending(false);
      if (res?.error) {
        setError(res.error);
      }
    });
  }

  function handleNotFoundSubmit() {
    if (!notFoundReason.trim()) {
      setError("Informe o motivo.");
      return;
    }
    setPending(true);
    setError(null);
    marcarMapeamentoComoNaoEncontrado(detail.mapping.id, notFoundReason.trim()).then((res) => {
      setPending(false);
      if (res?.error) {
        setError(res.error);
      }
    });
  }

  return (
    <div className="space-y-4">
      <Card>
        <div className="flex gap-4 p-6 sm:gap-6">
          <div className="w-28 shrink-0 self-stretch sm:w-36">
            {detail.card.thumbnailUrl ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={detail.card.thumbnailUrl}
                alt=""
                loading="lazy"
                decoding="async"
                className="h-full w-full rounded-md border border-border object-cover"
              />
            ) : (
              <div className="flex h-full min-h-[168px] w-full items-center justify-center rounded-md border border-dashed border-border bg-surface-muted p-1 text-center text-[9px] leading-tight text-muted-foreground">
                Sem imagem
              </div>
            )}
          </div>
          <div className="flex min-w-0 flex-1 flex-col">
            <div className="min-w-0 space-y-1">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <p className="truncate text-sm font-semibold text-foreground">{detail.card.name}</p>
                <StateBadge tone={detail.mapping.matchStatus === "NOT_FOUND" ? "danger" : "warning"}>
                  {detail.mapping.matchStatus === "NOT_FOUND" ? "Não encontrado" : "Pendente"}
                </StateBadge>
              </div>
              <p className="text-xs text-muted-foreground">
                {detail.card.collectorNumber}
                {detail.card.collectorTotal ? `/${detail.card.collectorTotal}` : ""} · {detail.card.cardSetName} (
                {detail.card.cardSetCode})
              </p>
              <p className="text-xs text-muted-foreground">
                Fonte {detail.mapping.pricingSourceCode} · Última verificação:{" "}
                {formatDateTime(detail.mapping.lastCheckedAt)}
              </p>
            </div>
            <div className="mt-auto min-w-0 pt-4">
              <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
                Variantes locais desta carta
              </p>
              {detail.localVariants.length === 0 ? (
                <p className="mt-1 text-xs text-muted-foreground">Nenhuma variante cadastrada ainda.</p>
              ) : (
                <div className="mt-1.5 flex flex-wrap gap-1.5">
                  {detail.localVariants.map((v) => (
                    <span
                      key={v.id}
                      className="inline-flex items-center rounded-full border border-border bg-surface-muted/60 px-2 py-0.5 text-[11px] text-foreground"
                    >
                      {v.name} {v.isDefault && <span className="ml-1 text-muted-foreground">(padrão)</span>}
                    </span>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>

        {detail.missingVariant && (
          <CardContent className="pt-0">
            <InlineFeedback tone="warning">
              <div className="flex flex-col gap-1.5">
                <span>
                  Esta carta ainda não tem nenhuma variante cadastrada no Catálogo Editorial. É possível confirmar a
                  identidade mesmo assim (sem selecionar uma variante), mas o ideal é resolver isso na origem.
                </span>
                <Button asChild variant="outline" size="sm" className="w-fit">
                  <Link href="/catalogo/importar-variantes">
                    Ir para Importar Variantes
                    <ArrowRight className="ml-1.5 h-3.5 w-3.5" aria-hidden="true" />
                  </Link>
                </Button>
              </div>
            </InlineFeedback>
          </CardContent>
        )}
      </Card>

      {!hasIdentities && rawCandidates.length > 0 && (
        <Card>
          <CardHeader className="space-y-0.5">
            <p className="text-sm font-semibold text-foreground">Candidatas encontradas automaticamente</p>
            <p className="text-xs text-muted-foreground">
              A última busca nesta fonte encontrou {rawCandidates.length === 1 ? "1 candidata" : `${rawCandidates.length} candidatas`}{" "}
              para esta carta. Escolha exatamente uma para confirmar o mapeamento.
            </p>
          </CardHeader>
          <CardContent className="space-y-2">
            {rawCandidates.map((candidate) => {
              const isSelected = selectedCandidateId === candidate.id;
              return (
                <label
                  key={candidate.id}
                  className={cn(
                    "flex cursor-pointer items-start gap-2 rounded-md border border-border p-3 transition-colors",
                    isSelected && "border-primary/40 bg-primary/5",
                  )}
                >
                  <input
                    type="radio"
                    name="raw-candidate"
                    className="mt-1"
                    checked={isSelected}
                    onChange={() => setSelectedCandidateId(candidate.id)}
                  />
                  <div>
                    <p className="text-sm font-medium text-foreground">{candidate.name}</p>
                    <p className="text-xs text-muted-foreground">
                      ID externo: {candidate.id}
                      {candidate.number ? ` · Número: ${candidate.number}` : ""}
                    </p>
                  </div>
                </label>
              );
            })}
          </CardContent>
        </Card>
      )}

      {hasIdentities && (
      <Card>
        <CardHeader className="space-y-0.5">
          <p className="text-sm font-semibold text-foreground">Candidatas externas</p>
          <p className="text-xs text-muted-foreground">
            Marque as candidatas confirmadas e escolha qual é a Principal — as demais incluídas viram Alternativa.
          </p>
        </CardHeader>
        <CardContent className="space-y-3">
          {detail.identities.length === 0 ? (
            <p className="text-xs text-muted-foreground">Nenhuma candidata externa encontrada para este mapeamento.</p>
          ) : (
            detail.identities.map((identity) => {
              const isPending = identity.matchStatus === "PENDING";
              const isIncluded = included.has(identity.id);
              const isPrimary = primaryId === identity.id;
              return (
                <div
                  key={identity.id}
                  className={cn(
                    "rounded-md border border-border p-3 transition-colors",
                    isIncluded && "border-primary/40 bg-primary/5",
                    !isPending && "opacity-60",
                  )}
                >
                  <div className="flex flex-wrap items-start justify-between gap-2">
                    <div className="flex items-start gap-2">
                      <input
                        type="checkbox"
                        className="mt-1"
                        checked={isIncluded}
                        disabled={!isPending}
                        onChange={() => toggleIncluded(identity.id)}
                        aria-label={`Incluir candidata ${identity.externalCardName}`}
                      />
                      <div>
                        <p className="text-sm font-medium text-foreground">{identity.externalCardName}</p>
                        <p className="text-xs text-muted-foreground">
                          ID externo: {identity.externalCardId}
                          {identity.externalVariantKey ? ` · ${identity.externalVariantKey}` : ""}
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-1.5">
                      <StateBadge tone={IDENTITY_STATUS_TONE[identity.matchStatus] ?? "muted"}>
                        {IDENTITY_STATUS_LABEL[identity.matchStatus] ?? identity.matchStatus}
                      </StateBadge>
                    </div>
                  </div>

                  {isIncluded && (
                    <div className="mt-3 flex flex-wrap items-end gap-3 border-t border-border/60 pt-3">
                      <label className="flex items-center gap-1.5 text-xs text-foreground">
                        <input
                          type="radio"
                          name="primary-identity"
                          checked={isPrimary}
                          onChange={() => setPrimaryId(identity.id)}
                        />
                        Principal
                      </label>
                      {!isPrimary && <span className="text-xs text-muted-foreground">Alternativa</span>}

                      {detail.localVariants.length > 0 && (
                        <div className="space-y-1">
                          <Label className="text-[10px] uppercase tracking-wide text-muted-foreground">
                            Variante local (opcional)
                          </Label>
                          <Select
                            className="h-8 min-w-[12rem] text-xs"
                            value={variantTypeByIdentity[identity.id] ?? ""}
                            onChange={(e) =>
                              setVariantTypeByIdentity((prev) => ({ ...prev, [identity.id]: e.target.value }))
                            }
                          >
                            <option value="">Nenhuma</option>
                            {detail.localVariants.map((v) => (
                              <option key={v.variantTypeId} value={v.variantTypeId}>
                                {v.name}
                              </option>
                            ))}
                          </Select>
                        </div>
                      )}
                    </div>
                  )}

                  <div className="mt-2">
                    <IdentityPrices prices={identity.prices} />
                  </div>
                  <p className="mt-1.5 text-[11px] text-muted-foreground">
                    Última verificação: {formatDateTime(identity.lastCheckedAt)}
                    {identity.matchMethod ? ` · Método: ${identity.matchMethod}` : ""}
                  </p>
                </div>
              );
            })
          )}
        </CardContent>
      </Card>
      )}

      {error && <InlineFeedback tone="error">{error}</InlineFeedback>}

      <div className="flex flex-wrap items-center justify-between gap-2">
        <Button asChild variant="outline" size="sm">
          <Link href="/pricing/mapeamentos-cartas">
            <ArrowLeft className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />
            Voltar para Mapeamentos de Cartas
          </Link>
        </Button>
        <div className="flex items-center gap-2">
          {hasIdentities ? (
            <>
              <Button type="button" variant="outline" size="sm" onClick={() => setRejectDialogOpen(true)} disabled={pending}>
                Rejeitar
              </Button>
              <Button type="button" size="sm" disabled={!canConfirm || pending} onClick={() => setConfirmDialogOpen(true)}>
                Confirmar {included.size > 0 ? `(${included.size})` : ""}
              </Button>
            </>
          ) : hasCandidates ? (
            <>
              <Button type="button" variant="outline" size="sm" onClick={() => setRejectDialogOpen(true)} disabled={pending}>
                Rejeitar
              </Button>
              <Button
                type="button"
                size="sm"
                disabled={!selectedCandidateId || pending}
                onClick={() => setConfirmCandidateDialogOpen(true)}
              >
                Confirmar candidata selecionada
              </Button>
            </>
          ) : (
            <Button type="button" variant="outline" size="sm" onClick={() => setNotFoundDialogOpen(true)} disabled={pending}>
              Marcar como Não Encontrado
            </Button>
          )}
        </div>
      </div>

      <Dialog open={confirmDialogOpen} onOpenChange={(next) => !pending && setConfirmDialogOpen(next)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confirmar mapeamento</DialogTitle>
            <DialogDescription>
              {included.size === 1
                ? "1 candidata será confirmada como identidade deste mapeamento."
                : `${included.size} candidatas serão confirmadas juntas (1 Principal + ${included.size - 1} Alternativa${included.size - 1 === 1 ? "" : "s"}).`}{" "}
              Esta ação não pode ser desfeita por aqui.
            </DialogDescription>
          </DialogHeader>
          <DialogBody className="space-y-2">
            {Array.from(included).map((identityId) => {
              const identity = pendingIdentities.find((i) => i.id === identityId);
              if (!identity) return null;
              return (
                <div key={identityId} className="flex items-center justify-between text-xs">
                  <span className="text-foreground">{identity.externalCardName}</span>
                  <StateBadge tone={identityId === primaryId ? "success" : "muted"}>
                    {identityId === primaryId ? "Principal" : "Alternativa"}
                  </StateBadge>
                </div>
              );
            })}
            {error && <InlineFeedback tone="error">{error}</InlineFeedback>}
          </DialogBody>
          <DialogFooter>
            <Button type="button" variant="outline" size="sm" onClick={() => setConfirmDialogOpen(false)} disabled={pending}>
              Cancelar
            </Button>
            <Button type="button" size="sm" disabled={pending} onClick={handleConfirmSubmit}>
              {pending ? "Confirmando…" : "Confirmar mapeamento"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={confirmCandidateDialogOpen} onOpenChange={(next) => !pending && setConfirmCandidateDialogOpen(next)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Confirmar candidata</DialogTitle>
            <DialogDescription>
              {(() => {
                const candidate = rawCandidates.find((c) => c.id === selectedCandidateId);
                return candidate ? `"${candidate.name}" será confirmada como identidade Principal deste mapeamento.` : "";
              })()}{" "}
              Esta ação não pode ser desfeita por aqui.
            </DialogDescription>
          </DialogHeader>
          <DialogBody className="space-y-2">
            {error && <InlineFeedback tone="error">{error}</InlineFeedback>}
          </DialogBody>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => setConfirmCandidateDialogOpen(false)}
              disabled={pending}
            >
              Cancelar
            </Button>
            <Button type="button" size="sm" disabled={pending} onClick={handleConfirmCandidateSubmit}>
              {pending ? "Confirmando…" : "Confirmar candidata"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={rejectDialogOpen} onOpenChange={(next) => !pending && setRejectDialogOpen(next)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rejeitar mapeamento</DialogTitle>
            <DialogDescription>
              Nenhuma identidade nova é criada — o mapeamento fica marcado como REJECTED. O motivo é obrigatório e fica
              registrado no log de auditoria.
            </DialogDescription>
          </DialogHeader>
          <DialogBody className="space-y-2">
            <Label htmlFor="reject-reason">Motivo</Label>
            <textarea
              id="reject-reason"
              value={rejectReason}
              onChange={(e) => setRejectReason(e.target.value)}
              placeholder="Ex.: nenhuma candidata da fonte corresponde a esta carta."
              className={textareaClassName}
              maxLength={500}
            />
            {error && <InlineFeedback tone="error">{error}</InlineFeedback>}
          </DialogBody>
          <DialogFooter>
            <Button type="button" variant="outline" size="sm" onClick={() => setRejectDialogOpen(false)} disabled={pending}>
              Cancelar
            </Button>
            <Button type="button" variant="destructive" size="sm" disabled={pending || !rejectReason.trim()} onClick={handleRejectSubmit}>
              {pending ? "Rejeitando…" : "Rejeitar mapeamento"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={notFoundDialogOpen} onOpenChange={(next) => !pending && setNotFoundDialogOpen(next)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Marcar como Não Encontrado</DialogTitle>
            <DialogDescription>
              Significa que a busca nesta fonte foi concluída e nenhuma correspondência foi localizada para esta
              carta — diferente de Rejeitar, que descarta um candidato específico. Nenhuma identidade é criada. O
              motivo é obrigatório e fica registrado no log de auditoria. A fonte pode passar a cobrir esta carta no
              futuro; o mapeamento pode ser reavaliado depois.
            </DialogDescription>
          </DialogHeader>
          <DialogBody className="space-y-2">
            <Label htmlFor="not-found-reason">Motivo</Label>
            <textarea
              id="not-found-reason"
              value={notFoundReason}
              onChange={(e) => setNotFoundReason(e.target.value)}
              placeholder="Ex.: carta verificada manualmente na fonte, sem produto correspondente."
              className={textareaClassName}
              maxLength={500}
            />
            {error && <InlineFeedback tone="error">{error}</InlineFeedback>}
          </DialogBody>
          <DialogFooter>
            <Button type="button" variant="outline" size="sm" onClick={() => setNotFoundDialogOpen(false)} disabled={pending}>
              Cancelar
            </Button>
            <Button type="button" variant="destructive" size="sm" disabled={pending || !notFoundReason.trim()} onClick={handleNotFoundSubmit}>
              {pending ? "Salvando…" : "Marcar como Não Encontrado"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
