import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { Heart } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { FavoriteCardsView, type FavoriteCardView } from "@/components/favorites/favorite-cards-view";
import { FAVORITES_PAGE_SIZE, parsePageParam } from "@/lib/favorites/card-favorites";
import {
  getMyFavoriteCards,
  getMyFavoriteCardSetCount,
  getMyFavoriteOwnedCount,
  getMyFavoriteReferenceValue,
} from "@/lib/favorites/card-favorites-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser } from "@/lib/supabase/request-auth-cache";

export const metadata: Metadata = { title: "Cartas favoritas · Coleções" };

/**
 * Cartas favoritas — /colecoes/favoritos (V1-10).
 *
 * Página pessoal: sem sessão → /login; a autorização real está no banco
 * (`get_my_favorite_cards`, Query 5336, resolve o dono por `auth.uid()`). Uma leitura
 * paginada (60 por página, mais recentes primeiro). Imagens: mesma origem pública da
 * Pesquisa (bucket `card-front`, frente primária pt-BR ou en). Os cards reutilizam o
 * tile da Pesquisa (arte com brilho, etiqueta de preço NM em lote, ampliar) e o mesmo
 * coração — desfavoritar aqui atenua a carta no lugar até a próxima navegação.
 */
export default async function FavoriteCardsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const page = parsePageParam(params.pagina);

  const {
    data: { user },
  } = await getCachedUser();
  if (!user) redirect("/login");

  const supabase = await createClient();
  // Quatro leituras em paralelo, todas como o usuário da sessão e agregadas no banco:
  // a página de favoritos (5336, traz o total), o valor de referência com cobertura
  // (5340), as favoritas no acervo (5339) e os Card Sets (5338). Cada uma falha sozinha.
  const [result, referenceValue, ownedCount, favoriteCardSetCount] = await Promise.all([
    getMyFavoriteCards(supabase, page),
    getMyFavoriteReferenceValue(supabase),
    getMyFavoriteOwnedCount(supabase),
    getMyFavoriteCardSetCount(supabase),
  ]);

  const publicUrl = (path: string | null) => (path ? supabase.storage.from("card-front").getPublicUrl(path).data.publicUrl : null);
  const cards: FavoriteCardView[] | null = result
    ? result.cards.map((card) => ({
        id: card.cardId,
        name: card.name,
        collectorNumber: card.collectorNumber,
        collectorTotal: card.collectorTotal,
        cardSet: { id: card.cardSetCode, code: card.cardSetCode, name: card.cardSetName },
        category: null,
        rarity: null,
        imageUrlPt: publicUrl(card.imagePathPt),
        imageUrlEn: publicUrl(card.imagePathEn),
      }))
    : null;

  const totalPages = result ? Math.max(1, Math.ceil(result.totalCount / FAVORITES_PAGE_SIZE)) : 1;

  return (
    <AppShell title="Cartas favoritas" icon={Heart}>
      <FavoriteCardsView
        cards={cards}
        totalCount={result?.totalCount ?? 0}
        referenceValue={referenceValue}
        ownedCount={ownedCount}
        favoriteCardSetCount={favoriteCardSetCount}
        page={page}
        totalPages={totalPages}
      />
    </AppShell>
  );
}
