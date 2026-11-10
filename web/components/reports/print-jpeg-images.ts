"use client";

import { PRINT_IMAGE_CONCURRENCY, prepareImageQueue } from "@/lib/reports/print-image-queue";
import { PRINT_JPEG_QUALITY, printJpegSize } from "@/lib/reports/print-jpeg";
import { type PrintProgress, preparePrintImages } from "./print-image-gate";

const DONE = "data-print-jpeg-ready";
const created = new Set<string>();

/**
 * Versão genérica do preparo de impressão do Caderno (`booklet-print-images.ts`, que fica intocado):
 * troca cada `<img>` do seletor por um JPEG no tamanho de impressão — o PDF do Chrome embute JPEG como
 * está e regrava WebP/PNG sem perdas (D7 §4p, CARD BOOKLET PDF OPTIMIZATION-01). Usado pelos
 * relatórios da Pokédex (F2-2) para a arte das espécies. Falha de conversão não bloqueia (a imagem
 * original continua); depois, o preparo homologado da R1-G.
 */
async function toPrintJpeg(img: HTMLImageElement, maxWidth: number): Promise<boolean> {
  if (img.hasAttribute(DONE)) return true;
  const src = img.currentSrc || img.src;
  if (!src || src.startsWith("blob:")) return true;
  try {
    const response = await fetch(src, { mode: "cors", credentials: "omit" });
    if (!response.ok) return false;
    const bitmap = await createImageBitmap(await response.blob());
    const { width, height } = printJpegSize(bitmap.width, bitmap.height, maxWidth);
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

export async function preparePrintJpegs(selector: string, maxWidth: number, onProgress?: (progress: PrintProgress) => void): Promise<boolean> {
  const images = [...document.querySelectorAll<HTMLImageElement>(selector)];
  const converted = await prepareImageQueue(images, {
    isReady: (img) => img.hasAttribute(DONE),
    load: (img) => toPrintJpeg(img, maxWidth),
    concurrency: PRINT_IMAGE_CONCURRENCY,
    onProgress: (ready, total) => onProgress?.({ ready, total }),
  });
  if (converted.failed.length > 0) console.warn("[relatórios] imagens mantidas no original para a impressão", { count: converted.failed.length });
  return preparePrintImages(onProgress);
}

export function releasePrintJpegs() {
  for (const url of created) URL.revokeObjectURL(url);
  created.clear();
}
