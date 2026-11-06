import type { Metadata } from "next";
import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { ClipboardCheck } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { CollectionChecklistReport } from "@/components/reports/collection-checklist-report";
import reportStyles from "@/components/reports/report.module.css";
import { collectionHref, isCollectionId } from "@/lib/colecoes/colecoes";
import { prepareChecklistReport } from "@/lib/reports/checklist-queries";
import { parseChecklistFilter } from "@/lib/reports/collection-checklist";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser } from "@/lib/supabase/request-auth-cache";

export const metadata: Metadata = { title: "Checklist de completude · Relatórios" };

/**
 * Acesso DIRETO ao "Checklist de completude" — /colecoes/colecoes/[id]/relatorios/checklist
 * (V1-14 R1-A). Rota auxiliar: o fluxo principal abre o relatório em sobreposição sobre a
 * coleção, pela cápsula do cabeçalho (UX REDIRECTION-02). Mesma preparação
 * (`prepareChecklistReport`), mesmas regras.
 *
 * Só o titular: `get_my_collection` (5332) devolve zero linhas para coleção alheia ou
 * compartilhada com você → 404, sem distinguir os casos. As posições vêm das leituras
 * canônicas do titular (5169 Set padrão, 5189/5198 Master Set), em lotes, até o conjunto
 * inteiro do filtro — a folha impressa só existe quando ele está completo. Somente leitura.
 */
export default async function ChecklistReportPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  if (!isCollectionId(id)) notFound();
  const collectionId = id.toLowerCase();
  const filter = parseChecklistFilter(query.situacao);

  const {
    data: { user },
  } = await getCachedUser();
  if (!user) redirect("/login");

  const supabase = await createClient();
  const result = await prepareChecklistReport(supabase, collectionId, filter);
  if (result.status === "not_found") notFound();
  if (result.status === "error") {
    return (
      <AppShell title="Relatórios" icon={ClipboardCheck}>
        <div className={reportStyles.root}>
          <div className={reportStyles.state} role="alert">
            <h2>Não conseguimos abrir esta coleção</h2>
            <p>Nada foi perdido. Recarregue a página em instantes.</p>
          </div>
        </div>
      </AppShell>
    );
  }
  if (result.status === "unavailable") {
    return (
      <AppShell title={result.name} icon={ClipboardCheck}>
        <div className={reportStyles.root}>
          <div className={reportStyles.state}>
            <ClipboardCheck className="h-6 w-6" aria-hidden="true" />
            <h2>Checklist indisponível para esta coleção</h2>
            <p>Nesta etapa, o Checklist de completude existe para coleções de Set padrão e Master Set.</p>
            <Link href={collectionHref(collectionId)} className={reportStyles.stateAction}>
              Voltar à coleção
            </Link>
          </div>
        </div>
      </AppShell>
    );
  }

  return (
    <AppShell title={result.data.collection.name} icon={ClipboardCheck}>
      <CollectionChecklistReport {...result.data} />
    </AppShell>
  );
}
