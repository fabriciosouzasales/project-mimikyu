/**
 * URL pública da arte de uma espécie (Pokédex P2 Lote C).
 *
 * A única entrada é o `artwork_path` devolvido por `get_pokedex_national_species`
 * (Query 6132) — nunca um caminho montado a partir do número. A URL usa o
 * endpoint público do bucket próprio `pokemon-species-artwork` no projeto
 * Supabase do MMKYU, sem consulta adicional ao banco e sem depender de
 * servidores externos para renderizar.
 *
 * Defesa: só caminhos no formato gravado pela 6132 (WebP de galeria,
 * endereçado por conteúdo) viram URL; qualquer outro valor cai no fallback.
 * Como o caminho contém o hash do arquivo, a URL é imutável — o navegador e a
 * CDN podem guardá-la indefinidamente (o importador envia com cache de 1 ano).
 */
export const SPECIES_ARTWORK_BUCKET = "pokemon-species-artwork";

const DISPLAY_PATH = /^official-artwork\/[0-9]{4}\/w320-[0-9a-f]{16}\.webp$/;

export function speciesArtworkUrl(path: string | null | undefined): string | null {
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!base || !path || !DISPLAY_PATH.test(path)) return null;
  return `${base.replace(/\/+$/, "")}/storage/v1/object/public/${SPECIES_ARTWORK_BUCKET}/${path}`;
}

/** Quantas imagens do topo da grade carregam com prioridade (o restante é lazy). */
export const PRIORITY_ARTWORK_COUNT = 12;
