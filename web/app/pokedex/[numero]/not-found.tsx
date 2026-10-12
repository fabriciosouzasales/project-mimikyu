import Link from "next/link";
import { AppShell } from "@/components/app-shell/app-shell";
import { Pokeball } from "@/components/icons/pokeball-icon";

/** Número fora da Pokédex Nacional (ou inválido) — orienta de volta, sem tela quebrada. */
export default function PokedexSpeciesNotFound() {
  return (
    <AppShell title="Pokédex" icon={Pokeball}>
      <div className="mx-auto flex max-w-md flex-col items-center gap-3 px-6 py-20 text-center">
        <Pokeball className="h-12 w-12 text-muted-foreground/50" strokeWidth={1.25} aria-hidden="true" />
        <h1 className="font-heading text-xl font-semibold text-foreground">Esta espécie não está na Pokédex</h1>
        <p className="text-sm text-muted-foreground">
          O número informado não corresponde a nenhuma espécie da Pokédex Nacional. Use a pesquisa para encontrar o Pokémon pelo nome ou pelo número.
        </p>
        <Link href="/pokedex" className="mt-2 text-sm font-medium text-primary-ink underline-offset-2 hover:underline">
          Ir para a Pokédex Nacional
        </Link>
      </div>
    </AppShell>
  );
}
