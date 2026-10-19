import { PokedexGalleryPage } from "@/components/pokedex/pokedex-gallery-page";

/**
 * Pokédex Nacional — entrada do módulo Pokédex (Pokédex P1, 2026-10-12; P3c/P4/P5a).
 *
 * P6 (2026-10-15): a composição foi movida, sem mudança de comportamento, para
 * `PokedexGalleryPage` (components/pokedex/pokedex-gallery-page.tsx), compartilhada com
 * a página Pokémon Favoritos (`/pokedex/favoritos`). A única novidade aqui é o coração
 * de favorito nos cards e a leitura agregada dos favoritos do usuário (Query 6137).
 */
export default function PokedexPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  return <PokedexGalleryPage searchParams={searchParams} mode="national" />;
}
