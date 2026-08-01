"use client";

import { useActionState, useState, useTransition, type ChangeEvent, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, HelpCircle, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import type { CardSetSemCartasRow } from "@/lib/catalogo/queries";
import type { TcgdexAutoMatchResult, TcgdexSetCandidate } from "@/lib/catalogo/tcgdex-lookup";
import {
  buscarSetsTcgdexManualmente,
  iniciarImportacaoTcgdex,
  type IniciarImportacaoTcgdexActionState,
} from "@/app/catalogo/importar-cartas/tcgdex/actions";

const INITIAL_STATE: IniciarImportacaoTcgdexActionState = { error: null };

/**
 * Tela "Selecionar fonte TCGdex" + "Analisar" (Ciclo 2, ADR-024). Escolher a
 * Coleção já dispara a localização automática do Set (page.tsx recalcula ao
 * mudar `?cardSetId=`) — o administrador nunca vê nem digita o
 * external_set_id em nenhum dos três estados possíveis (localizado,
 * ambíguo, sem correspondência).
 */
export function ImportarTcgdexView({
  cardSets,
  selectedCardSet,
  matchResult,
}: {
  cardSets: CardSetSemCartasRow[];
  selectedCardSet: CardSetSemCartasRow | null;
  matchResult: TcgdexAutoMatchResult | null;
}) {
  const router = useRouter();

  function handleCardSetChange(event: ChangeEvent<HTMLSelectElement>) {
    const id = event.target.value;
    router.push(id ? `/catalogo/importar-cartas/tcgdex?cardSetId=${id}` : "/catalogo/importar-cartas/tcgdex");
  }

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <PageTitle>Importar via TCGdex</PageTitle>
          <PageDescription>Selecione a Coleção sem cartas para localizar e importar da TCGdex.</PageDescription>
        </PageHeading>
      </PageHeader>

      <Card>
        <CardContent className="space-y-4 pt-6">
          <div className="space-y-1.5">
            <label htmlFor="card-set-select" className="text-sm font-medium text-foreground">
              Coleção
            </label>
            <select
              id="card-set-select"
              value={selectedCardSet?.id ?? ""}
              onChange={handleCardSetChange}
              className="h-10 w-full rounded-md border border-input bg-surface px-3 text-sm shadow-subtle focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
            >
              <option value="">Selecione uma Coleção sem cartas...</option>
              {cardSets.map((cardSet) => (
                <option key={cardSet.id} value={cardSet.id}>
                  {cardSet.code} — {cardSet.name}
                </option>
              ))}
            </select>
            {cardSets.length === 0 && (
              <p className="text-sm text-muted-foreground">Nenhuma Coleção sem cartas no momento.</p>
            )}
          </div>

          {selectedCardSet && matchResult && (
            <MatchResultPanel cardSet={selectedCardSet} matchResult={matchResult} />
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function MatchResultPanel({
  cardSet,
  matchResult,
}: {
  cardSet: CardSetSemCartasRow;
  matchResult: TcgdexAutoMatchResult;
}) {
  if (matchResult.status === "MATCHED") {
    return (
      <StartImportForm cardSetId={cardSet.id} candidate={matchResult.set}>
        <div className="flex items-center gap-3 rounded-md border border-input bg-[#F7F5ED] p-3">
          <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-600" aria-hidden="true" />
          <div className="flex-1">
            <p className="text-sm font-medium text-foreground">Set localizado: {matchResult.set.name}</p>
            <p className="text-xs text-muted-foreground">{matchResult.set.cardCountTotal} cartas na TCGdex</p>
          </div>
        </div>
      </StartImportForm>
    );
  }

  if (matchResult.status === "AMBIGUOUS") {
    return (
      <div className="space-y-2">
        <p className="flex items-center gap-1.5 text-sm font-medium text-foreground">
          <HelpCircle className="h-4 w-4 text-amber-600" aria-hidden="true" />
          Mais de um Set encontrado — selecione o correto
        </p>
        {matchResult.candidates.map((candidate) => (
          <StartImportForm key={candidate.id} cardSetId={cardSet.id} candidate={candidate}>
            <CandidateSummary candidate={candidate} />
          </StartImportForm>
        ))}
      </div>
    );
  }

  return <ManualSearchPanel cardSetId={cardSet.id} />;
}

function CandidateSummary({ candidate }: { candidate: TcgdexSetCandidate }) {
  return (
    <div className="rounded-md border border-input p-3">
      <p className="text-sm font-medium text-foreground">{candidate.name}</p>
      <p className="text-xs text-muted-foreground">{candidate.cardCountTotal} cartas</p>
    </div>
  );
}

function StartImportForm({
  cardSetId,
  candidate,
  children,
}: {
  cardSetId: string;
  candidate: TcgdexSetCandidate;
  children: ReactNode;
}) {
  const [state, formAction, isPending] = useActionState(iniciarImportacaoTcgdex, INITIAL_STATE);

  return (
    <form action={formAction} className="space-y-2">
      <input type="hidden" name="card_set_id" value={cardSetId} />
      <input type="hidden" name="external_set_id" value={candidate.id} />
      {children}
      <Button type="submit" disabled={isPending}>
        {isPending ? "Analisando..." : "Analisar"}
      </Button>
      {state.error && <p className="text-sm text-destructive">{state.error}</p>}
    </form>
  );
}

/**
 * Busca manual — só aparece quando a localização automática não resolve
 * sozinha. Busca por nome (nunca por id técnico); os resultados usam o
 * mesmo StartImportForm da localização automática.
 */
function ManualSearchPanel({ cardSetId }: { cardSetId: string }) {
  const [query, setQuery] = useState("");
  const [candidates, setCandidates] = useState<TcgdexSetCandidate[]>([]);
  const [searched, setSearched] = useState(false);
  const [isPending, startTransition] = useTransition();

  function handleSearch() {
    if (!query.trim()) return;
    startTransition(async () => {
      const results = await buscarSetsTcgdexManualmente(query);
      setCandidates(results);
      setSearched(true);
    });
  }

  return (
    <div className="space-y-3">
      <p className="flex items-center gap-1.5 text-sm font-medium text-foreground">
        <Search className="h-4 w-4 text-muted-foreground" aria-hidden="true" />
        Nenhuma correspondência automática — busque o Set pelo nome
      </p>
      <div className="flex gap-2">
        <input
          type="text"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter") {
              event.preventDefault();
              handleSearch();
            }
          }}
          placeholder="Nome do Set na TCGdex..."
          className="h-10 flex-1 rounded-md border border-input bg-surface px-3 text-sm shadow-subtle focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
        />
        <Button type="button" variant="outline" onClick={handleSearch} disabled={isPending}>
          {isPending ? "Buscando..." : "Buscar"}
        </Button>
      </div>
      {searched && candidates.length === 0 && !isPending && (
        <p className="text-sm text-muted-foreground">Nenhum Set encontrado com esse nome.</p>
      )}
      <div className="space-y-2">
        {candidates.map((candidate) => (
          <StartImportForm key={candidate.id} cardSetId={cardSetId} candidate={candidate}>
            <CandidateSummary candidate={candidate} />
          </StartImportForm>
        ))}
      </div>
    </div>
  );
}
