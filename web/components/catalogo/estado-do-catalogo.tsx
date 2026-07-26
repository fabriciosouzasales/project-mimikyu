import type { EstadoDoCatalogo as EstadoDoCatalogoData } from "@/lib/catalogo/queries";

/**
 * Faixa de KPIs — cada indicador em seu próprio card branco com borda
 * (referência enviada por Fabrício: grid de métricas do Supabase Database
 * Overview). Continua mais raso e discreto que a tabela de Card Sets
 * (rótulo pequeno + número, sem descrição/rodapé por card) para preservar
 * o ritmo visual — é contexto de relance, não o bloco dominante da tela.
 */
export function EstadoDoCatalogo({ estado }: { estado: EstadoDoCatalogoData }) {
  const coberturaPendente = estado.cardSetsCatalogados - estado.cardSetsComImagensCompletas;

  const stats = [
    { rotulo: "Card Sets", valor: estado.cardSetsCatalogados },
    { rotulo: "Cobertura de imagens", valor: `${estado.cardSetsComImagensCompletas}/${estado.cardSetsCatalogados}` },
    { rotulo: "Cartas catalogadas", valor: estado.cartasCatalogadas },
    {
      rotulo: "Pendências de importação",
      valor: estado.execucoesComPendencia,
      destaque: estado.execucoesComPendencia > 0,
    },
  ];

  return (
    <div className="space-y-2">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {stats.map((stat) => (
          <div key={stat.rotulo} className="rounded-lg border border-border bg-surface px-3.5 py-3">
            <p className="text-[11px] text-muted-foreground">{stat.rotulo}</p>
            <p className={`mt-1 text-xl leading-none ${stat.destaque ? "text-warning" : "text-foreground"}`}>
              {stat.valor}
            </p>
          </div>
        ))}
      </div>
      {coberturaPendente > 0 && (
        <p className="text-xs text-muted-foreground">
          {coberturaPendente} Card Set{coberturaPendente > 1 ? "s" : ""} com imagens pendentes
        </p>
      )}
    </div>
  );
}
