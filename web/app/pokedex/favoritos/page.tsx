import type { Metadata } from "next";
import { PokedexGalleryPage } from "@/components/pokedex/pokedex-gallery-page";

export const metadata: Metadata = { title: "Pokémon Favoritos · Pokédex" };

/**
 * Pokémon Favoritos — /pokedex/favoritos (Pokédex P6, 2026-10-15; decisão D8).
 *
 * A mesma galeria da Pokédex Nacional (nenhuma segunda galeria nem componente
 * duplicado), recortada pelas espécies favoritas do usuário da sessão
 * (`get_my_pokedex_favorites`, Query 6137). Pesquisa, régua de gerações e filtro por
 * tipo (P5a) funcionam igual e ficam dentro desta página. Segmento estático: o App Router
 * o resolve antes de `/pokedex/[numero]` (precedente: `/pokedex/imagens`).
 */
export default function PokedexFavoritesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  return <PokedexGalleryPage searchParams={searchParams} mode="favorites" />;
}
