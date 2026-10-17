import { LibraryBig } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Skeleton } from "@/components/ui/skeleton";
import acervoStyles from "@/components/colecoes/acervo/acervo.module.css";
import styles from "@/components/colecoes/colecoes/colecoes.module.css";

/** Carregamento de uma coleção — título, painel de progresso, filtro e grade 8:11. */
export default function ColecaoLoading() {
  return (
    <AppShell title="Minhas coleções" icon={LibraryBig}>
      <div className={acervoStyles.root} aria-busy="true" aria-label="Carregando a coleção">
        <div className={acervoStyles.hero}>
          <Skeleton className="h-5 w-36" />
          <div className={`${styles.collectionHero} mt-3`}>
            <div>
              <Skeleton className="h-[clamp(2.25rem,5.2vw,3.75rem)] w-80 max-w-full rounded-lg" />
              <Skeleton className="mt-4 h-4 w-72 max-w-full" />
            </div>
            <Skeleton className="h-[8.5rem] w-full rounded-2xl" />
          </div>
        </div>
        <div className={styles.bar}>
          <Skeleton className="h-11 w-72 max-w-full rounded-xl" />
        </div>
        <ul className={acervoStyles.grid}>
          {Array.from({ length: 12 }).map((_, index) => (
            <li key={index}>
              <Skeleton className={acervoStyles.skeletonArt} />
              <Skeleton className="mt-3 h-3.5 w-3/4" />
              <Skeleton className="mt-2 h-3 w-2/5" />
            </li>
          ))}
        </ul>
      </div>
    </AppShell>
  );
}
