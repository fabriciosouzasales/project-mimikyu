"use client";

import { Info, Loader2, RefreshCw } from "lucide-react";
import { useState, useTransition } from "react";
import { reprocessSpeciesArtwork } from "@/app/pokedex/imagens/actions";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
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
import { InlineFeedback, type FeedbackTone } from "@/components/ui/feedback";
import type { ArtworkStatus } from "@/lib/pokedex/admin-artwork-format";

/** Linha já formatada no servidor (datas com fuso fixo, rótulos em pt-BR, URL da miniatura validada). */
export type ArtworkAdminItem = {
  number: number;
  numberLabel: string;
  name: string;
  status: ArtworkStatus;
  statusLabel: string;
  attempts: number;
  lastAttempt: string | null;
  importedAt: string | null;
  errorCode: string | null;
  errorLabel: string | null;
  errorMessage: string | null;
  errorTransient: boolean;
  sourcePokemonId: string | null;
  originalPath: string | null;
  displayPath: string | null;
  displaySize: string | null;
  rights: string | null;
  thumbUrl: string | null;
};

const STATUS_BADGE: Record<ArtworkStatus, "success" | "warning" | "destructive"> = {
  IMPORTED: "success",
  PENDING: "warning",
  FAILED: "destructive",
};

/**
 * Tabela da administração de Imagens (Lote E): diagnóstico por espécie e
 * reprocessamento individual pela Server Action `reprocessSpeciesArtwork`.
 *
 * - Uma operação por vez na tela (todos os botões ficam desabilitados
 *   enquanto uma espécie é processada); o servidor também trava a espécie.
 * - Substituir uma imagem válida (IMPORTED) sempre passa por confirmação.
 * - O resultado aparece em feedback inline anunciado a leitores de tela; a
 *   lista é atualizada pelo `revalidatePath` da própria ação.
 */
export function ArtworkAdminTable({ items }: { items: ArtworkAdminItem[] }) {
  const [isPending, startTransition] = useTransition();
  const [runningNumber, setRunningNumber] = useState<number | null>(null);
  const [feedback, setFeedback] = useState<{ tone: FeedbackTone; message: string } | null>(null);
  const [detail, setDetail] = useState<ArtworkAdminItem | null>(null);
  const [confirmItem, setConfirmItem] = useState<ArtworkAdminItem | null>(null);

  function run(item: ArtworkAdminItem, confirmReplace: boolean) {
    setFeedback(null);
    setRunningNumber(item.number);
    startTransition(async () => {
      const result = await reprocessSpeciesArtwork({ nationalDexNumber: item.number, confirmReplace });
      setRunningNumber(null);
      setConfirmItem(null);
      setDetail(null);
      if (result.ok) {
        setFeedback({ tone: "success", message: result.message });
      } else if (result.reason === "needs_confirmation") {
        setConfirmItem(item);
      } else {
        setFeedback({ tone: result.imagePreserved || result.reason === "busy" ? "warning" : "error", message: result.message });
      }
    });
  }

  function request(item: ArtworkAdminItem) {
    if (item.status === "IMPORTED") setConfirmItem(item);
    else run(item, false);
  }

  return (
    <>
      <div role="status" aria-live="polite" className={feedback ? "px-3 pt-3" : undefined}>
        {feedback ? <InlineFeedback tone={feedback.tone}>{feedback.message}</InlineFeedback> : null}
      </div>

      <DataTable aria-busy={isPending}>
        <DataTableHead>
          <DataTableHeadRow>
            <DataTableHeadCell className="w-14 pl-3">Imagem</DataTableHeadCell>
            <DataTableHeadCell className="w-16">Nº</DataTableHeadCell>
            <DataTableHeadCell>Espécie</DataTableHeadCell>
            <DataTableHeadCell>Situação</DataTableHeadCell>
            <DataTableHeadCell className="hidden md:table-cell">Diagnóstico</DataTableHeadCell>
            <DataTableHeadCell align="right" className="hidden lg:table-cell">
              Tentativas
            </DataTableHeadCell>
            <DataTableHeadCell align="right" className="pr-3">
              <span className="sr-only">Ações</span>
            </DataTableHeadCell>
          </DataTableHeadRow>
        </DataTableHead>
        <tbody>
          {items.map((item) => {
            const running = runningNumber === item.number;
            return (
              <DataTableRow key={item.number}>
                <DataTableCell className="pl-3">
                  <Thumb item={item} size={40} />
                </DataTableCell>
                <DataTableCell className="tabular-nums">{item.numberLabel}</DataTableCell>
                <DataTableCell className="font-medium text-foreground">{item.name}</DataTableCell>
                <DataTableCell>
                  <Badge variant={STATUS_BADGE[item.status]}>{item.statusLabel}</Badge>
                </DataTableCell>
                <DataTableCell className="hidden max-w-[22rem] md:table-cell">
                  <Diagnosis item={item} />
                </DataTableCell>
                <DataTableCell align="right" className="hidden tabular-nums lg:table-cell">
                  {item.attempts}
                </DataTableCell>
                <DataTableCell align="right" className="pr-3">
                  <div className="flex items-center justify-end gap-1.5">
                    <Button
                      type="button"
                      variant="ghost"
                      size="icon-sm"
                      onClick={() => setDetail(item)}
                      aria-label={`Detalhes de Nº ${item.numberLabel} ${item.name}`}
                      title="Detalhes"
                    >
                      <Info className="h-3.5 w-3.5" />
                    </Button>
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      disabled={isPending}
                      onClick={() => request(item)}
                      aria-label={`${item.status === "PENDING" ? "Importar" : "Reprocessar"} imagem de Nº ${item.numberLabel} ${item.name}`}
                    >
                      {running ? (
                        <Loader2 className="h-3.5 w-3.5 animate-spin motion-reduce:animate-none" aria-hidden="true" />
                      ) : (
                        <RefreshCw className="h-3.5 w-3.5" aria-hidden="true" />
                      )}
                      <span className="hidden sm:inline">
                        {running ? "Processando…" : item.status === "PENDING" ? "Importar" : "Reprocessar"}
                      </span>
                    </Button>
                  </div>
                </DataTableCell>
              </DataTableRow>
            );
          })}
        </tbody>
      </DataTable>

      <DetailDialog
        item={detail}
        busy={isPending}
        onClose={() => setDetail(null)}
        onReprocess={(item) => {
          setDetail(null);
          request(item);
        }}
      />

      <Dialog open={confirmItem !== null} onOpenChange={(open) => !open && !isPending && setConfirmItem(null)}>
        <DialogContent hideClose={isPending}>
          <DialogHeader>
            <DialogTitle>Reprocessar uma imagem válida?</DialogTitle>
            <DialogDescription>
              {confirmItem ? `Nº ${confirmItem.numberLabel} ${confirmItem.name}` : null}
            </DialogDescription>
          </DialogHeader>
          <DialogBody className="space-y-2 text-sm text-muted-foreground">
            <p>
              A arte oficial será baixada e validada de novo. Se a origem não mudou, nada é alterado. Se mudou, a nova
              imagem passa a ser exibida.
            </p>
            <p>Os arquivos atuais nunca são sobrescritos, e em caso de falha a imagem atual é preservada.</p>
          </DialogBody>
          <DialogFooter>
            <Button type="button" variant="outline" disabled={isPending} onClick={() => setConfirmItem(null)}>
              Cancelar
            </Button>
            <Button type="button" disabled={isPending || !confirmItem} onClick={() => confirmItem && run(confirmItem, true)}>
              {isPending ? <Loader2 className="h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden="true" /> : null}
              {isPending ? "Processando…" : "Reprocessar"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function Thumb({ item, size }: { item: ArtworkAdminItem; size: number }) {
  return (
    <div
      className="flex items-center justify-center overflow-hidden rounded-md bg-surface-muted/70 dark:bg-surface-muted/40"
      style={{ width: size, height: size }}
    >
      {item.thumbUrl ? (
        // eslint-disable-next-line @next/next/no-img-element -- WebP de 320 px já otimizado, URL imutável
        <img
          src={item.thumbUrl}
          alt=""
          width={size}
          height={size}
          loading="lazy"
          decoding="async"
          className="h-full w-full object-contain p-[8%]"
        />
      ) : (
        <Pokeball className="h-1/2 w-1/2 text-foreground/15" strokeWidth={1.25} aria-hidden="true" />
      )}
    </div>
  );
}

function Diagnosis({ item }: { item: ArtworkAdminItem }) {
  if (item.status === "FAILED") {
    return (
      <span className="line-clamp-2 text-destructive dark:text-destructive-foreground">
        {item.errorLabel ?? "Falha sem diagnóstico."}
        {item.errorTransient ? <span className="text-muted-foreground"> Pode ser temporária.</span> : null}
      </span>
    );
  }
  if (item.status === "PENDING") return <span>Aguardando importação.</span>;
  if (item.errorCode) {
    return (
      <span className="line-clamp-2 text-warning">Última tentativa falhou; a imagem atual foi preservada.</span>
    );
  }
  return <span>{item.importedAt ? `Importada em ${item.importedAt}` : "Importada"}</span>;
}

function DetailDialog({
  item,
  busy,
  onClose,
  onReprocess,
}: {
  item: ArtworkAdminItem | null;
  busy: boolean;
  onClose: () => void;
  onReprocess: (item: ArtworkAdminItem) => void;
}) {
  const fields: [string, string | null][] = item
    ? [
        ["Situação", item.statusLabel],
        ["Tentativas", String(item.attempts)],
        ["Última tentativa", item.lastAttempt],
        ["Importada em", item.importedAt],
        ["Última falha", item.errorCode ? `${item.errorLabel ?? ""} (${item.errorCode})` : null],
        ["Mensagem técnica", item.errorMessage],
        ["Origem (PokéAPI, forma padrão)", item.sourcePokemonId ? `pokemon/${item.sourcePokemonId}` : null],
        ["Original (PNG)", item.originalPath],
        ["Galeria (WebP)", item.displayPath ? `${item.displayPath}${item.displaySize ? ` · ${item.displaySize}` : ""}` : null],
        ["Direitos de uso", item.rights],
      ]
    : [];

  return (
    <Dialog open={item !== null} onOpenChange={(open) => !open && onClose()}>
      <DialogContent size="lg">
        <DialogHeader>
          <DialogTitle>{item ? `Nº ${item.numberLabel} · ${item.name}` : "Detalhes"}</DialogTitle>
          <DialogDescription>Diagnóstico e proveniência da imagem.</DialogDescription>
        </DialogHeader>
        {item ? (
          <DialogBody className="flex flex-col gap-4 sm:flex-row">
            <div className="shrink-0 self-center sm:self-start">
              <Thumb item={item} size={128} />
            </div>
            <dl className="grid min-w-0 flex-1 grid-cols-1 gap-x-4 gap-y-2 text-xs sm:grid-cols-[auto_1fr]">
              {fields
                .filter(([, value]) => value)
                .map(([label, value]) => (
                  <div key={label} className="contents">
                    <dt className="text-muted-foreground">{label}</dt>
                    <dd className="break-all text-foreground">{value}</dd>
                  </div>
                ))}
            </dl>
          </DialogBody>
        ) : null}
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onClose}>
            Fechar
          </Button>
          {item ? (
            <Button type="button" disabled={busy} onClick={() => onReprocess(item)}>
              <RefreshCw className="h-4 w-4" aria-hidden="true" />
              {item.status === "PENDING" ? "Importar" : "Reprocessar"}
            </Button>
          ) : null}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
