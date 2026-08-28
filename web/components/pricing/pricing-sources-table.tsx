"use client";

import { ArrowUpRight, Pencil } from "lucide-react";
import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { atualizarFontePreco, type AtualizarFontePrecoState } from "@/app/pricing/fontes/actions";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/empty-state";
import { InlineFeedback } from "@/components/ui/feedback";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import type { PricingSource } from "@/lib/pricing/queries";
import { cn } from "@/lib/utils";

const initialState: AtualizarFontePrecoState = { error: null };

// Rótulos de humanização — só cobrem os domínios já declarados nos CHECKs de
// `pricing_source` (migration 3000: source_type IN ('API','DATASET','MANUAL'),
// default_market_scope IN ('INTERNATIONAL','BRAZIL')). Valor bruto como
// fallback, nunca um rótulo inventado.
const SOURCE_TYPE_LABEL: Record<string, string> = {
  API: "API",
  DATASET: "Dataset",
  MANUAL: "Manual",
};

const MARKET_SCOPE_LABEL: Record<string, string> = {
  INTERNATIONAL: "Internacional",
  BRAZIL: "Brasil",
};

/**
 * Descrição curta por fonte, escrita manualmente (não inventada a partir dos
 * dados) — só cobre fontes já conhecidas. Uma fonte futura sem entrada aqui
 * simplesmente não exibe a linha de descrição, em vez de um texto genérico.
 */
const SOURCE_DESCRIPTION: Record<string, string> = {
  JUSTTCG:
    "A API da JustTCG fornece dados de preços em tempo real para jogos de cartas colecionáveis, incluindo Magic: The Gathering, Pokémon, Yu-Gi-Oh!, Disney Lorcana, One Piece TCG, Digimon e Union Arena. Nossa API foi projetada para ser simples, rápida e confiável.",
};

/**
 * Cadastro de Fontes de Preço (Bloco 4 do Pricing Admin, migration 3942) —
 * sem criação/exclusão nesta V1 (hoje só JUSTTCG, cadastrada via migration
 * 3910; novas fontes continuam sendo um evento raro de migration, não um
 * fluxo de UI): só edição de metadados via Dialog, mesmo esqueleto de
 * `PoliticaSincronizacaoPanel`. `code`/`source_type`/`default_market_scope`/
 * `base_currency` ficam de fora do formulário — identidade estrutural da
 * fonte, imutável por este caminho (mesma disciplina de `card_set.code`
 * antes de ganhar Cards).
 *
 * Refinamento visual (2026-08-24, pedido de Fabrício, três rodadas): a
 * listagem principal deixa de ser uma tabela e passa a ser um ou mais
 * painéis horizontais de configuração por fonte (3ª rodada — abandona a
 * ideia de grid 2x2 da 2ª rodada; com uma fonte real hoje, a composição
 * precisa funcionar bem sozinha, não "parecer preparada" para uma grade
 * futura). Largura contida em `max-w-[900px]` — presença visual deliberada
 * sem ocupar o workspace inteiro. Tela continua puramente cadastral — nenhum
 * dado operacional (última sincronização, erros, cobertura) migrou para cá;
 * isso é responsabilidade de `Saúde das Fontes` (`saude-fontes-list.tsx`).
 * O Dialog de edição (`EditPricingSourceDialog`/`EditPricingSourceForm`
 * abaixo) está aprovado desde a 2ª rodada e não muda nesta 3ª.
 *
 * Padronização de CTAs primários do Pricing (2026-08-28, pedido explícito de
 * Fabrício): "Editar configuração" vira `default` (dourado, mesmo
 * `ctaStyles.cta` do Catálogo Editorial) em vez de `outline`. Semanticamente
 * é uma ação de edição, não de criação — mas é a única ação da tela (nenhum
 * fluxo de criação de fonte existe nesta V1, ver comentário acima), logo
 * funciona como o CTA primário da página, no mesmo papel que "+ Nova
 * Raridade" ocupa em `raridades-table.tsx`. Confirmado explicitamente com
 * Fabrício antes de reverter a exclusão geral de "botões de edição inline"
 * só para este caso específico.
 */
export function PricingSourcesTable({ sources }: { sources: PricingSource[] }) {
  const router = useRouter();
  const state = useAdminListState();
  const editingSource = sources.find((s) => s.id === state.editingId) ?? null;

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  return (
    <div className="mx-auto max-w-5xl space-y-4">
      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      {sources.length === 0 ? (
        <Card>
          <CardContent className="p-0">
            <EmptyState
              title="Nenhuma fonte de preço cadastrada"
              description="Fontes novas são cadastradas via migration — não existe criação por aqui nesta versão."
              className="py-10"
            />
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Fontes configuradas</p>
          <div className="space-y-4">
            {sources.map((source) => (
              <PricingSourceCard
                key={source.id}
                source={source}
                highlighted={state.highlightId === source.id}
                onEdit={() => state.startEdit(source.id)}
              />
            ))}
          </div>
        </div>
      )}

      <EditPricingSourceDialog
        open={editingSource !== null}
        source={editingSource}
        onSaved={handleSaved}
        onCancel={state.cancelEdit}
      />
    </div>
  );
}

/**
 * Referências utilitárias do card — só os campos com URL cadastrada, na
 * ordem "Site · Documentação · API · Termos" pedida por Fabrício. Nenhuma
 * URL fica visível por extenso na tela principal; o `href` completo só
 * existe no atributo do link.
 */
function buildSourceLinks(source: PricingSource): { label: string; href: string }[] {
  return [
    { label: "Site", href: source.baseUrl },
    { label: "Documentação", href: source.documentationUrl },
    { label: "API", href: source.apiBaseUrl },
    { label: "Termos", href: source.termsUrl },
  ].filter((link): link is { label: string; href: string } => Boolean(link.href));
}

/**
 * Iniciais para o selo de identidade — não é logo oficial (nenhum asset
 * aprovado existe para JustTCG nem para fontes futuras), só um monograma
 * neutro derivado do próprio nome cadastrado. Preferência por letras
 * maiúsculas internas (ex.: "JustTCG" → "JT", a partir de J/T/C/G) porque é
 * assim que fontes normalmente demarcam a própria marca dentro do nome;
 * cai para as duas primeiras letras quando o nome não tem esse padrão.
 */
function sourceInitials(name: string): string {
  const capitals = name.match(/[A-ZÀ-Ý]/g);
  if (capitals && capitals.length >= 2) return capitals.slice(0, 2).join("");
  return name.slice(0, 2).toUpperCase();
}

/**
 * Painel de fonte, v4 (2026-08-24, reorganização a partir de mockup de
 * Fabrício) — abandona a divisão em duas zonas lado a lado da v3 (identidade
 * à esquerda / configuração à direita com `border-l`). Tudo agora é uma
 * única coluna de conteúdo ao lado do selo de monograma: nome+status no
 * topo (mesma linha, alinhados às duas bordas do painel), descrição logo
 * abaixo, Mercado/Moeda/Integração em seguida (mesma indentação do nome,
 * não uma coluna à parte), e por fim links utilitários + `Editar
 * configuração` na mesma linha (links à esquerda, botão na borda direita —
 * mesmo alinhamento do status acima, por estarem na mesma coluna flex).
 * Coluna única também em telas estreitas — não há mais duas zonas para
 * empilhar.
 */
function PricingSourceCard({
  source,
  highlighted,
  onEdit,
}: {
  source: PricingSource;
  highlighted: boolean;
  onEdit: () => void;
}) {
  const description = SOURCE_DESCRIPTION[source.code];
  const links = buildSourceLinks(source);

  return (
    <Card className={cn(highlighted && "bg-primary/5")}>
      <CardContent className="flex gap-4 p-6 sm:p-8">
        <span
          className="flex h-12 w-12 shrink-0 items-center justify-center rounded-lg bg-primary/15 text-base font-bold tracking-wide text-primary-ink"
          aria-hidden="true"
        >
          {sourceInitials(source.name)}
        </span>

        <div className="min-w-0 flex-1 space-y-5">
          <div className="space-y-1">
            <div className="flex items-center justify-between gap-4">
              <h3 className="truncate text-xl font-semibold text-foreground">{source.name}</h3>
              <SourceStatusDot isActive={source.isActive} />
            </div>
            {description && <p className="text-sm text-muted-foreground">{description}</p>}
          </div>

          <div className="flex flex-wrap gap-x-10 gap-y-3">
            <SourceMetaColumn
              label="Mercado"
              value={MARKET_SCOPE_LABEL[source.defaultMarketScope] ?? source.defaultMarketScope}
            />
            <SourceMetaColumn label="Moeda" value={source.baseCurrency} />
            <SourceMetaColumn
              label="Integração"
              value={SOURCE_TYPE_LABEL[source.sourceType] ?? source.sourceType}
            />
          </div>

          <div className="flex flex-wrap items-center justify-between gap-4 border-t border-border/50 pt-5">
            <div className="flex flex-wrap items-center gap-x-6 gap-y-2 text-xs">
              {links.map((link) => (
                <a
                  key={link.label}
                  href={link.href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 text-muted-foreground transition-colors hover:text-foreground"
                >
                  <ArrowUpRight className="h-3 w-3" aria-hidden="true" />
                  {link.label}
                </a>
              ))}
            </div>
            <Button type="button" size="sm" onClick={onEdit}>
              <Pencil className="h-3.5 w-3.5" />
              Editar configuração
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

/** Status como ponto + texto (não badge/pill) — pedido explícito de Fabrício para reduzir a contagem de badges no card. */
function SourceStatusDot({ isActive }: { isActive: boolean }) {
  return (
    <span className="inline-flex items-center gap-2 text-sm font-medium">
      <span className={cn("h-2 w-2 rounded-full", isActive ? "bg-success" : "bg-warning")} aria-hidden="true" />
      <span className={isActive ? "text-success" : "text-warning"}>{isActive ? "Ativa" : "Inativa"}</span>
    </span>
  );
}

/** Coluna leve label secundário (acima) + valor forte (abaixo) — sem tabela, sem divisória vertical entre colunas. */
function SourceMetaColumn({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-[84px]">
      <p className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-1 text-base font-semibold text-foreground">{value}</p>
    </div>
  );
}

function EditPricingSourceDialog({
  open,
  source,
  onSaved,
  onCancel,
}: {
  open: boolean;
  source: PricingSource | null;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        size="xl"
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Editar Fonte de Preço</DialogTitle>
          <DialogDescription>
            {source
              ? `${source.code} · ${SOURCE_TYPE_LABEL[source.sourceType] ?? source.sourceType} · ${source.baseCurrency}`
              : "Identidade estrutural imutável."}
          </DialogDescription>
        </DialogHeader>

        {open && source && (
          <EditPricingSourceForm key={source.id} source={source} onSaved={onSaved} onCancel={onCancel} onPendingChange={setPending} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function EditPricingSourceForm({
  source,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  source: PricingSource;
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(atualizarFontePreco, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Fonte de preço atualizada com sucesso.", source.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="pricingSourceId" value={source.id} />
      <DialogBody className="space-y-6">
        <div className="space-y-4">
          <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Identificação</p>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor={`edit-source-name-${source.id}`}>Nome</Label>
              <Input id={`edit-source-name-${source.id}`} name="name" defaultValue={source.name} required maxLength={100} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor={`edit-source-attribution-${source.id}`}>Texto de atribuição</Label>
              <Input
                id={`edit-source-attribution-${source.id}`}
                name="attribution_text"
                defaultValue={source.attributionText ?? ""}
                maxLength={300}
              />
            </div>
          </div>
        </div>

        <div className="space-y-4 border-t border-border/60 pt-5">
          <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Endpoints e referências</p>
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1.5">
              <Label htmlFor={`edit-source-base-url-${source.id}`}>URL do site</Label>
              <Input id={`edit-source-base-url-${source.id}`} name="base_url" type="url" defaultValue={source.baseUrl ?? ""} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor={`edit-source-api-url-${source.id}`}>URL da API</Label>
              <Input id={`edit-source-api-url-${source.id}`} name="api_base_url" type="url" defaultValue={source.apiBaseUrl ?? ""} />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor={`edit-source-docs-url-${source.id}`}>URL da documentação</Label>
              <Input
                id={`edit-source-docs-url-${source.id}`}
                name="documentation_url"
                type="url"
                defaultValue={source.documentationUrl ?? ""}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor={`edit-source-terms-url-${source.id}`}>URL dos termos de uso</Label>
              <Input id={`edit-source-terms-url-${source.id}`} name="terms_url" type="url" defaultValue={source.termsUrl ?? ""} />
            </div>
          </div>
        </div>

        <div className="space-y-4 border-t border-border/60 pt-5">
          <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Configuração</p>
          <div className="grid grid-cols-3 gap-4">
            <div className="space-y-1.5">
              <Label htmlFor={`edit-source-active-${source.id}`}>Status</Label>
              <Select id={`edit-source-active-${source.id}`} name="is_active" defaultValue={source.isActive ? "on" : ""}>
                <option value="on">Ativa</option>
                <option value="">Inativa</option>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor={`edit-source-api-${source.id}`}>Suporta API</Label>
              <Select id={`edit-source-api-${source.id}`} name="supports_api" defaultValue={source.supportsApi ? "on" : ""}>
                <option value="on">Sim</option>
                <option value="">Não</option>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor={`edit-source-agreement-${source.id}`}>Exige acordo comercial</Label>
              <Select
                id={`edit-source-agreement-${source.id}`}
                name="requires_commercial_agreement"
                defaultValue={source.requiresCommercialAgreement ? "on" : ""}
              >
                <option value="on">Sim</option>
                <option value="">Não</option>
              </Select>
            </div>
          </div>
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>
      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Salvando…" : "Salvar"}
        </Button>
      </DialogFooter>
    </form>
  );
}
