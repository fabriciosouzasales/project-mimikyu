"use client";

import { type ReactNode, useEffect, useRef, useState } from "react";
import { flushSync } from "react-dom";
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
/** Evento síncrono do preparo para o gate: "terminei" — o gate recalcula na hora (sem esperar `load`). */
const READY_EVENT = "mmkyu:print-images-checked";

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
  const ok = result.failed.length === 0 && pendingImages(root).length === 0;
  // Imagem que veio do cache do navegador fica pronta na hora e o `load` dela pode chegar DEPOIS da
  // impressão abrir: o preparo avisa o gate de forma síncrona (dispatchEvent é síncrono).
  root.dispatchEvent(new Event(READY_EVENT));
  // Garantia adicional: um quadro de animação para o navegador aplicar o gate pronto antes de imprimir.
  if (ok) await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
  return ok;
}

export function PrintImageGate({ children }: { children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const [pending, setPending] = useState(0);

  useEffect(() => {
    const root = ref.current;
    if (!root) return;
    const images = [...root.querySelectorAll<HTMLImageElement>("img")];
    const count = () => pendingImages(root).length;
    /*
     * Cada miniatura que termina atualiza o gate de forma SÍNCRONA (`flushSync`). Sem isso, o botão
     * Imprimir abria a impressão logo depois do preparo, antes de o React aplicar o novo estado, e a
     * 1ª impressão saía com o aviso de miniaturas pendentes (bug da homologação da R2-D). Os ouvintes
     * do gate são registrados na montagem, antes dos do preparo, então rodam primeiro na mesma imagem.
     */
    const onImage = () => flushSync(() => setPending(count()));
    for (const img of images) {
      img.addEventListener("load", onImage);
      img.addEventListener("error", onImage);
    }
    root.addEventListener(READY_EVENT, onImage);
    setPending(count());
    return () => {
      root.removeEventListener(READY_EVENT, onImage);
      for (const img of images) {
        img.removeEventListener("load", onImage);
        img.removeEventListener("error", onImage);
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
