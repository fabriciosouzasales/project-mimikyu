"use client";

import { RefreshCw } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
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
 * Acompanhamento do job (Ciclo 2, Sprint 2a) — status real + contagens.
 * Revisão interativa e confirmação (Sprint 2b) vivem em
 * RevisaoImportacaoTable, renderizada abaixo deste componente por quem
 * chama — polling automático continua fora de escopo (as ações de
 * decisão/confirmação já disparam `onRefresh` sozinhas).
 *
 * Simplificado em 2026-08-01 (segunda rodada, pedido de Fabrício: "a tabela
 * com a lista de cartas [seja] apresentada na mesma página") — perdeu o
 * PageHeader/PageTitle próprio (título de página duplicado não faz sentido
 * embutido) e os indicadores viraram uma linha de texto simples em vez do
 * `dl` de 4 colunas com números grandes — pedido explícito: "os
 * indicadores podem ser mais discretos... em label simples".
 *
 * `onRefresh` (era `router.refresh()`, terceira rodada — ver comentário de
 * `useAnalyzeJob` em importar-tcgdex-view.tsx): job/linhas viraram estado
 * de componente cliente, não mais derivados de `?jobId=` na URL — um
 * `router.refresh()` aqui não teria mais nada de servidor pra buscar de
 * novo. Quem chama passa a mesma função usada por RevisaoImportacaoTable.
 *
 * SEM USO ATUALMENTE (2026-08-01, sexta rodada) — Fabrício pediu pra
 * eliminar este card ("Importação") da tela; o conteúdo que ele mostrava
 * (status, contagens, erro) migrou pra dentro da etapa "Concluído" de
 * `ImportProgress` (importar-tcgdex-view.tsx). Mantido aqui intacto (não
 * apagado) — grep confirma que nada mais importa este componente hoje.
 */
export function JobStatusView({
  job,
  onRefresh,
}: {
  job: CatalogImportJobStatus;
  onRefresh: () => void;
}) {
  return (
    <Card>
      <CardHeader className="flex-row flex-wrap items-center justify-between gap-2 space-y-0">
        <div className="flex flex-wrap items-center gap-2">
          <p className="text-sm font-semibold text-foreground">Importação — {job.cardSetName || job.cardSetCode}</p>
          <Badge variant="outline">{STATUS_LABEL[job.status] ?? job.status}</Badge>
          {job.progressStep && (
            <span className="text-xs text-muted-foreground">
              {PROGRESS_STEP_LABEL[job.progressStep] ?? job.progressStep}
            </span>
          )}
        </div>
        <Button variant="outline" size="sm" onClick={onRefresh}>
          <RefreshCw className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />
          Atualizar
        </Button>
      </CardHeader>
      <CardContent className="space-y-1.5">
        {job.errorSummary && <p className="text-sm text-destructive">{job.errorSummary}</p>}
        <p className="text-xs text-muted-foreground">
          {job.totalRows} linhas · {job.validRows} válidas · {job.insertedRows} inseridas ·{" "}
          {job.updatedRows} atualizadas · {job.failedRows} falhas
        </p>
      </CardContent>
    </Card>
  );
}
