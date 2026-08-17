import { Search } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Skeleton } from "@/components/ui/skeleton";

export default function PesquisaLoading() {
  return (
    <AppShell title="Pesquisa avançada" icon={Search}>
      <div className="mx-auto max-w-6xl space-y-4">
        <Skeleton className="h-16 w-full rounded-lg" />
        <Skeleton className="h-24 w-full rounded-lg" />
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6">
          {Array.from({ length: 12 }).map((_, index) => (
            <Skeleton key={index} className="aspect-[5/7] w-full rounded-lg" />
          ))}
        </div>
      </div>
    </AppShell>
  );
}
