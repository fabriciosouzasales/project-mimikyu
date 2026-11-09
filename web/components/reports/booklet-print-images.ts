"use client";

import { PRINT_IMAGE_CONCURRENCY, prepareImageQueue } from "@/lib/reports/print-image-queue";
import { PRINT_JPEG_QUALITY, printJpegSize } from "@/lib/reports/print-jpeg";
import { type PrintProgress, preparePrintImages } from "./print-image-gate";

const SELECTOR = "[data-card-booklet] img[data-print-jpeg]";
const DONE = "data-print-jpeg-ready";
/** URLs criadas nesta aba — liberadas quando o caderno é desmontado. */
const created = new Set<string>();

/**
 * Converte uma carta para JPEG no tamanho de impressão e troca a fonte da `<img>` pela versão
 * convertida (a mesma imagem vista na tela, mais leve; nitidez acima da exibida). Leitura com CORS
 * (bucket público com `Access-Control-Allow-Origin`); se falhar, a original continua — a impressão
 * segue, só mais pesada. Nunca bloqueia.
 */
async function toPrintJpeg(img: HTMLImageElement): Promise<boolean> {
  if (img.hasAttribute(DONE)) return true;
  const src = img.currentSrc || img.src;
  if (!src || src.startsWith("blob:")) return true;
  try {
    const response = await fetch(src, { mode: "cors", credentials: "omit" });
    if (!response.ok) return false;
    const bitmap = await createImageBitmap(await response.blob());
    const { width, height } = printJpegSize(bitmap.width, bitmap.height);
    if (width === 0) return false;
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    if (!context) return false;
    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, width, height);
    context.imageSmoothingQuality = "high";
    context.drawImage(bitmap, 0, 0, width, height);
    bitmap.close();
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", PRINT_JPEG_QUALITY));
    if (!blob) return false;
    const url = URL.createObjectURL(blob);
    created.add(url);
    img.setAttribute(DONE, "");
    img.loading = "eager";
    img.src = url;
    return true;
  } catch {
    return false;
  }
}

/**
 * Preparo do Imprimir do Caderno: (1) cartas → JPEG de impressão (6 por vez, progresso real);
 * (2) o preparo homologado da R1-G garante todas as imagens carregadas antes de abrir a impressão.
 * Falha na conversão não bloqueia: a carta imprime com a imagem original.
 */
export async function prepareBookletPrint(onProgress?: (progress: PrintProgress) => void): Promise<boolean> {
  const images = [...document.querySelectorAll<HTMLImageElement>(SELECTOR)];
  const converted = await prepareImageQueue(images, {
    isReady: (img) => img.hasAttribute(DONE),
    load: toPrintJpeg,
    concurrency: PRINT_IMAGE_CONCURRENCY,
    onProgress: (ready, total) => onProgress?.({ ready, total }),
  });
  if (converted.failed.length > 0) console.warn("[caderno] cartas mantidas no original para a impressão", { count: converted.failed.length });
  return preparePrintImages(onProgress);
}

/** Libera as versões de impressão criadas (desmontagem do caderno). */
export function releaseBookletPrintImages() {
  for (const url of created) URL.revokeObjectURL(url);
  created.clear();
}
