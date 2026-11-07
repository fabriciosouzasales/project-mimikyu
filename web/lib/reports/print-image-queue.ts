/**
 * V1-14 R1-G — fila do preparo de miniaturas para a impressão (sem DOM; testável).
 *
 * - Só entram as imagens ainda não prontas (`isReady`): o que já carregou é preservado e conta no
 *   progresso desde o início — uma nova tentativa processa apenas as pendentes ou com falha.
 * - No máximo `concurrency` carregamentos ao mesmo tempo (6).
 * - Sem teto global de tempo: cada imagem tem o próprio limite (aplicado por `load`); uma imagem
 *   que não responde vira falha individual e a fila segue.
 * - `onProgress(prontas, total)` a cada imagem concluída — progresso real.
 */
export const PRINT_IMAGE_CONCURRENCY = 6;
export const PRINT_IMAGE_ITEM_TIMEOUT_MS = 30_000;

export type PrintImagesResult<T> = { total: number; ready: number; failed: T[] };

export async function prepareImageQueue<T>(
  items: readonly T[],
  options: {
    isReady: (item: T) => boolean;
    /** Carrega uma imagem; `true` = pronta, `false` = falhou ou não respondeu no limite. */
    load: (item: T) => Promise<boolean>;
    concurrency?: number;
    onProgress?: (ready: number, total: number) => void;
  },
): Promise<PrintImagesResult<T>> {
  const total = items.length;
  const pending = items.filter((item) => !options.isReady(item));
  let ready = total - pending.length;
  const failed: T[] = [];
  options.onProgress?.(ready, total);
  let next = 0;
  const worker = async () => {
    while (next < pending.length) {
      const item = pending[next++] as T;
      let ok = false;
      try {
        ok = await options.load(item);
      } catch {
        ok = false;
      }
      if (ok) {
        ready += 1;
        options.onProgress?.(ready, total);
      } else failed.push(item);
    }
  };
  const lanes = Math.min(Math.max(1, options.concurrency ?? PRINT_IMAGE_CONCURRENCY), pending.length);
  await Promise.all(Array.from({ length: lanes }, worker));
  return { total, ready, failed };
}
