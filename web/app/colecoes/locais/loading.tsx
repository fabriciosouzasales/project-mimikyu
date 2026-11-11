import { MapPin } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Skeleton } from "@/components/ui/skeleton";
import acervoStyles from "@/components/colecoes/acervo/acervo.module.css";
import colecoesStyles from "@/components/colecoes/colecoes/colecoes.module.css";
import regionStyles from "@/components/colecoes/colecoes/library-modes.module.css";
import styles from "@/components/colecoes/locais/locais.module.css";

/**
 * Carregamento de Meus locais — mesma geometria da página real (cabeçalho
 * editorial do módulo, região de trabalho, coluna de organização e tipos, busca e índice de locais). Sem atraso artificial: aparece só enquanto as
 * leituras do servidor estão em andamento.
 */
export default function LocaisLoading() {
  return (
    <AppShell title="Meus locais" icon={MapPin}>
      <div className={acervoStyles.root} aria-busy="true" aria-label="Carregando seus locais">
        <div className={`${acervoStyles.hero} ${colecoesStyles.libraryHero}`}>
          <Skeleton className="h-14 w-[34rem] max-w-full rounded-lg" />
          <Skeleton className="mt-3 h-5 w-[30rem] max-w-full" />
          <Skeleton className="mt-[1.125rem] h-9 w-32 rounded-md" />
        </div>
        <div className={`${regionStyles.region} ${styles.workspace}`}>
          <div className={styles.layout}>
            <div className={styles.side}>
              <Skeleton className="h-[11.5rem] w-full rounded-2xl" />
              <Skeleton className="h-[12rem] w-full rounded-xl" />
            </div>
            <div className={styles.mainCol}>
              <Skeleton className="h-11 w-full rounded-lg" />
              <ul className={`${styles.index} mt-9`}>
                {Array.from({ length: 8 }).map((_, index) => (
                  <li key={index} className="p-3">
                    <Skeleton className="h-11 w-full rounded-lg" />
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      </div>
    </AppShell>
  );
}
