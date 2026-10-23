import { BookOpen } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Skeleton } from "@/components/ui/skeleton";
import styles from "@/components/colecoes/fichario/binder.module.css";

/** Carregamento do Fichário Digital — título e o fichário aberto com bolsos em espera. */
export default function FicharioLoading() {
  return (
    <AppShell title="Fichário" icon={BookOpen}>
      <div className={styles.root} aria-busy="true" aria-label="Abrindo o fichário">
        <div className={styles.top}>
          <Skeleton className="h-5 w-36" />
        </div>
        <Skeleton className="mt-3 h-10 w-80 max-w-full rounded-lg" />
        <Skeleton className="mt-3 h-4 w-96 max-w-full" />
        <div className={styles.desk} style={{ "--spread-ratio": 1.6, "--per-view": 2 } as React.CSSProperties}>
          <span />
          <div className={styles.binder}>
            <div className={styles.spread} data-direction="none">
              {[0, 1].map((page) => (
                <ul key={page} className={styles.page} style={{ "--cols": 3 } as React.CSSProperties} aria-hidden="true">
                  {Array.from({ length: 9 }).map((_, index) => (
                    <li key={index} className={styles.pocket}>
                      <span className={styles.pocketSkeleton} />
                    </li>
                  ))}
                </ul>
              ))}
            </div>
          </div>
          <span />
        </div>
      </div>
    </AppShell>
  );
}
