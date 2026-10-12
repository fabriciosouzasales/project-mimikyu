import { AppShell } from "@/components/app-shell/app-shell";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { Skeleton } from "@/components/ui/skeleton";

/** Carregamento da Pokédex Nacional — mesma geometria da página real, sem layout shift na troca. */
export default function PokedexLoading() {
  return (
    <AppShell title="Pokédex Nacional" icon={Pokeball}>
      <div className="mx-auto max-w-7xl space-y-6" aria-busy="true" aria-label="Carregando a Pokédex">
        <Skeleton className="h-[132px] w-full rounded-xl" />
        <div className="flex gap-2 overflow-hidden">
          {Array.from({ length: 8 }).map((_, index) => (
            <Skeleton key={index} className="h-9 w-28 shrink-0 rounded-full" />
          ))}
        </div>
        <Skeleton className="h-5 w-64" />
        <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 2xl:grid-cols-7">
          {Array.from({ length: 14 }).map((_, index) => (
            <li key={index} className="overflow-hidden rounded-xl border border-border/80 bg-surface">
              <Skeleton className="aspect-square w-full rounded-none" />
              <div className="space-y-1.5 px-3 pb-3 pt-2.5">
                <Skeleton className="h-3 w-12" />
                <Skeleton className="h-4 w-24" />
              </div>
            </li>
          ))}
        </ul>
      </div>
    </AppShell>
  );
}
