import { Library } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Skeleton } from "@/components/ui/skeleton";
import styles from "@/components/colecoes/acervo/acervo.module.css";
import regionStyles from "@/components/colecoes/colecoes/library-modes.module.css";

/**
 * Carregamento de Meu acervo — mesma geometria da página real (título, números,
 * barra de busca e grade de cartas 8:11). Sem atraso artificial: aparece só
 * enquanto as leituras do servidor estão em andamento.
 */
export default function AcervoLoading() {
  return (
    <AppShell title="Meu acervo" icon={Library}>
      <div className={styles.root} aria-busy="true" aria-label="Carregando seu acervo">
        <div className={styles.hero}>
          <Skeleton className="h-[clamp(2.25rem,5.2vw,3.75rem)] w-72 max-w-full rounded-lg" />
          <Skeleton className="mt-4 h-5 w-96 max-w-full" />
          <Skeleton className={`${styles.ledger} h-[6.75rem] w-full`} />
        </div>
        <div className={`${regionStyles.region} ${styles.workspace}`}>
          <div className={styles.toolbar}>
            <Skeleton className="h-9 w-72 max-w-full" />
          </div>
          <ul className={styles.grid}>
            {Array.from({ length: 12 }).map((_, index) => (
              <li key={index}>
                <Skeleton className={styles.skeletonArt} />
                <Skeleton className="mt-3 h-3.5 w-3/4" />
                <Skeleton className="mt-2 h-3 w-2/5" />
              </li>
            ))}
          </ul>
        </div>
      </div>
    </AppShell>
  );
}
