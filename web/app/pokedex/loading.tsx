import { AppShell } from "@/components/app-shell/app-shell";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { Skeleton } from "@/components/ui/skeleton";
import heroStyles from "@/components/pokedex/pokedex-national.module.css";
import gridStyles from "@/components/pokedex/species-grid.module.css";

/**
 * Carregamento da Pokédex Nacional — mesma geometria da página real (cabeçalho,
 * régua de gerações, grade de cards P3c), sem layout shift na troca.
 */
export default function PokedexLoading() {
  return (
    <AppShell title="Pokédex Nacional" icon={Pokeball}>
      <div className="mx-auto max-w-7xl" aria-busy="true" aria-label="Carregando a Pokédex">
        <div className={heroStyles.hero}>
          <div className={heroStyles.heroContent}>
            <Skeleton className="h-[clamp(2.25rem,5.2vw,3.75rem)] w-4/5 rounded-lg" />
            <Skeleton className="mt-4 h-5 w-3/4" />
            <Skeleton className={`${heroStyles.search} h-[3.25rem] w-full rounded-xl`} />
          </div>
        </div>
        <div className="space-y-6">
          <div className="flex gap-1 overflow-hidden pt-3">
            {Array.from({ length: 10 }).map((_, index) => (
              <Skeleton key={index} className="h-11 flex-1 shrink-0 rounded-md" />
            ))}
          </div>
          <Skeleton className="h-5 w-64" />
          <div>
            <Skeleton className="mb-5 h-14 w-56 rounded-lg" />
            <ul className={gridStyles.grid}>
              {Array.from({ length: 12 }).map((_, index) => (
                <li key={index} className="overflow-hidden rounded-[1.25rem] border border-border/70 bg-surface">
                  <Skeleton className="aspect-[1/0.9] w-full rounded-none" />
                  <div className="space-y-2 px-4 pb-4 pt-1">
                    <Skeleton className="h-4 w-24" />
                    <Skeleton className="h-5 w-32 rounded-full" />
                  </div>
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </AppShell>
  );
}
