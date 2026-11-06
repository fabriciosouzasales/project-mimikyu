import { ClipboardCheck } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Skeleton } from "@/components/ui/skeleton";
import styles from "@/components/reports/report.module.css";

/** Carregamento do Checklist — barra, título, painel de números e linhas. */
export default function ChecklistReportLoading() {
  return (
    <AppShell title="Relatórios" icon={ClipboardCheck}>
      <div className={styles.root} aria-busy="true" aria-label="Preparando o checklist">
        <div className={styles.topBar}>
          <Skeleton className="h-5 w-40" />
          <Skeleton className="h-11 w-56 rounded-full" />
        </div>
        <div className={styles.head}>
          <Skeleton className="h-3 w-32" />
          <Skeleton className="mt-3 h-10 w-80 max-w-full rounded-lg" />
          <Skeleton className="mt-3 h-4 w-64 max-w-full" />
        </div>
        <Skeleton className="mt-6 h-24 w-full rounded-2xl" />
        <div className="mt-6 grid gap-2">
          {Array.from({ length: 10 }).map((_, index) => (
            <Skeleton key={index} className="h-10 w-full rounded-lg" />
          ))}
        </div>
      </div>
    </AppShell>
  );
}
