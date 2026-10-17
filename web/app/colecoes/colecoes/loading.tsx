import { cookies } from "next/headers";
import { LibraryBig } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Skeleton } from "@/components/ui/skeleton";
import acervoStyles from "@/components/colecoes/acervo/acervo.module.css";
import styles from "@/components/colecoes/colecoes/colecoes.module.css";
import carouselStyles from "@/components/colecoes/colecoes/library-carousel.module.css";
import modeStyles from "@/components/colecoes/colecoes/library-modes.module.css";
import { LIBRARY_MODE_COOKIE, resolveLibraryMode } from "@/lib/colecoes/colecoes";

/**
 * Carregamento da Biblioteca — mesma geometria da página real no modo que o
 * colecionador escolheu por último (cookie; a URL não chega ao loading).
 * Cards: capas 26:33. Lista: linhas com miniatura. Carrossel: palco central.
 * Sem atraso artificial.
 */
export default async function ColecoesLoading() {
  const mode = resolveLibraryMode({}, (await cookies()).get(LIBRARY_MODE_COOKIE)?.value);
  return (
    <AppShell title="Minhas coleções" icon={LibraryBig}>
      <div className={acervoStyles.root} aria-busy="true" aria-label="Carregando suas coleções">
        <div className={acervoStyles.hero}>
          <Skeleton className="h-[clamp(2.25rem,5.2vw,3.75rem)] w-80 max-w-full rounded-lg" />
          <Skeleton className="mt-4 h-5 w-96 max-w-full" />
        </div>
        <section className={modeStyles.region}>
          <div className={modeStyles.head}>
            <Skeleton className="h-6 w-44" />
            <Skeleton className="h-[2.5rem] w-[17rem] max-w-[45%] rounded-xl" />
          </div>
          <div className={modeStyles.panel}>
            {mode === "lista" ? (
              <ul className={modeStyles.list}>
                {Array.from({ length: 6 }).map((_, index) => (
                  <li key={index} className="flex items-center gap-5 px-4 py-3">
                    <Skeleton className="aspect-[26/33] w-12 flex-none rounded-md" />
                    <div className="flex-1">
                      <Skeleton className="h-4 w-1/2" />
                      <Skeleton className="mt-2 h-3 w-1/3" />
                    </div>
                    <Skeleton className="hidden h-1.5 w-56 rounded-full sm:block" />
                  </li>
                ))}
              </ul>
            ) : mode === "carrossel" ? (
              <div className={carouselStyles.carousel}>
                <div className={`${carouselStyles.stage} flex items-center justify-center`}>
                  <Skeleton className="aspect-[26/33] w-[var(--lib-card-w)] rounded-xl" />
                </div>
                <div className="mt-1 flex flex-col items-center">
                  <Skeleton className="h-6 w-56" />
                  <Skeleton className="mt-2 h-3 w-40" />
                  <Skeleton className="mt-4 h-1.5 w-72 rounded-full" />
                </div>
              </div>
            ) : (
              <ul className={styles.library}>
                {Array.from({ length: 8 }).map((_, index) => (
                  <li key={index}>
                    <Skeleton className="aspect-[26/33] w-full rounded-xl" />
                    <Skeleton className="mt-3 h-4 w-3/4" />
                    <Skeleton className="mt-2 h-3 w-1/2" />
                    <Skeleton className="mt-3 h-1.5 w-full rounded-full" />
                  </li>
                ))}
              </ul>
            )}
          </div>
        </section>
      </div>
    </AppShell>
  );
}
