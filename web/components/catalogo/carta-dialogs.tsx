"use client";

import { AlertTriangle, Star } from "lucide-react";
import { useActionState, useEffect, useState } from "react";
import { createCard, deactivateCard, updateCard } from "@/app/catalogo/cartas/actions";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogBody,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { InlineFeedback } from "@/components/ui/feedback";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import type { CardActionState } from "@/app/catalogo/cartas/actions";
import { buildVariantSummaryModel } from "@/lib/catalogo/carta-variant-summary";
import type { CartaCompletaRow, CategoriaOption, RaridadeRow } from "@/lib/catalogo/queries";

const initialState: CardActionState = { error: null };

/**
 * Dialog de cadastro de Card — novo em 2026-08-07 (fecha o subciclo Card do
 * ADR-023 junto com desativação/reativação, pedido de Fabrício: "Vamos
 * avançar com o Resto do subciclo Card — criação e desativação/reativação
 * administrativa"). Mesmo padrão estrutural de `EditCardDialog`
 * (`key={cardSetId}` isola o estado do formulário por Card Set, já que o
 * botão "Nova Carta" fica fixo na tela mesmo trocando de Coleção), mas com
 * um campo a mais: `collector_number`, que aqui define a identidade da Card
 * sendo criada (não um campo protegido como em `EditCardDialog` — essa
 * proteção só existe depois que a Card já existe).
 *
 * `defaultCollectorTotal`/`suggestedCollectorOrder` — ajuste #3 da revisão
 * de Fabrício ("collector_total deve vir pré-preenchido a partir do Card
 * Set; collector_order = max + 1 é apenas sugestão de UX, mantendo
 * validação transacional no banco"): ambos chegam prontos do componente pai
 * (`CartasGallery`, que já tem `selectedCardSet.totalSetSize` e o maior
 * `collectorOrder` entre as cartas já carregadas — ativas e inativas, ver
 * `getCartasCompletas`) e só preenchem o valor inicial do campo — o usuário
 * pode sempre sobrescrever, e a validação real (duplicidade, consistência de
 * Game) continua inteiramente em `admin_create_card()` (Query 2115).
 */
export function NewCardDialog({
  open,
  cardSetId,
  cardSetLabel,
  defaultCollectorTotal,
  suggestedCollectorOrder,
  raridades,
  categorias,
  onSaved,
  onCancel,
}: {
  open: boolean;
  cardSetId: string;
  /** "{Coleção} ({Código})" — mesmo formato de `EditCardDialog`. */
  cardSetLabel: string;
  defaultCollectorTotal: number | null;
  suggestedCollectorOrder: number;
  raridades: RaridadeRow[];
  categorias: CategoriaOption[];
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        size="lg"
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Nova Carta</DialogTitle>
          <DialogDescription>{cardSetLabel}</DialogDescription>
        </DialogHeader>

        {open && (
          <NewCardForm
            key={cardSetId}
            cardSetId={cardSetId}
            defaultCollectorTotal={defaultCollectorTotal}
            suggestedCollectorOrder={suggestedCollectorOrder}
            raridades={raridades}
            categorias={categorias}
            onSaved={onSaved}
            onCancel={onCancel}
            onPendingChange={setPending}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function NewCardForm({
  cardSetId,
  defaultCollectorTotal,
  suggestedCollectorOrder,
  raridades,
  categorias,
  onSaved,
  onCancel,
  onPendingChange,
}: {
  cardSetId: string;
  defaultCollectorTotal: number | null;
  suggestedCollectorOrder: number;
  raridades: RaridadeRow[];
  categorias: CategoriaOption[];
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
}) {
  const [state, formAction, pending] = useActionState(createCard, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Card cadastrada com sucesso.", state.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="card_set_id" value={cardSetId} />
      <DialogBody className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-card-number">Número</Label>
            <Input id="new-card-number" name="collector_number" required maxLength={20} placeholder="Ex.: 001" />
          </div>
          <div className="space-y-1">
            <Label htmlFor="new-card-total">Total (opcional)</Label>
            <Input
              id="new-card-total"
              name="collector_total"
              type="number"
              min={1}
              step={1}
              defaultValue={defaultCollectorTotal ?? ""}
            />
          </div>
        </div>

        <div className="space-y-1">
          <Label htmlFor="new-card-name">Nome</Label>
          <Input id="new-card-name" name="name" required maxLength={150} />
        </div>

        <div className="space-y-1">
          <Label htmlFor="new-card-order">Ordem editorial</Label>
          <Input
            id="new-card-order"
            name="collector_order"
            type="number"
            min={1}
            step={1}
            defaultValue={suggestedCollectorOrder}
            required
          />
        </div>
        <p className="-mt-2 text-xs text-muted-foreground">
          Ordem editorial: posição da carta no checklist oficial do Card Set — define a ordem de exibição na galeria.
          Sugestão automática (última ordem + 1); ajuste se necessário.
        </p>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor="new-card-rarity">Raridade</Label>
            <Select id="new-card-rarity" name="rarity_id" required defaultValue="">
              <option value="" disabled>
                Selecione…
              </option>
              {raridades.map((raridade) => (
                <option key={raridade.id} value={raridade.id}>
                  {raridade.name}
                </option>
              ))}
            </Select>
          </div>
          <div className="space-y-1">
            <Label htmlFor="new-card-category">Categoria</Label>
            <Select id="new-card-category" name="category_id" required defaultValue="">
              <option value="" disabled>
                Selecione…
              </option>
              {categorias.map((categoria) => (
                <option key={categoria.id} value={categoria.id}>
                  {categoria.name}
                </option>
              ))}
            </Select>
          </div>
        </div>

        {state.error && <InlineFeedback tone="error">{state.error}</InlineFeedback>}
      </DialogBody>

      <DialogFooter>
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" size="sm" disabled={pending}>
          {pending ? "Cadastrando…" : "Cadastrar"}
        </Button>
      </DialogFooter>
    </form>
  );
}

/**
 * Dialog de edição de Card — novo em 2026-08-07 (pedido de Fabrício:
 * "Encontrei duas cartas cadastradas com a raridade errada... vamos incluir
 * um botão de ação rápida abaixo de cada carta, no canto inferior direito
 * para abrir a tela de alteração do cadastro, possibilitando editar todas as
 * informações possíveis referente aquela carta específica, incluindo a sua
 * raridade" — mesmo padrão explícito de `EditCardSetDialog`: "Assim como
 * fizemos para Coleções"). Cópia fiel da estrutura de `EditCardSetDialog`:
 * campos imutáveis (Card Set + Número) saem do corpo do formulário e viram a
 * `DialogDescription` do cabeçalho, `key={carta.id}` isola o estado do
 * formulário por entidade.
 *
 * Campos editáveis: Nome, Total (opcional — nem toda Card tem denominador,
 * ver comentário de `collector_total` em `140_create_card_table.sql`), Ordem
 * editorial, Raridade e Categoria. `card_set_id` **e `collector_number`**
 * ficam de fora por decisão já registrada em ADR-023 ("Campos
 * estruturalmente protegidos nunca são alteráveis por atualização" —
 * mudar identidade não é o mesmo que corrigir conteúdo, mesmo sob decisão
 * administrativa explícita) — por isso o Número aparece só como texto no
 * cabeçalho, ao lado da Coleção, nunca como campo do formulário. `is_active`
 * (soft delete) também fica de fora — não pedido, e exclusão de Card é uma
 * ação distinta de edição.
 */
export function EditCardDialog({
  open,
  carta,
  cardSetLabel,
  raridades,
  categorias,
  onSaved,
  onCancel,
  onManageDefaultVariant,
  defaultVariantNotice,
  onManageVariants,
}: {
  open: boolean;
  carta: CartaCompletaRow | null;
  /** "{Coleção} ({Código})" — resolvido pelo componente pai, que já tem o Card Set selecionado em mãos; evita esta tela precisar buscar o Card Set de novo. */
  cardSetLabel: string;
  raridades: RaridadeRow[];
  categorias: CategoriaOption[];
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  /** P1 (2026-10-11): abre o diálogo de variante padrão por cima deste (o formulário não é perdido). */
  onManageDefaultVariant?: () => void;
  /** P1: confirmação exibida na seção "Variante padrão" depois de uma troca feita a partir daqui. */
  defaultVariantNotice?: string | null;
  /** P2a (2026-10-11): abre o diálogo "Variações" (lista + adicionar) por cima deste. */
  onManageVariants?: () => void;
}) {
  const [pending, setPending] = useState(false);

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        size="lg"
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Editar Card</DialogTitle>
          {/* Fallback estático só aparece durante o frame de saída do
              Dialog, quando `carta` já voltou a `null` mas o Radix ainda
              está animando o fechamento — mesmo cuidado de `EditCardSetDialog`.
              Número junto da Coleção (não um campo do formulário) — ver
              comentário acima sobre `collector_number` ser estruturalmente
              protegido (ADR-023). */}
          <DialogDescription>
            {carta ? `${cardSetLabel} · Nº ${carta.collectorNumber}` : "Coleção e número são imutáveis após o cadastro."}
          </DialogDescription>
        </DialogHeader>

        {open && carta && (
          <EditCardForm
            key={carta.id}
            carta={carta}
            raridades={raridades}
            categorias={categorias}
            onSaved={onSaved}
            onCancel={onCancel}
            onPendingChange={setPending}
            onManageDefaultVariant={onManageDefaultVariant}
            defaultVariantNotice={defaultVariantNotice ?? null}
            onManageVariants={onManageVariants}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

/**
 * P1 (2026-10-11) — seção somente leitura "Variante padrão" do formulário de
 * edição. A troca acontece no diálogo dedicado (`CartaDefaultVariantDialog`),
 * gravada na hora pela própria RPC — independente do "Salvar" deste
 * formulário, por isso o botão é `type="button"` e o texto deixa isso claro.
 */
function DefaultVariantSection({
  carta,
  onManage,
  notice,
}: {
  carta: CartaCompletaRow;
  onManage?: () => void;
  notice: string | null;
}) {
  const model = buildVariantSummaryModel(carta.variantView, carta.name);
  const titleId = `edit-card-default-variant-${carta.id}`;

  let body: React.ReactNode;
  if (model.kind === "HIDDEN") {
    body = <p className="text-sm text-muted-foreground">Esta carta não tem variações cadastradas.</p>;
  } else if (model.kind === "UNAVAILABLE") {
    body = <p className="text-sm text-muted-foreground">Detalhes das variações indisponíveis.</p>;
  } else if (model.defaultLine) {
    body = (
      <p className="flex min-w-0 items-center gap-1.5 text-sm text-foreground">
        <Star className="h-3.5 w-3.5 shrink-0 fill-current text-primary" aria-hidden="true" />
        <span className="truncate">{model.defaultLine.label}</span>
      </p>
    );
  } else {
    body = (
      <p className="flex items-center gap-1.5 text-sm text-warning">
        <AlertTriangle className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
        Nenhuma definida
      </p>
    );
  }

  return (
    <section aria-labelledby={titleId} className="space-y-1.5 rounded-md border border-border px-3 py-2.5">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0 space-y-0.5">
          <p id={titleId} className="text-xs font-medium text-muted-foreground">
            Variante padrão
          </p>
          {body}
        </div>
        {model.kind === "LIST" && onManage ? (
          <Button type="button" variant="outline" size="sm" className="shrink-0" onClick={onManage}>
            {model.defaultLine ? "Alterar" : "Escolher"}
          </Button>
        ) : null}
      </div>
      {notice ? (
        <p role="status" className="text-xs text-success">
          {notice}
        </p>
      ) : null}
    </section>
  );
}

/**
 * P2a (2026-10-11) — seção "Variações" do formulário de edição: quantidade
 * cadastrada + atalho para o diálogo de variações (lista e cadastro
 * individual). Também é o caminho de teclado/sem variações, já que o
 * indicador da galeria não aparece em cartas sem variação.
 */
function VariantsSection({ carta, onManage }: { carta: CartaCompletaRow; onManage?: () => void }) {
  const model = buildVariantSummaryModel(carta.variantView, carta.name);
  const titleId = `edit-card-variants-${carta.id}`;
  const text =
    model.kind === "HIDDEN"
      ? "Nenhuma variação cadastrada"
      : model.kind === "UNAVAILABLE"
        ? "Detalhes indisponíveis"
        : model.count === 1
          ? "1 variação cadastrada"
          : `${model.count} variações cadastradas`;
  return (
    <section aria-labelledby={titleId} className="rounded-md border border-border px-3 py-2.5">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0 space-y-0.5">
          <p id={titleId} className="text-xs font-medium text-muted-foreground">
            Variações
          </p>
          <p className="text-sm text-foreground">{text}</p>
        </div>
        {onManage ? (
          <Button type="button" variant="outline" size="sm" className="shrink-0" onClick={onManage}>
            Gerenciar
          </Button>
        ) : null}
      </div>
    </section>
  );
}

function EditCardForm({
  carta,
  raridades,
  categorias,
  onSaved,
  onCancel,
  onPendingChange,
  onManageDefaultVariant,
  defaultVariantNotice,
  onManageVariants,
}: {
  carta: CartaCompletaRow;
  raridades: RaridadeRow[];
  categorias: CategoriaOption[];
  onSaved: (message: string, id?: string) => void;
  onCancel: () => void;
  onPendingChange: (pending: boolean) => void;
  onManageDefaultVariant?: () => void;
  defaultVariantNotice: string | null;
  onManageVariants?: () => void;
}) {
  const [state, formAction, pending] = useActionState(updateCard, initialState);

  useEffect(() => {
    onPendingChange(pending);
  }, [pending, onPendingChange]);

  useEffect(() => {
    if (state.success) {
      onSaved("Card atualizada com sucesso.", carta.id);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success]);

  return (
    <form action={formAction}>
      <input type="hidden" name="id" value={carta.id} />
      <DialogBody className="space-y-4">
        <div className="space-y-1">
          <Label htmlFor={`edit-card-name-${carta.id}`}>Nome</Label>
          <Input id={`edit-card-name-${carta.id}`} name="name" defaultValue={carta.name} required maxLength={150} />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-card-total-${carta.id}`}>Total (opcional)</Label>
            <Input
              id={`edit-card-total-${carta.id}`}
              name="collector_total"
              type="number"
              min={1}
              step={1}
              defaultValue={carta.collectorTotal ?? ""}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-card-order-${carta.id}`}>Ordem editorial</Label>
            <Input
              id={`edit-card-order-${carta.id}`}
              name="collector_order"
              type="number"
              min={1}
              step={1}
              defaultValue={carta.collectorOrder}
              required
            />
          </div>
        </div>
        <p className="-mt-2 text-xs text-muted-foreground">
          Ordem editorial: posição da carta no checklist oficial do Card Set — define a ordem de exibição na galeria.
        </p>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <Label htmlFor={`edit-card-rarity-${carta.id}`}>Raridade</Label>
            <Select id={`edit-card-rarity-${carta.id}`} name="rarity_id" required defaultValue={carta.rarityId}>
              {raridades.map((raridade) => (
                <option key={raridade.id} value={raridade.id}>
                  {raridade.name}
                </option>
              ))}
            </Select>
          </div>
          <div className="space-y-1">
            <Label htmlFor={`edit-card-category-${carta.id}`}>Categoria</Label>
            <Select id={`edit-card-category-${carta.id}`} name="category_id" required defaultValue={carta.categoryId}>
              {categorias.map((categoria) => (
                <option key={categoria.id} value={categoria.id}>
                  {categoria.name}
                </option>
              ))}
            </Select>
          </div>
        </div>

        <VariantsSection carta={carta} onManage={onManageVariants} />
        <DefaultVariantSection carta={carta} onManage={onManageDefaultVariant} notice={defaultVariantNotice} />

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

/**
 * Confirmação de desativação de Card — novo em 2026-08-07, fecha o
 * subciclo Card do ADR-023. Diferente de `ConfirmDeleteBar` (exclusão real,
 * irreversível, usada por Game/Expansion/Card Set), esta ação é reversível
 * (soft delete real via `card.is_active`, ver `admin_deactivate_card()`,
 * Query 2116) — por isso um Dialog de confirmação próprio, com linguagem
 * que deixa isso explícito ("pode ser reativada a qualquer momento"), em vez
 * de reaproveitar a tarja "esta ação não pode ser desfeita" de
 * `ConfirmDeleteBar`, que descreveria mal o que de fato acontece.
 *
 * Chama `deactivateCard()` diretamente (sem `useActionState`/`<form>`,
 * mesmo padrão de `setCardSetLogo()`) — não há campo nenhum para coletar,
 * só uma confirmação e o `id` já conhecido.
 */
export function DeactivateCardDialog({
  open,
  carta,
  onConfirmed,
  onCancel,
}: {
  open: boolean;
  carta: CartaCompletaRow | null;
  onConfirmed: (message: string, id?: string) => void;
  onCancel: () => void;
}) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) setError(null);
  }, [open]);

  async function handleConfirm() {
    if (!carta) return;
    setPending(true);
    setError(null);
    const result = await deactivateCard(carta.id);
    setPending(false);
    if (result.error) {
      setError(result.error);
      return;
    }
    onConfirmed("Card desativada com sucesso.", carta.id);
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && !pending && onCancel()}>
      <DialogContent
        onEscapeKeyDown={(event) => pending && event.preventDefault()}
        onInteractOutside={(event) => pending && event.preventDefault()}
      >
        <DialogHeader>
          <DialogTitle>Desativar Card</DialogTitle>
          <DialogDescription>
            {carta ? `${carta.name} · Nº ${carta.collectorNumber}` : "Carta"} deixa de aparecer nas telas
            operacionais (galeria, importação de imagens, etc.). Nenhum dado é apagado — variações e imagens já
            importadas permanecem intactas, e a Card pode ser reativada a qualquer momento.
          </DialogDescription>
        </DialogHeader>

        {error && (
          <DialogBody>
            <InlineFeedback tone="error">{error}</InlineFeedback>
          </DialogBody>
        )}

        <DialogFooter>
          <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
            Cancelar
          </Button>
          <Button type="button" variant="destructive" size="sm" onClick={handleConfirm} disabled={pending}>
            {pending ? "Desativando…" : "Desativar"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
