"use client";

import { useCallback, useEffect, useRef, useState } from "react";

/**
 * Revela itens de uma lista longa em lotes conforme o usuário rola até o
 * fim, em vez de um botão "Ver todas" — pedido de Fabrício (2026-08-09), nas
 * duas galerias de Cartas que paginavam client-side com esse botão
 * (`CartasGallery`, tela `/catalogo/cartas`, e `CardSetCartasGrid`, seção do
 * hub de Card Set): "remover o botão 'Ver todas as cartas' e carregar as
 * cartas à medida que o usuário rola a tela para baixo".
 *
 * Usa `IntersectionObserver` sobre um elemento sentinela (`sentinelRef`)
 * renderizado logo após o último item revelado — quando ele entra na
 * viewport (com folga de `rootMargin`, para revelar um pouco antes do fim
 * literal da tela, sem esperar o usuário bater no rodapé), mais um lote
 * (`pageSize`) é revelado. `sentinelRef` é um callback ref (não um
 * `useRef` + `useEffect` sobre `.current`) de propósito: a lista some/volta
 * entre estados (busca sem resultado, filtro vazio), então o próprio
 * elemento sentinela desmonta e remonta — um callback ref reconecta o
 * observer a cada montagem real, o que um `useEffect` com dependência fixa
 * não faria sozinho.
 *
 * `resetKey` — qualquer valor que, ao mudar, deve voltar a exibição para o
 * primeiro lote (busca, troca de Coleção/filtro). Sem isso, trocar de
 * contexto manteria a contagem já revelada da lista anterior.
 */
export function useInfiniteReveal(pageSize: number, resetKey: unknown) {
  const [visibleCount, setVisibleCount] = useState(pageSize);
  const observerRef = useRef<IntersectionObserver | null>(null);

  useEffect(() => {
    setVisibleCount(pageSize);
  }, [resetKey, pageSize]);

  const sentinelRef = useCallback(
    (node: HTMLDivElement | null) => {
      observerRef.current?.disconnect();
      observerRef.current = null;
      if (!node) return;
      observerRef.current = new IntersectionObserver(
        (entries) => {
          if (entries[0]?.isIntersecting) {
            setVisibleCount((count) => count + pageSize);
          }
        },
        { rootMargin: "600px" },
      );
      observerRef.current.observe(node);
    },
    [pageSize],
  );

  return { visibleCount, sentinelRef };
}
