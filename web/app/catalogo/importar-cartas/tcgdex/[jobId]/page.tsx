import { Globe } from "lucide-react";
import { notFound } from "next/navigation";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { JobStatusView } from "@/components/catalogo/job-status-view";
import { PageContainer } from "@/components/ui/page";
import { getCatalogImportJobStatus } from "@/lib/catalogo/queries";

/**
 * Passos "Progresso" + "Revisão" + "Confirmação" do fluxo TCGdex (Ciclo 2,
 * ADR-024). Nesta primeira versão (Sprint 2a) só acompanha o status/
 * contagens reais do job — revisão interativa (aprovar/rejeitar/pular
 * linhas) e confirmação em lote ficam para o próximo incremento (Sprint
 * 2b), deliberadamente fora deste.
 */
export default async function ImportacaoTcgdexJobPage({
  params,
}: {
  params: Promise<{ jobId: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Importação TCGdex", Globe);
  if (denied) return denied;

  const { jobId } = await params;
  const job = await getCatalogImportJobStatus(supabase, jobId);
  if (!job) return notFound();

  return (
    <AppShell title="Importação TCGdex" icon={Globe}>
      <PageContainer>
        <JobStatusView job={job} />
      </PageContainer>
    </AppShell>
  );
}
