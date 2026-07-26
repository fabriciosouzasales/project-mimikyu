import Link from "next/link";
import { AppShell } from "@/components/app-shell/app-shell";
import { Panel, PanelContent, PanelHeader, PanelTitle, PanelDescription } from "@/components/catalogo/panel";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { cn } from "@/lib/utils";
import { getCardSetOptions, getCartasPorCardSet } from "@/lib/catalogo/queries";

/**
 * Cartas — navegação por Card Set (chips com `?set=CODE`), não uma lista
 * única das 927 cartas: `collector_order` é relativo a cada Card Set, então
 * misturar Sets na mesma tabela intercalaria numerações sem sentido (ver
 * comentário de `getCartasPorCardSet`). Sem estado no cliente — o chip ativo
 * deriva inteiramente do `searchParams`, mesmo princípio já usado no
 * submenu (seção ativa deriva da rota).
 */
export default async function CartasPage({
  searchParams,
}: {
  searchParams: Promise<{ set?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Cartas");
  if (denied) return denied;

  const { set } = await searchParams;
  const cardSets = await getCardSetOptions(supabase);
  const selectedCode = set && cardSets.some((cs) => cs.code === set) ? set : cardSets[0]?.code;
  const cartas = selectedCode ? await getCartasPorCardSet(supabase, selectedCode) : [];
  const selectedName = cardSets.find((cs) => cs.code === selectedCode)?.name;

  return (
    <AppShell title="Cartas">
      <div className="mx-auto max-w-6xl space-y-4">
        <h1 className="font-heading text-xl font-medium text-foreground">Cartas</h1>

        {cardSets.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {cardSets.map((cs) => (
              <Link
                key={cs.code}
                href={`/catalogo/cartas?set=${cs.code}`}
                className={cn(
                  "rounded-full border px-3 py-1 text-xs transition-colors",
                  cs.code === selectedCode
                    ? "border-primary/40 bg-primary/10 text-primary"
                    : "border-border text-muted-foreground hover:bg-surface-muted hover:text-foreground",
                )}
              >
                {cs.code}
              </Link>
            ))}
          </div>
        )}

        <Panel>
          <PanelHeader>
            <PanelTitle>{selectedName ?? "Cartas"}</PanelTitle>
            <PanelDescription>{cartas.length} carta{cartas.length === 1 ? "" : "s"} catalogada{cartas.length === 1 ? "" : "s"}</PanelDescription>
          </PanelHeader>
          <PanelContent>
            {cartas.length === 0 ? (
              <div className="flex flex-col items-center gap-1 py-10 text-center">
                <p className="text-sm text-foreground">Nenhuma carta catalogada neste Card Set</p>
              </div>
            ) : (
              <div className="max-h-[32rem] overflow-y-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border text-left text-[11px] font-normal uppercase tracking-wide text-muted-foreground">
                      <th className="py-1.5 pr-3 font-normal">Nº</th>
                      <th className="py-1.5 pr-3 font-normal">Carta</th>
                      <th className="py-1.5 pr-3 font-normal">Raridade</th>
                      <th className="py-1.5 font-normal">Categoria</th>
                    </tr>
                  </thead>
                  <tbody>
                    {cartas.map((carta) => (
                      <tr key={carta.id} className="border-b border-border/60 last:border-b-0">
                        <td className="py-2 pr-3 text-muted-foreground">
                          {carta.collectorNumber}
                          {carta.collectorTotal ? `/${carta.collectorTotal}` : ""}
                        </td>
                        <td className="py-2 pr-3 text-foreground">{carta.name}</td>
                        <td className="py-2 pr-3 text-muted-foreground">{carta.raridadeNome ?? "—"}</td>
                        <td className="py-2 text-muted-foreground">{carta.categoriaNome ?? "—"}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </PanelContent>
        </Panel>
      </div>
    </AppShell>
  );
}
