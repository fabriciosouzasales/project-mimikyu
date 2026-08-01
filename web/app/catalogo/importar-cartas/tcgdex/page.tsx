import { redirect } from "next/navigation";

/**
 * Redirect puro — a partir de 2026-08-01 (redesenho visual da página
 * Importar Cartas), a etapa "selecionar Coleção + localizar Set na TCGdex"
 * deixou de ser esta rota própria e passou a viver direto em
 * `/catalogo/importar-cartas` (`?fonte=api&cardSetId=...`). Esta rota
 * continua existindo só para não quebrar links/favoritos antigos —
 * `[jobId]/page.tsx` (revisão/confirmação do job) e `actions.ts` (Server
 * Actions) continuam intocados e são a razão de o segmento `tcgdex/`
 * continuar existindo.
 */
export default async function ImportarViaTcgdexRedirectPage({
  searchParams,
}: {
  searchParams: Promise<{ cardSetId?: string }>;
}) {
  const { cardSetId } = await searchParams;
  const query = cardSetId ? `?cardSetId=${encodeURIComponent(cardSetId)}` : "";
  redirect(`/catalogo/importar-cartas${query}`);
}
