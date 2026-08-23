import { GitMerge } from "lucide-react";
import Link from "next/link";
import { AppShell } from "@/components/app-shell/app-shell";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { ResolucaoMapeamentoDetail } from "@/components/pricing/resolucao-mapeamento-detail";
import { Alert } from "@/components/ui/alert";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { getPricingMappingDetail } from "@/lib/pricing/queries";

/**
 * Resolução de Mapeamentos (Bloco 2 do Pricing Admin, migration 3940) —
 * ponto de chegada a partir de Pendências (`?mapping=<id>`), nunca uma
 * listagem própria: a triagem/paginação vive só em `/pricing/pendencias`,
 * esta rota é o fluxo de decisão de UM mapping por vez.
 *
 * Três estados possíveis: (1) sem `?mapping=`, orienta a voltar para
 * Pendências; (2) mapping não encontrado/inacessível (`getPricingMappingDetail`
 * retorna `null`); (3) mapping já decidido por outra pessoa entre a listagem
 * e o clique (`match_status` fora de PENDING/NOT_FOUND) — mesma janela de
 * corrida que a RPC já bloqueia no write, aqui é só a mensagem correspondente.
 */
export default async function PricingResolucaoMapeamentosPage({
  searchParams,
}: {
  searchParams: Promise<{ mapping?: string }>;
}) {
  const { denied, supabase } = await requirePricingAdmin("Resolução de Mapeamentos", GitMerge);
  if (denied) return denied;

  const { mapping: mappingId } = await searchParams;

  return (
    <AppShell title="Resolução de Mapeamentos" icon={GitMerge}>
      <PageContainer className="space-y-4">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <GitMerge className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Resolução de Mapeamentos</PageTitle>
            </div>
            <PageDescription>
              Fluxo administrativo de resolução manual de mapeamentos pendentes ou ambíguos.
            </PageDescription>
          </PageHeading>
        </PageHeader>

        {!mappingId ? (
          <EmptyState
            icon={GitMerge}
            title="Nenhum mapeamento selecionado"
            description='Escolha um item em "Pendências" e clique em Resolver para abrir o fluxo de decisão aqui.'
            className="py-14"
          />
        ) : (
          await renderMappingDetail(mappingId)
        )}
      </PageContainer>
    </AppShell>
  );

  async function renderMappingDetail(id: string) {
    const detail = await getPricingMappingDetail(supabase, id);

    if (!detail) {
      return (
        <Alert variant="destructive">
          Mapeamento não encontrado — ele pode ter sido removido ou o link está incorreto.{" "}
          <Link href="/pricing/pendencias" className="underline">
            Voltar para Pendências
          </Link>
          .
        </Alert>
      );
    }

    if (detail.mapping.matchStatus !== "PENDING" && detail.mapping.matchStatus !== "NOT_FOUND") {
      return (
        <Alert variant="destructive">
          Este mapeamento já foi decidido ({detail.mapping.matchStatus === "CONFIRMED" ? "confirmado" : "rejeitado"} por
          outro administrador).{" "}
          <Link href="/pricing/pendencias" className="underline">
            Voltar para Pendências
          </Link>
          .
        </Alert>
      );
    }

    return <ResolucaoMapeamentoDetail detail={detail} />;
  }
}
