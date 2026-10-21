import { MapPin } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Skeleton } from "@/components/ui/skeleton";
import acervoStyles from "@/components/colecoes/acervo/acervo.module.css";
import styles from "@/components/colecoes/locais/locais.module.css";

/**
 * Carregamento de Meus locais — mesma geometria da página real (título, painel
 * de números e grade de locais). Sem atraso artificial: aparece só enquanto as
 * leituras do servidor estão em andamento.
 */
export default function LocaisLoading() {
  return (
    <AppShell title="Meus locais" icon={MapPin}>
      <div className={acervoStyles.root} aria-busy="true" aria-label="Carregando seus locais">
        <div className={acervoStyles.hero}>
          <Skeleton className="h-[clamp(2.25rem,5.2vw,3.75rem)] w-64 max-w-full rounded-lg" />
          <Skeleton className="mt-4 h-5 w-[32rem] max-w-full" />
          <Skeleton className={`${acervoStyles.ledger} h-[6.75rem] w-full`} />
        </div>
        <Skeleton className="mt-8 h-6 w-40" />
        <ul className={styles.grid}>
          {Array.from({ length: 6 }).map((_, index) => (
            <li key={index}>
              <Skeleton className="h-[13.5rem] w-full rounded-2xl" />
            </li>
          ))}
        </ul>
      </div>
    </AppShell>
  );
}
