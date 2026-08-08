"use client";

import { useMemo, useRef, useState } from "react";
import { AlertTriangle, CheckCircle2, FileWarning, Trash2, UploadCloud } from "lucide-react";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import {
  extensionOf,
  MANUAL_ASSET_MIME_TYPES,
  sha256Hex,
  stripExtension,
  validateManualAssetExtensionAndMime,
} from "@/lib/catalogo/manual-asset-import/core";
import type { CartaManualImportManifestRow } from "@/lib/catalogo/queries";
import { createClient } from "@/lib/supabase/client";
import { cn } from "@/lib/utils";
import {
  fecharLoteImportacaoManual,
  persistirImagemManual,
  type FalhaImportacaoManual,
} from "@/app/catalogo/importar-imagens/manual-actions";

const STORAGE_BUCKET = "card-front";

type RowStatus = "ok" | "already-has-image" | "duplicate" | "not-found" | "unsupported-extension";

type ReviewRow = {
  file: File;
  collectorNumber: string;
  status: RowStatus;
  cardName: string | null;
};

const STATUS_LABEL: Record<RowStatus, string> = {
  ok: "OK",
  "already-has-image": "Já tem imagem",
  duplicate: "Duplicado na seleção",
  "not-found": "Carta não encontrada",
  "unsupported-extension": "Extensão não suportada",
};

const STATUS_TONE: Record<RowStatus, string> = {
  ok: "text-success",
  "already-has-image": "text-warning",
  duplicate: "text-destructive",
  "not-found": "text-destructive",
  "unsupported-extension": "text-destructive",
};

const BLOCKING_STATUSES: RowStatus[] = ["duplicate", "not-found", "unsupported-extension"];

type FileOutcome = {
  collectorNumber: string;
  fileName: string;
  success: boolean;
  error?: string;
};

type ImportPhase = "idle" | "reviewing" | "uploading" | "done";

/**
 * Seletor + validação prévia + upload do modo Manual da tela
 * `/catalogo/importar-imagens` (ADR-026, emenda "Segundo ponto de entrada
 * via UI", 2026-08-08). Fluxo:
 *
 * 1. Seleção de arquivos via `<input type="file">` (multi-seleção nativa do
 *    navegador — nunca um campo de texto para caminho local, pedido
 *    explícito de Fabrício).
 * 2. Validação prévia contra o manifesto já carregado da Coleção+idioma
 *    (`manifest`, de `getCartasParaImportacaoManual`): nome/extensão,
 *    duplicidade dentro da seleção, Card inexistente, Card já com imagem —
 *    tudo no cliente, sem round-trip por arquivo. Só libera "Importar" com
 *    zero linhas bloqueantes (duplicidade/inexistente/extensão).
 * 3. Upload: bytes vão direto do navegador para o Storage (`card-front`),
 *    em um path sempre novo (`{set}/{idioma}/{collector_number}-{uuid}.
 *    {ext}`) — nunca reaproveita um path existente, exatamente para o
 *    rollback nunca poder apagar um arquivo bom anterior (ver ADR-026).
 *    Depois do upload, `persistirImagemManual()` (Server Action) resolve o
 *    Card e chama `admin_persist_manual_card_asset()` só com metadados.
 *    Falha na persistência → remove o arquivo recém-subido. Sucesso com
 *    `previousStoragePath` → remove o arquivo antigo só agora, nunca antes.
 * 4. Ao final do lote inteiro, `fecharLoteImportacaoManual()` grava uma
 *    única linha de auditoria (nunca uma por arquivo).
 *
 * Validação client-side é conveniência de UX — `persistirImagemManual()`
 * roda a validação de novo, server-side, como autoridade final (o
 * manifesto pode ter ficado desatualizado entre o carregamento da página e
 * o clique em "Importar").
 */
export function ImportarImagensManualPicker({
  cardSetId,
  cardSetCode,
  languageCode,
  manifest,
  onDone,
}: {
  cardSetId: string;
  cardSetCode: string;
  languageCode: string;
  manifest: CartaManualImportManifestRow[];
  onDone: () => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [rows, setRows] = useState<ReviewRow[]>([]);
  const [phase, setPhase] = useState<ImportPhase>("idle");
  const [progress, setProgress] = useState({ current: 0, total: 0 });
  const [outcomes, setOutcomes] = useState<FileOutcome[]>([]);
  const [batchError, setBatchError] = useState<string | null>(null);

  const manifestByCollectorNumber = useMemo(() => {
    const map = new Map<string, CartaManualImportManifestRow>();
    for (const card of manifest) map.set(card.collectorNumber, card);
    return map;
  }, [manifest]);

  const supabase = useMemo(() => createClient(), []);

  const hasBlockingRows = rows.some((row) => BLOCKING_STATUSES.includes(row.status));
  const importableCount = rows.filter((row) => !BLOCKING_STATUSES.includes(row.status)).length;

  function handleFilesSelected(fileList: FileList | null) {
    if (!fileList || fileList.length === 0) return;

    const files = Array.from(fileList);
    const seenCollectorNumbers = new Set<string>();
    const nextRows: ReviewRow[] = [];

    for (const file of files) {
      const collectorNumber = stripExtension(file.name);
      const extension = extensionOf(file.name);
      const card = manifestByCollectorNumber.get(collectorNumber);

      let status: RowStatus;
      if (!MANUAL_ASSET_MIME_TYPES[extension]) {
        status = "unsupported-extension";
      } else if (seenCollectorNumbers.has(collectorNumber)) {
        status = "duplicate";
      } else if (!card) {
        status = "not-found";
      } else if (card.hasImage) {
        status = "already-has-image";
      } else {
        status = "ok";
      }

      seenCollectorNumbers.add(collectorNumber);
      nextRows.push({ file, collectorNumber, status, cardName: card?.name ?? null });
    }

    nextRows.sort((a, b) => a.collectorNumber.localeCompare(b.collectorNumber, undefined, { numeric: true }));
    setRows(nextRows);
    setPhase("reviewing");
    setOutcomes([]);
    setBatchError(null);
  }

  function removeRow(file: File) {
    setRows((current) => current.filter((row) => row.file !== file));
  }

  async function handleImportar() {
    const runId = crypto.randomUUID();
    const toImport = rows.filter((row) => !BLOCKING_STATUSES.includes(row.status));

    setPhase("uploading");
    setProgress({ current: 0, total: toImport.length });
    setBatchError(null);

    const newOutcomes: FileOutcome[] = [];
    let insertedCount = 0;
    let updatedCount = 0;

    for (const [index, row] of toImport.entries()) {
      const extension = extensionOf(row.file.name);
      const mimeType = MANUAL_ASSET_MIME_TYPES[extension];
      const newStoragePath = `${cardSetCode.toLowerCase()}/${languageCode}/${row.collectorNumber}-${crypto.randomUUID()}.${extension}`;

      try {
        if (!mimeType) {
          throw new Error(`Extensão não suportada: ${extension}`);
        }

        validateManualAssetExtensionAndMime(extension, row.file.type || mimeType);

        const bytes = new Uint8Array(await row.file.arrayBuffer());
        const checksum = await sha256Hex(bytes);

        const { error: uploadError } = await supabase.storage
          .from(STORAGE_BUCKET)
          .upload(newStoragePath, bytes, { contentType: mimeType, upsert: false });

        if (uploadError) {
          throw new Error(`Falha ao enviar o arquivo: ${uploadError.message}`);
        }

        const result = await persistirImagemManual({
          cardSetId,
          cardSetCode,
          languageCode,
          collectorNumber: row.collectorNumber,
          storagePath: newStoragePath,
          mimeType,
          fileExtension: extension,
          fileSizeBytes: bytes.byteLength,
          checksumSha256: checksum,
        });

        if (result.error || !result.action) {
          // Persistência falhou depois do upload — remove só o arquivo que
          // ACABOU de subir (path sempre novo, nunca toca em nada anterior).
          await supabase.storage.from(STORAGE_BUCKET).remove([newStoragePath]);
          throw new Error(result.error ?? "Falha ao persistir a imagem.");
        }

        if (result.action === "INSERTED") insertedCount += 1;
        if (result.action === "UPDATED") updatedCount += 1;

        // Sucesso confirmado — só agora remove o arquivo anterior, se havia.
        if (result.previousStoragePath && result.previousStoragePath !== newStoragePath) {
          await supabase.storage.from(STORAGE_BUCKET).remove([result.previousStoragePath]);
        }

        newOutcomes.push({ collectorNumber: row.collectorNumber, fileName: row.file.name, success: true });
      } catch (error) {
        const message = error instanceof Error ? error.message : "Falha inesperada.";
        newOutcomes.push({ collectorNumber: row.collectorNumber, fileName: row.file.name, success: false, error: message });
      }

      setProgress({ current: index + 1, total: toImport.length });
    }

    setOutcomes(newOutcomes);

    const failures: FalhaImportacaoManual[] = newOutcomes
      .filter((outcome) => !outcome.success)
      .map((outcome) => ({ collectorNumber: outcome.collectorNumber, fileName: outcome.fileName, error: outcome.error ?? "Motivo não informado." }));

    const batchResult = await fecharLoteImportacaoManual({
      cardSetId,
      languageCode,
      runId,
      filesTotal: toImport.length,
      insertedCount,
      updatedCount,
      failedCount: failures.length,
      failures,
    });

    if (batchResult.error) {
      setBatchError(batchResult.error);
    }

    setPhase("done");
    onDone();
  }

  function reset() {
    setRows([]);
    setPhase("idle");
    setOutcomes([]);
    setBatchError(null);
    if (inputRef.current) inputRef.current.value = "";
  }

  return (
    <div className="space-y-4">
      <input
        ref={inputRef}
        type="file"
        multiple
        accept="image/png,image/jpeg,image/webp"
        className="hidden"
        onChange={(event) => handleFilesSelected(event.target.files)}
      />

      {phase === "idle" && (
        <div className="flex flex-col items-center justify-center gap-2 rounded-md border border-dashed border-border bg-surface-muted px-6 py-10 text-center">
          <UploadCloud className="h-6 w-6 text-muted-foreground" aria-hidden="true" />
          <p className="text-sm text-muted-foreground">Selecione os arquivos de imagem desta Coleção/idioma.</p>
          <Button type="button" variant="outline" size="sm" onClick={() => inputRef.current?.click()}>
            Selecionar arquivos
          </Button>
          <p className="text-[11px] text-muted-foreground">
            O nome de cada arquivo (sem extensão) deve ser igual ao número da carta. PNG, JPEG ou WEBP.
          </p>
        </div>
      )}

      {(phase === "reviewing" || phase === "uploading" || phase === "done") && rows.length > 0 && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">
              {rows.length} arquivo{rows.length === 1 ? "" : "s"} selecionado{rows.length === 1 ? "" : "s"} —{" "}
              {importableCount} pronto{importableCount === 1 ? "" : "s"} para importar.
            </p>
            {phase === "reviewing" && (
              <Button type="button" variant="ghost" size="sm" onClick={() => inputRef.current?.click()}>
                Trocar seleção
              </Button>
            )}
          </div>

          <div className="max-h-72 overflow-auto rounded-md border border-border">
            <table className="w-full text-left text-[13px]">
              <thead className="sticky top-0 bg-surface-muted text-[11px] uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-3 py-2 font-medium">Arquivo</th>
                  <th className="px-3 py-2 font-medium">Número</th>
                  <th className="px-3 py-2 font-medium">Carta</th>
                  <th className="px-3 py-2 font-medium">Status</th>
                  <th className="px-3 py-2" />
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {rows.map((row) => {
                  const outcome = outcomes.find(
                    (item) => item.collectorNumber === row.collectorNumber && item.fileName === row.file.name,
                  );
                  return (
                    <tr key={`${row.file.name}-${row.collectorNumber}`}>
                      <td className="truncate px-3 py-1.5 text-foreground">{row.file.name}</td>
                      <td className="px-3 py-1.5 text-foreground">{row.collectorNumber}</td>
                      <td className="truncate px-3 py-1.5 text-muted-foreground">{row.cardName ?? "—"}</td>
                      <td className={cn("px-3 py-1.5 font-medium", STATUS_TONE[row.status])}>
                        {outcome
                          ? outcome.success
                            ? "Importado"
                            : `Falhou: ${outcome.error}`
                          : STATUS_LABEL[row.status]}
                      </td>
                      <td className="px-3 py-1.5 text-right">
                        {phase === "reviewing" && (
                          <button
                            type="button"
                            onClick={() => removeRow(row.file)}
                            className="text-muted-foreground hover:text-destructive"
                            aria-label={`Remover ${row.file.name} da seleção`}
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </button>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {hasBlockingRows && phase === "reviewing" && (
            <Alert variant="destructive">
              <FileWarning className="h-4 w-4" aria-hidden="true" />
              Há arquivos com problema (duplicado, carta não encontrada ou extensão não suportada) — remova-os da
              seleção ou corrija antes de importar. Eles não serão enviados.
            </Alert>
          )}

          {phase === "reviewing" && (
            <div className="flex items-center gap-2">
              <Button type="button" onClick={handleImportar} disabled={importableCount === 0}>
                Importar {importableCount} arquivo{importableCount === 1 ? "" : "s"}
              </Button>
              <Button type="button" variant="ghost" onClick={reset}>
                Cancelar
              </Button>
            </div>
          )}

          {phase === "uploading" && (
            <p className="text-sm text-muted-foreground">
              Importando {progress.current} de {progress.total}...
            </p>
          )}

          {phase === "done" && (
            <div className="space-y-2">
              <Alert variant={outcomes.every((o) => o.success) ? "success" : "destructive"}>
                {outcomes.filter((o) => o.success).length} de {outcomes.length} arquivos importados com sucesso.
              </Alert>
              {batchError && (
                <Alert variant="destructive">
                  <AlertTriangle className="h-4 w-4" aria-hidden="true" />
                  Falha ao gravar a auditoria do lote: {batchError}
                </Alert>
              )}
              <Button type="button" variant="outline" size="sm" onClick={reset}>
                Importar mais arquivos
              </Button>
            </div>
          )}
        </div>
      )}

      {phase === "done" && rows.length === 0 && (
        <Alert variant="success">
          <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
          Lote concluído.
        </Alert>
      )}
    </div>
  );
}
