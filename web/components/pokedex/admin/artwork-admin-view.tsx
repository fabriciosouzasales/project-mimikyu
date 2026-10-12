import { ChevronLeft, ChevronRight, CircleCheck, Clock, TriangleAlert } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";
import { StatCard } from "@/components/catalogo/stat-card";
import { ArtworkAdminSearch } from "@/components/pokedex/admin/artwork-admin-search";
import { ArtworkAdminTable, type ArtworkAdminItem } from "@/components/pokedex/admin/artwork-admin-table";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { ARTWORK_ADMIN_PAGE_SIZE, type ArtworkAdminRow, type ArtworkCoverage } from "@/lib/pokedex/admin-artwork";
import {
  STATUS_LABEL,
  STATUS_PARAM_BY_STATUS,
  artworkErrorLabel,
  formatArtworkDate,
  formatBytes,
  isTransientArtworkError,
  rightsLabel,
  type ArtworkStatus,
} from "@/lib/pokedex/admin-artwork-format";
import { speciesArtworkUrl } from "@/lib/pokedex/artwork";
import { formatCount, formatDexNumber } from "@/lib/pokedex/format";
import { POKEDEX_QUERY_MAX_LENGTH } from "@/lib/pokedex/queries";
import { cn } from "@/lib/utils";

/**
 * Pokédex → Cadastro → Imagens (Pokédex P2 Lote E). Renderizada no
 * servidor; só a pesquisa e a tabela (detalhes/reprocessamento) são ilhas
 * cliente. Miniaturas usam o WebP de 320 px — o PNG original nunca é
 * carregado na listagem.
 */

function hrefFor(params: { query: string | null; status: ArtworkStatus | null; page?: number }) {
  const search = new URLSearchParams();
  if (params.query) search.set("q", params.query);
  if (params.status) search.set("status", STATUS_PARAM_BY_STATUS[params.status]);
  if (params.page && params.page > 0) search.set("pagina", String(params.page + 1));
  const text = search.toString();
  return text ? `/pokedex/imagens?${text}` : "/pokedex/imagens";
}

function toItem(row: ArtworkAdminRow): ArtworkAdminItem {
  return {
    number: row.national_dex_number,
    numberLabel: formatDexNumber(row.national_dex_number),
    name: row.species_name,
    status: row.artwork_status,
    statusLabel: STATUS_LABEL[row.artwork_status],
    attempts: row.attempt_count,
    lastAttempt: formatArtworkDate(row.last_attempt_at),
    importedAt: formatArtworkDate(row.imported_at),
    errorCode: row.last_error_code,
    errorLabel: artworkErrorLabel(row.last_error_code),
    errorMessage: row.last_error_message,
    errorTransient: isTransientArtworkError(row.last_error_code),
    sourcePokemonId: row.source_pokemon_id,
    originalPath: row.original_storage_path,
    displayPath: row.display_storage_path,
    displaySize: formatBytes(row.display_size_bytes),
    rights: rightsLabel(row.rights_status),
    thumbUrl: speciesArtworkUrl(row.display_storage_path),
  };
}

export function ArtworkAdminView({
  coverage,
  result,
  query,
  status,
  page,
}: {
  coverage: ArtworkCoverage | null;
  result: { rows: ArtworkAdminRow[]; total: number } | null;
  query: string | null;
  status: ArtworkStatus | null;
  page: number;
}) {
  const percent = coverage && coverage.total > 0 ? Math.floor((coverage.imported / coverage.total) * 1000) / 10 : 0;
  const totalPages = result ? Math.max(1, Math.ceil(result.total / ARTWORK_ADMIN_PAGE_SIZE)) : 1;
  const firstShown = result && result.total > 0 ? page * ARTWORK_ADMIN_PAGE_SIZE + 1 : 0;
  const lastShown = result ? Math.min(result.total, page * ARTWORK_ADMIN_PAGE_SIZE + result.rows.length) : 0;
  const filtered = Boolean(query || status);

  const chips: { status: ArtworkStatus | null; label: string; count: number | null }[] = [
    { status: null, label: "Todas", count: coverage?.total ?? null },
    { status: "IMPORTED", label: "Importadas", count: coverage?.imported ?? null },
    { status: "PENDING", label: "Pendentes", count: coverage?.pending ?? null },
    { status: "FAILED", label: "Com falha", count: coverage?.failed ?? null },
  ];

  return (
    <PageContainer width="wide">
      <PageHeader>
        <PageHeading>
          <PageTitle>Imagens das espécies</PageTitle>
          <PageDescription>
            Arte oficial da Pokédex Nacional — cobertura, diagnóstico e reprocessamento pontual.
          </PageDescription>
        </PageHeading>
      </PageHeader>

      {coverage ? (
        <div className="flex flex-wrap gap-3">
          <StatCard
            label="Com imagem"
            value={`${formatCount(coverage.imported)} / ${formatCount(coverage.total)}`}
            caption={`${percent.toLocaleString("pt-BR")}% da Pokédex Nacional`}
            icon={CircleCheck}
            href={hrefFor({ query: null, status: "IMPORTED" })}
          />
          <StatCard
            label="Pendentes"
            value={formatCount(coverage.pending)}
            caption={coverage.pending === 0 ? "Nenhuma espécie sem imagem" : "Ainda sem importação"}
            icon={Clock}
            href={hrefFor({ query: null, status: "PENDING" })}
          />
          <StatCard
            label="Com falha"
            value={formatCount(coverage.failed)}
            caption={coverage.failed === 0 ? "Nenhuma falha registrada" : "Precisam de atenção"}
            icon={TriangleAlert}
            tone={coverage.failed > 0 ? "danger" : "default"}
            href={hrefFor({ query: null, status: "FAILED" })}
          />
        </div>
      ) : null}

      {!coverage || !result ? (
        <Alert variant="destructive">
          Não foi possível carregar a situação das imagens agora. Recarregue a página em instantes.
        </Alert>
      ) : (
        <Card className="overflow-hidden">
          <div className="flex flex-col gap-3 border-b border-border p-3 lg:flex-row lg:items-center lg:justify-between">
            <nav aria-label="Filtrar por situação" className="-mx-1 overflow-x-auto px-1">
              <ul className="flex w-max gap-1.5">
                {chips.map((chip) => {
                  const active = chip.status === status;
                  return (
                    <li key={chip.label}>
                      <Link
                        href={hrefFor({ query, status: chip.status })}
                        scroll={false}
                        aria-current={active ? "page" : undefined}
                        className={cn(
                          "flex h-8 items-center gap-1.5 whitespace-nowrap rounded-full border px-3 text-xs transition-colors",
                          "focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-primary/20",
                          active
                            ? "border-primary/60 bg-primary/10 font-semibold text-foreground"
                            : "border-border text-foreground/80 hover:border-foreground/20 hover:text-foreground",
                        )}
                      >
                        {chip.label}
                        {chip.count !== null ? (
                          <span className="tabular-nums text-muted-foreground">{formatCount(chip.count)}</span>
                        ) : null}
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </nav>
            <div className="w-full lg:w-80">
              <ArtworkAdminSearch
                initialQuery={query}
                statusParam={status ? STATUS_PARAM_BY_STATUS[status] : null}
                maxLength={POKEDEX_QUERY_MAX_LENGTH}
              />
            </div>
          </div>

          {result.rows.length === 0 ? (
            <div className="space-y-3 pb-8">
              <EmptyState
                title={
                  status === "FAILED" && !query
                    ? "Nenhuma falha registrada"
                    : status === "PENDING" && !query
                      ? "Nenhuma espécie pendente"
                      : "Nenhuma espécie encontrada"
                }
                description={
                  filtered && query
                    ? `Nada corresponde a “${query}” neste filtro.`
                    : "Todas as espécies desta situação estão em ordem."
                }
              />
              {filtered ? (
                <div className="flex justify-center">
                  <Button asChild variant="outline" size="sm">
                    <Link href="/pokedex/imagens">Ver todas as espécies</Link>
                  </Button>
                </div>
              ) : null}
            </div>
          ) : (
            <ArtworkAdminTable items={result.rows.map(toItem)} />
          )}

          {result.total > 0 ? (
            <div className="flex items-center justify-between gap-3 border-t border-border px-3 py-2 text-xs text-muted-foreground">
              <span className="tabular-nums">
                {formatCount(firstShown)}–{formatCount(lastShown)} de{" "}
                <span className="font-medium text-foreground">{formatCount(result.total)}</span>
              </span>
              <div className="flex items-center gap-1.5">
                <PageLink href={page > 0 ? hrefFor({ query, status, page: page - 1 }) : null} label="Página anterior">
                  <ChevronLeft className="h-3.5 w-3.5" />
                </PageLink>
                <span className="min-w-[3rem] text-center tabular-nums">
                  {page + 1}/{totalPages}
                </span>
                <PageLink
                  href={page < totalPages - 1 ? hrefFor({ query, status, page: page + 1 }) : null}
                  label="Próxima página"
                >
                  <ChevronRight className="h-3.5 w-3.5" />
                </PageLink>
              </div>
            </div>
          ) : null}
        </Card>
      )}
    </PageContainer>
  );
}

function PageLink({ href, label, children }: { href: string | null; label: string; children: ReactNode }) {
  if (!href) {
    return (
      <Button type="button" variant="outline" size="icon-sm" disabled aria-label={label}>
        {children}
      </Button>
    );
  }
  return (
    <Button asChild variant="outline" size="icon-sm" aria-label={label}>
      <Link href={href} scroll={false}>
        {children}
      </Link>
    </Button>
  );
}
