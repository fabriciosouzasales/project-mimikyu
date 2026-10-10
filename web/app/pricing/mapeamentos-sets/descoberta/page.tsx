import { ChevronLeft, Layers } from "lucide-react";
import Link from "next/link";
import { AppShell } from "@/components/app-shell/app-shell";
import { DescobertaSetsLote } from "@/components/pricing/descoberta-sets-lote";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getPricingSetMappings } from "@/lib/pricing/queries";

/**
 * Descoberta de correspondências em lote (PRICING-MODULE-RECOVERY-01, Fase 3, 2026-10-10).
 * O servidor só mede o tamanho da pendência (Sets sem mapeamento CONFIRMED e suas cartas
 * ativas); a consulta à JustTCG acontece apenas quando o admin pede (custa 1 requisição).
 */
export default async function DescobertaCorrespondenciasPage() {
  const { denied, supabase } = await requirePricingAdmin("Descobrir correspondências", Layers);
  if (denied) return denied;

  const pendentes = await getPricingSetMappings(supabase, {
    status: ["UNMAPPED", "PENDING", "NOT_FOUND", "REJECTED"],
    limit: 500,
    offset: 0,
  });
  const setIds = pendentes.items.map((i) => i.cardSetId);
  let pendingCards = 0;
  if (setIds.length > 0) {
    const { count } = await supabase
      .from("card")
      .select("id", { count: "exact", head: true })
      .eq("is_active", true)
      .in("card_set_id", setIds);
    pendingCards = count ?? 0;
  }

  return (
    <AppShell title="Descobrir correspondências" icon={Layers}>
      <PageContainer className="space-y-4">
        <Link
          href="/pricing/mapeamentos-sets"
          className="inline-flex items-center gap-1 rounded-sm text-xs text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <ChevronLeft className="h-3.5 w-3.5" aria-hidden="true" />
          Mapeamentos de Sets
        </Link>
        <PageHeader>
          <PageHeading>
            <PageTitle>Descobrir correspondências</PageTitle>
            <PageDescription>
              Vincule os Sets do catálogo aos Sets da JustTCG para que suas cartas passem a receber preço.
            </PageDescription>
          </PageHeading>
        </PageHeader>

        <DescobertaSetsLote pendingSets={pendentes.totalCount} pendingCards={pendingCards} />
      </PageContainer>
    </AppShell>
  );
}
