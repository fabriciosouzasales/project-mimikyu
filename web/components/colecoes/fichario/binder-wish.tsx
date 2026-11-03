"use client";

import { createContext, type ReactNode, type RefObject, useCallback, useEffect, useRef, useState } from "react";
import { readBinderWishState } from "@/app/colecoes/lista-de-desejos/actions";
import type { BinderPage } from "@/lib/colecoes/binder";
import { binderWishReadPlan, binderWishTarget, binderWishTargetCovered, wishPositionKey } from "@/lib/wishlist/wishlist";
import { WishlistController } from "@/components/wishlist/wishlist-controller";

/**
 * Estado dos marcadores da Lista de desejos no Fichário (V1-11 W5). `null` fora do
 * fichário do titular (compartilhado em só leitura, vitrine): nenhum marcador.
 * `known` = chaves de alvo cobertas por uma leitura bem-sucedida — sem leitura, o bolso
 * não mostra marcador (nunca "não desejada" por falta de dado).
 */
export type BinderWishValue = {
  variants: ReadonlySet<string>;
  positions: ReadonlySet<string>;
  known: ReadonlySet<string>;
};

export const BinderWishContext = createContext<BinderWishValue | null>(null);

const EMPTY: BinderWishValue = { variants: new Set(), positions: new Set(), known: new Set() };

function allSlots(pages: ReadonlyMap<number, BinderPage>) {
  return [...pages.values()].flatMap((page) => page.slots);
}

/**
 * Camada da Lista de desejos no Fichário: UMA leitura agregada por lote de páginas
 * carregadas (variantes + posições, só ids ainda não lidos), o controlador da W1 por
 * delegação (nenhum componente cliente por bolso) e a releitura da carta afetada após
 * cada confirmação — para que bolsos da mesma carta (ocupado e reservado, por exemplo)
 * passem a refletir o mesmo desejo.
 *
 * Nunca grava nada no fichário: não conhece bolso, reserva, alocação nem exemplar além
 * de LER o que cada bolso mostra. A raiz é `display: contents` para não mexer na grade
 * do Fichário; a escolha de variante monta dentro do próprio Fichário (sobreposição e
 * tela cheia).
 */
export function BinderWishLayer({
  pages,
  dialogContainer,
  onFeedback,
  children,
}: {
  pages: ReadonlyMap<number, BinderPage>;
  dialogContainer: RefObject<HTMLElement | null>;
  onFeedback: (feedback: { tone: "success" | "error"; text: string }) => void;
  children: ReactNode;
}) {
  const [state, setState] = useState<BinderWishValue>(EMPTY);
  // Ids já pedidos (com sucesso ou em voo): cada id é lido uma vez por lote, nunca por bolso.
  const requested = useRef({ variants: new Set<string>(), cards: new Set<string>() });
  const pagesRef = useRef(pages);
  useEffect(() => {
    pagesRef.current = pages;
  }, [pages]);

  const read = useCallback(async (variantIds: string[], cardIds: string[]) => {
    if (variantIds.length === 0 && cardIds.length === 0) return;
    const result = await readBinderWishState(variantIds, cardIds).catch(() => null);
    if (!result) {
      // Falha: libera os ids para uma próxima tentativa (nova página, nova confirmação).
      for (const id of variantIds) requested.current.variants.delete(id);
      for (const id of cardIds) requested.current.cards.delete(id);
      return;
    }
    const variantSet = new Set(variantIds);
    const cardSet = new Set(cardIds);
    const wishedVariants = new Set(result.variants);
    const wishedPositions = new Set(result.positions);
    setState((prev) => {
      const variants = new Set(prev.variants);
      for (const id of variantIds) {
        if (wishedVariants.has(id)) variants.add(id);
        else variants.delete(id);
      }
      const positions = new Set([...prev.positions].filter((key) => !cardSet.has(key.slice(0, key.indexOf("|")))));
      for (const key of wishedPositions) positions.add(key);
      const known = new Set(prev.known);
      for (const slot of allSlots(pagesRef.current)) {
        const target = binderWishTarget(slot);
        if (target && binderWishTargetCovered(target, variantSet, cardSet)) known.add(target.key);
      }
      return { variants, positions, known };
    });
  }, []);

  // Páginas novas no cache → lê só o que ainda não foi pedido.
  useEffect(() => {
    const plan = binderWishReadPlan(allSlots(pages));
    const variantIds = plan.variantIds.filter((id) => !requested.current.variants.has(id));
    const cardIds = plan.cardIds.filter((id) => !requested.current.cards.has(id));
    if (variantIds.length === 0 && cardIds.length === 0) {
      // Bolsos que mudaram de conteúdo (mover, reservar) podem trazer alvos já lidos.
      setState((prev) => {
        let changed = false;
        const known = new Set(prev.known);
        for (const slot of allSlots(pages)) {
          const target = binderWishTarget(slot);
          if (!target || known.has(target.key)) continue;
          const covered = target.kind === "variant" ? requested.current.variants.has(target.variantId) : requested.current.cards.has(target.cardId);
          if (covered) {
            known.add(target.key);
            changed = true;
          }
        }
        return changed ? { ...prev, known } : prev;
      });
      return;
    }
    for (const id of variantIds) requested.current.variants.add(id);
    for (const id of cardIds) requested.current.cards.add(id);
    void read(variantIds.slice(0, 2000), cardIds.slice(0, 2000));
  }, [pages, read]);

  /** Relê, em lote, tudo o que os bolsos carregados mostram desta carta. */
  const refreshCard = useCallback(
    (cardId: string) => {
      const variantIds = new Set<string>();
      const cardIds = new Set<string>();
      for (const slot of allSlots(pagesRef.current)) {
        const target = binderWishTarget(slot);
        if (!target || target.cardId !== cardId) continue;
        if (target.kind === "variant") variantIds.add(target.variantId);
        else cardIds.add(target.cardId);
      }
      void read([...variantIds], [...cardIds]);
    },
    [read],
  );

  const cardOfVariant = useCallback((variantId: string): string | null => {
    for (const slot of allSlots(pagesRef.current)) {
      const target = binderWishTarget(slot);
      if (target?.kind === "variant" && target.variantId === variantId && target.cardId) return target.cardId;
    }
    return null;
  }, []);

  const onVariantConfirmed = useCallback(
    (variantId: string, wished: boolean) => {
      setState((prev) => {
        const variants = new Set(prev.variants);
        if (wished) variants.add(variantId);
        else variants.delete(variantId);
        return { ...prev, variants };
      });
      const cardId = cardOfVariant(variantId);
      if (cardId) refreshCard(cardId);
    },
    [cardOfVariant, refreshCard],
  );

  const onTargetConfirmed = useCallback(
    (cardId: string, finish: string | null, wished: boolean) => {
      if (finish !== null) {
        const key = wishPositionKey(cardId, finish);
        setState((prev) => {
          const positions = new Set(prev.positions);
          if (wished) positions.add(key);
          else positions.delete(key);
          return { ...prev, positions };
        });
      }
      refreshCard(cardId);
    },
    [refreshCard],
  );

  return (
    <BinderWishContext.Provider value={state}>
      <WishlistController
        className="contents"
        dialogContainer={dialogContainer}
        onFeedback={onFeedback}
        onVariantConfirmed={onVariantConfirmed}
        onTargetConfirmed={onTargetConfirmed}
      >
        {children}
      </WishlistController>
    </BinderWishContext.Provider>
  );
}
