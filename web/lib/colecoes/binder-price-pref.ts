/**
 * Preferência "Exibir preços" do fichário (V1-09, D2). Pessoal e do
 * dispositivo: chave própria no `localStorage`, sem sincronização entre
 * dispositivos e sem gravação no banco. Vale para todos os fichários do dono.
 * Padrão: ligada (ausente, ilegível ou formato inesperado → ligada).
 */
export const BINDER_PRICES_STORAGE_KEY = "mmkyu:binder-prices:v1";

export function parseBinderPricesPref(raw: string | null): boolean {
  if (!raw) return true;
  try {
    const value = JSON.parse(raw) as unknown;
    if (value && typeof value === "object" && (value as Record<string, unknown>).visible === false) return false;
    return true;
  } catch {
    return true;
  }
}

export function serializeBinderPricesPref(visible: boolean): string {
  return JSON.stringify({ visible });
}
