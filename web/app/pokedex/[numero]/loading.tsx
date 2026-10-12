import { AppShell } from "@/components/app-shell/app-shell";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { Skeleton } from "@/components/ui/skeleton";

/**
 * Carregamento da página de detalhes (Pokédex P3b) — mesma geometria do palco
 * (barra superior, quadro quadrado da arte, nome, tipos e painel), sem cor de
 * tipo (ainda desconhecida): a troca para o conteúdo real não desloca nada.
 */
export default function PokedexSpeciesLoading() {
  return (
    <AppShell title="Pokédex" icon={Pokeball}>
    <div className="-m-6 flex min-h-[calc(100dvh-3.5rem)] flex-col items-center" aria-busy="true" aria-label="Carregando espécie">
      <div className="flex w-full items-center justify-between px-5 pt-4 lg:px-8 lg:pt-5">
        <Skeleton className="h-6 w-40 rounded-full" />
        <Skeleton className="h-5 w-28 rounded-full" />
      </div>
      <div className="mt-2 aspect-square w-[min(74vw,18.75rem)] sm:w-[min(52vw,21rem)] lg:w-[clamp(18rem,30vw,27.5rem)]">
        <Skeleton className="h-full w-full rounded-full opacity-60" />
      </div>
      <Skeleton className="mt-4 h-4 w-44 rounded-full" />
      <Skeleton className="mt-4 h-14 w-[min(80vw,26rem)] rounded-xl" />
      <Skeleton className="mt-3 h-5 w-36 rounded-full" />
      <div className="mt-5 flex gap-2.5">
        <Skeleton className="h-8 w-24 rounded-full" />
        <Skeleton className="h-8 w-24 rounded-full" />
      </div>
      <div className="mt-7 w-full max-w-xl space-y-2 px-6">
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-4/5" />
      </div>
    </div>
    </AppShell>
  );
}
