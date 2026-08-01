"use client";

import { useRouter } from "next/navigation";
import { RefreshCw } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import type { CatalogImportJobStatus } from "@/lib/catalogo/queries";

const STATUS_LABEL: Record<string, string> = {
  RECEIVED: "Recebido",
  PROCESSING: "Processando",
  STAGED: "Aguardando revisão",
  CONFIRMING: "Confirmando",
  COMPLETED: "Concluído",
  COMPLETED_WITH_ERRORS: "Concluído com erros",
  FAILED: "Falhou",
  CANCELLED: "Cancelado",
};

// Textos em português — backend só grava o código estável (ver comentário
// de catalog_import_job.progress_step, Query 2060): "Só tem sentido durante
// status = PROCESSING; os textos e ícones pertencem inteiramente ao
// frontend".
const PROGRESS_STEP_LABEL: Record<string, string> = {
  FETCHING_SOURCE: "Buscando na TCGdex",
  EXTRACTING_CARDS: "Extraindo cartas",
  DETECTING_RARITY: "Identificando raridade",
  CLASSIFYING_CATEGORY: "Classificando categoria",
  VALIDATING_SEQUENCE: "Validando sequência",
  MATCHING_CATALOG: "Comparando com o catálogo",
  PREPARING_REVIEW: "Preparando revisão",
};

/**
 * Acompanhamento do job (Ciclo 2, Sprint 2a) — status real + contagens,
 * sem atualização automática ainda (botão "Atualizar" manual via
 * router.refresh()). Polling automático fica para o Sprint 2b, quando a
 * tela ganha a revisão interativa que justifica reconsultar sozinha.
 */
export function JobStatusView({ job }: { job: CatalogImportJobStatus }) {
  const router = useRouter();

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <PageTitle>Importação — {job.cardSetName || job.cardSetCode}</PageTitle>
          <PageDescription>{job.cardSetCode}</PageDescription>
        </PageHeading>
      </PageHeader>

      <Card>
        <CardHeader className="flex-row items-center justify-between space-y-0">
          <div className="flex items-center gap-2">
            <Badge variant="outline">{STATUS_LABEL[job.status] ?? job.status}</Badge>
            {job.progressStep && (
              <span className="text-sm text-muted-foreground">
                {PROGRESS_STEP_LABEL[job.progressStep] ?? job.progressStep}
              </span>
            )}
          </div>
          <Button variant="outline" size="sm" onClick={() => router.refresh()}>
            <RefreshCw className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />
            Atualizar
          </Button>
        </CardHeader>
        <CardContent className="space-y-3">
          {job.errorSummary && <p className="text-sm text-destructive">{job.errorSummary}</p>}
          <dl className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
            <StatItem label="Linhas" value={job.totalRows} />
            <StatItem label="Válidas" value={job.validRows} />
            <StatItem label="Inseridas" value={job.insertedRows} />
            <StatItem label="Falhas" value={job.failedRows} />
          </dl>
          <p className="text-xs text-muted-foreground">
            Revisão e confirmação interativas chegam no próximo incremento — por ora, esta tela só acompanha o
            status real do job.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}

function StatItem({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="text-lg font-semibold text-foreground">{value}</dd>
    </div>
  );
}
