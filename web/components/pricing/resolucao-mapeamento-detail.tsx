"use client";

import { ArrowLeft, ArrowRight, CheckCircle2 } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useMemo, useState } from "react";
import { confirmarMapeamentoPricing, rejeitarMapeamentoPricing } from "@/app/pricing/resolucao-mapeamentos/actions";
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
 * migration 3940) — carta, variantes locais, candidatas externas com
 * roles/qualifiers/preços, e a decisão em si (Confirmar 1..N candidatas ou
 * Rejeitar com motivo obrigatório). Mesma disciplina de
 * `ResolverMapeamentoDialog`: confirmação explícita via Dialog antes do
 * write, `pending`/`error` locais, nunca lança — a action sempre volta
 * `{ error }`.
 *
 * Regra de Principal (PRIMARY): só uma identidade incluída pode ser
 * Principal por vez (mesma trava de `uq_pricing_source_card_identity_active_primary_per_mapping`
 * no banco — aqui é só UX, a garantia real é a RPC). As demais incluídas
 * viram ALTERNATE. ALIAS não aparece como opção nesta V1: a trigger
 * `validate_pricing_source_card_identity_canonical` exige que o canonical já
 * esteja CONFIRMED antes do write, então nenhuma candidata PENDING chega com
 * `identity_role = ALIAS` — ver nota na migration 3940.
 */
export function ResolucaoMapeamentoDetail({ detail }: { detail: PricingMappingDetail }) {
  const router = useRouter();
  const pendingIdentities = useMemo(() => detail.identities.filter((i) => i.matchStatus === "PENDING"), [detail.identities]);

  const [included, setIncluded] = useState<Set<string>>(new Set());
  const [primaryId, setPrimaryId] = useState<string | null>(null);
  const [variantTypeByIdentity, setVariantTypeByIdentity] = useState<Record<string, string>>({});
  const [confirmDialogOpen, setConfirmDialogOpen] = useState(false);
  const [rejectDialogOpen, setRejectDialogOpen] = useState(false);
  const [rejectReason, setRejectReason] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<"CONFIRMED" | "REJECTED" | null>(null);

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
    confirmarMapeamentoPricing(detail.mapping.id, assignments).then((res) => {
      setPending(false);
      if (res.error) {
        setError(res.error);
        return;
      }
      setConfirmDialogOpen(false);
      setResult("CONFIRMED");
      router.refresh();
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
      if (res.error) {
        setError(res.error);
        return;
      }
      setRejectDialogOpen(false);
      setResult("REJECTED");
      router.refresh();
    });
  }

  if (result) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center gap-3 py-10 text-center">
          <CheckCircle2 className="h-8 w-8 text-success" aria-hidden="true" />
          <p className="text-sm font-medium text-foreground">
            {result === "CONFIRMED" ? "Mapeamento confirmado." : "Mapeamento rejeitado."}
          </p>
          <p className="text-xs text-muted-foreground">
            {detail.card.name} ({detail.card.collectorNumber}) — {detail.mapping.pricingSourceCode}
          </p>
          <Button asChild variant="outline" size="sm">
            <Link href="/pricing/pendencias">
              <ArrowLeft className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />
              Voltar para Pendências
            </Link>
          </Button>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="flex-row flex-wrap items-center justify-between gap-2 space-y-0">
          <div>
            <p className="text-sm font-semibold text-foreground">{detail.card.name}</p>
            <p className="text-xs text-muted-foreground">
              {detail.card.collectorNumber}
              {detail.card.collectorTotal ? `/${detail.card.collectorTotal}` : ""} · {detail.card.cardSetName} (
              {detail.card.cardSetCode}) · Fonte {detail.mapping.pricingSourceCode}
            </p>
          </div>
          <StateBadge tone={detail.mapping.matchStatus === "NOT_FOUND" ? "danger" : "warning"}>
            {detail.mapping.matchStatus === "NOT_FOUND" ? "Não encontrado" : "Pendente"}
          </StateBadge>
        </CardHeader>
        <CardContent className="space-y-3">
          <div>
            <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Variantes locais desta carta</p>
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

          {detail.missingVariant && (
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
          )}
        </CardContent>
      </Card>

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

      {error && <InlineFeedback tone="error">{error}</InlineFeedback>}

      <div className="flex flex-wrap items-center justify-between gap-2">
        <Button asChild variant="outline" size="sm">
          <Link href="/pricing/pendencias">
            <ArrowLeft className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />
            Voltar para Pendências
          </Link>
        </Button>
        <div className="flex items-center gap-2">
          <Button type="button" variant="outline" size="sm" onClick={() => setRejectDialogOpen(true)} disabled={pending}>
            Rejeitar
          </Button>
          <Button type="button" size="sm" disabled={!canConfirm || pending} onClick={() => setConfirmDialogOpen(true)}>
            Confirmar {included.size > 0 ? `(${included.size})` : ""}
          </Button>
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
    </div>
  );
}
