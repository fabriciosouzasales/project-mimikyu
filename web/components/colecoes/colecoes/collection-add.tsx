"use client";

import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { Loader2, PackagePlus } from "lucide-react";
import { readAddLanguages } from "@/app/colecoes/acervo/actions";
import { readCollectionStorage } from "@/app/colecoes/colecoes/actions";
import { AcervoAddPanel, type AddStorage, type AddTarget } from "@/components/colecoes/acervo/acervo-add";
import { Button } from "@/components/ui/button";
import type { AddLanguage } from "@/lib/colecoes/acervo-add";
import { type RegisterMode, effectiveRegisterMode } from "@/lib/colecoes/collection-add";
import { cn } from "@/lib/utils";

/**
 * "Cartas novas" (V1-06 — Fluxos 2 e 5 a partir da coleção). Abre o mesmo
 * painel de cadastro de Meu acervo, com a coleção como destino: o banco cria os
 * exemplares e já os aloca aqui numa transação (5150/5157). Ao lado de
 * "Adicionar cartas" (do acervo), que continua sendo a ação para cartas que já
 * estão cadastradas.
 *
 * Idiomas lidos só ao abrir (nenhuma leitura a mais no carregamento da página).
 * Só aparece para o titular em coleção ativa (quem chama decide).
 */
export function CollectionAddLauncher({
  target,
  layout = "bar",
  autoOpen = null,
}: {
  target: AddTarget;
  /** `bar`: botão compacto da barra da galeria; `empty`: estado vazio. */
  layout?: "bar" | "empty";
  /** Vindo da criação da coleção (`?cadastrar=`): abre uma vez ao chegar. */
  autoOpen?: RegisterMode | null;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [languages, setLanguages] = useState<AddLanguage[] | null>(null);
  const [storage, setStorage] = useState<AddStorage | null>(null);
  const [mode, setMode] = useState<RegisterMode | null>(null);
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);
  const opened = useRef(false);

  const open = useCallback(
    async (requested: RegisterMode) => {
      if (loading) return;
      setFailed(false);
      const next = effectiveRegisterMode(requested, target.cardSet !== null);
      if (languages) {
        setMode(next);
        return;
      }
      setLoading(true);
      // Idiomas e locais numa ida só (os locais vêm só ao abrir: nenhuma leitura a mais na página).
      const [read, places] = await Promise.all([
        readAddLanguages().catch(() => ({ ok: false as const, reason: "unavailable" as const })),
        readCollectionStorage({ collectionId: target.collectionId }).catch(() => ({ ok: false as const, reason: "unavailable" as const })),
      ]);
      setLoading(false);
      if (!read.ok) {
        setFailed(true);
        return;
      }
      setLanguages(read.languages);
      // Sem leitura de locais: cadastro continua possível, sem local (nada presumido).
      setStorage(
        places.ok
          ? { kind: "choose", locations: places.locations.map((l) => ({ id: l.id, name: l.name })), suggestedId: places.storageId }
          : { kind: "choose", locations: [], suggestedId: null },
      );
      setMode(next);
    },
    [languages, loading, target.cardSet, target.collectionId],
  );

  // Continuidade após criar (Fluxo 1.6): abre uma vez e tira o parâmetro da URL,
  // para recarregar a página não reabrir o painel.
  useEffect(() => {
    if (!autoOpen || opened.current) return;
    opened.current = true;
    void open(autoOpen);
    router.replace(pathname, { scroll: false });
  }, [autoOpen, open, pathname, router]);

  return (
    <>
      <span className="inline-flex items-center gap-2">
        {failed ? (
          <span role="alert" className="text-xs text-destructive dark:text-destructive-foreground">
            Não conseguimos abrir agora. Tente de novo.
          </span>
        ) : null}
        <Button
          variant="outline"
          size={layout === "bar" ? "sm" : "default"}
          onClick={() => void open("cards")}
          disabled={loading}
          aria-busy={loading || undefined}
          aria-label="Cadastrar cartas novas nesta coleção"
          className={cn(layout === "bar" ? "h-8 gap-1.5 rounded-full px-3.5 text-[0.8125rem]" : "min-h-11")}
        >
          {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden="true" /> : <PackagePlus className="h-3.5 w-3.5" aria-hidden="true" />}
          Cartas novas
        </Button>
      </span>
      {mode && languages ? (
        <AcervoAddPanel mode={mode} languages={languages} target={{ ...target, storage: storage ?? undefined }} onClose={() => setMode(null)} />
      ) : null}
    </>
  );
}
