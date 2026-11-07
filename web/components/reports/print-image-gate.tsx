"use client";

import { type ReactNode, useEffect, useRef, useState } from "react";
import { PRINT_IMAGE_CONCURRENCY, PRINT_IMAGE_ITEM_TIMEOUT_MS, prepareImageQueue } from "@/lib/reports/print-image-queue";

/**
 * V1-14 R1-G — miniaturas prontas para a impressão de relatórios extensos, sem carregar tudo na
 * navegação normal e sem custo novo: as imagens são as ORIGINAIS do bucket `card-front`, no mesmo
 * endereço da tela (o navegador reaproveita o que já baixou); nenhuma transformação de imagem.
 *
 * - Na tela, as miniaturas acima do teto de carregamento imediato continuam sob demanda (`lazy`).
 * - `preparePrintImages(onProgress)` (botão Imprimir, via `ReportSheetEntry.preparePrint`) carrega
 *   só as miniaturas ainda pendentes, no máximo 6 ao mesmo tempo, com progresso real; cada uma tem
 *   30 s para responder (falha individual, sem teto global que descarte o progresso). As que já
 *   carregaram ficam; uma nova tentativa processa apenas as pendentes ou com falha. Assíncrono — a
 *   interface continua utilizável.
 * - `PrintImageGate` acompanha as miniaturas: enquanto houver alguma não carregada (pendente ou com
 *   falha), a folha impressa por Ctrl+P traz só um aviso (nunca quadros vazios por carregamento).
 * Sem dependência externa; só a API do navegador (`img.complete`, `naturalWidth`, eventos load/error).
 */
const GATE = "[data-print-image-gate]";

export type PrintProgress = { ready: number; total: number };

const isReady = (img: HTMLImageElement) => img.complete && img.naturalWidth > 0;

function pendingImages(root: ParentNode): HTMLImageElement[] {
  return [...root.querySelectorAll<HTMLImageElement>("img")].filter((img) => !isReady(img));
}

/** Uma miniatura: pede o carregamento (mesmo endereço) e espera load/error, até 30 s. */
function loadImage(img: HTMLImageElement, timeoutMs: number): Promise<boolean> {
  return new Promise((resolve) => {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const finish = (ok: boolean) => {
      if (timer) clearTimeout(timer);
      img.removeEventListener("load", onLoad);
      img.removeEventListener("error", onError);
      resolve(ok);
    };
    const onLoad = () => finish(img.naturalWidth > 0);
    const onError = () => finish(false);
    img.addEventListener("load", onLoad);
    img.addEventListener("error", onError);
    timer = setTimeout(() => finish(isReady(img)), timeoutMs);
    if (img.complete && img.naturalWidth === 0) {
      // Falhou antes: nova tentativa no MESMO endereço (cache do navegador preservado).
      const src = img.getAttribute("src");
      if (src) img.src = src;
    }
    if (img.loading === "lazy") img.loading = "eager";
    if (isReady(img)) finish(true);
  });
}

/** Prepara as miniaturas da folha; `true` = todas prontas. Nova chamada = só as que faltam. */
export async function preparePrintImages(onProgress?: (progress: PrintProgress) => void): Promise<boolean> {
  const root = document.querySelector(GATE);
  if (!root) return true;
  const images = [...root.querySelectorAll<HTMLImageElement>("img")];
  const result = await prepareImageQueue(images, {
    isReady,
    load: (img) => loadImage(img, PRINT_IMAGE_ITEM_TIMEOUT_MS),
    concurrency: PRINT_IMAGE_CONCURRENCY,
    onProgress: (ready, total) => onProgress?.({ ready, total }),
  });
  return result.failed.length === 0 && pendingImages(root).length === 0;
}

export function PrintImageGate({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [pending, setPending] = useState(0);

  useEffect(() => {
    const root = ref.current;
    if (!root) return;
    const images = [...root.querySelectorAll<HTMLImageElement>("img")];
    const update = () => setPending(pendingImages(root).length);
    for (const img of images) {
      img.addEventListener("load", update);
      img.addEventListener("error", update);
    }
    update();
    return () => {
      for (const img of images) {
        img.removeEventListener("load", update);
        img.removeEventListener("error", update);
      }
    };
  }, []);

  return (
    <div ref={ref} data-print-image-gate="" data-print-images={pending === 0 ? "ready" : "pending"}>
      <div className={pending > 0 ? "print:hidden" : undefined}>{children}</div>
      {pending > 0 ? (
        <p className="hidden text-sm print:block">
          As miniaturas do relatório ainda não terminaram de carregar; nada foi impresso. Use o botão Imprimir do relatório — ele
          prepara as imagens antes de abrir a impressão.
        </p>
      ) : null}
    </div>
  );
}
