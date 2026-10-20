"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Sparkles, X } from "lucide-react";
import { readPokedexBulkPreview } from "@/app/colecoes/colecoes/actions";
import { Button } from "@/components/ui/button";
import { ACERVO_PATH, formatCount } from "@/lib/colecoes/acervo";
import { POKEDEX_FIRST_RUN_DISMISSED_EVENT, PokedexBulkLauncher } from "./pokedex-bulk-link";
import styles from "./pokedex.module.css";

type Readiness = { status: "loading" } | { status: "ready"; available: number } | { status: "unknown" };

/**
 * A contagem usa a prévia do lote (5211), a leitura mais pesada da Pokédex.
 * Para não concorrer com a grade (timeout observado logo após remover a última
 * carta): roda só com o navegador ocioso, e o resultado vale por 60 s na aba —
 * remontagens e `router.refresh` não repetem a chamada.
 */
const COUNT_TTL_MS = 60_000;
const countCache = new Map<string, { at: number; available: number }>();

function whenIdle(task: () => void): () => void {
  if (typeof window.requestIdleCallback === "function") {
    const handle = window.requestIdleCallback(task, { timeout: 2500 });
    return () => window.cancelIdleCallback(handle);
  }
  const handle = window.setTimeout(task, 400);
  return () => window.clearTimeout(handle);
}

/**
 * Aviso de primeiro uso da Pokédex (UX-05) — só enquanto nenhum Pokémon foi
 * conquistado. Mostra quantos Pokémon desta Pokédex já têm carta LIVRE no
 * acervo (prévia do lote, 5211, sem SQL novo) e leva direto a "Completar com o
 * acervo", com revisão antes de confirmar. Sem cartas livres que sirvam,
 * orienta para o Meu acervo. Dispensável na sessão ("Agora não").
 */
export function PokedexFirstRun({ collectionId }: { collectionId: string }) {
  const [readiness, setReadiness] = useState<Readiness>({ status: "loading" });
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    const cached = countCache.get(collectionId);
    if (cached && Date.now() - cached.at < COUNT_TTL_MS) {
      setReadiness({ status: "ready", available: cached.available });
      return;
    }
    let alive = true;
    const cancel = whenIdle(() => {
      readPokedexBulkPreview({ collectionId, generation: null })
        .then((result) => {
          if (result.ok) countCache.set(collectionId, { at: Date.now(), available: result.total });
          if (!alive) return;
          setReadiness(result.ok ? { status: "ready", available: result.total } : { status: "unknown" });
        })
        .catch(() => alive && setReadiness({ status: "unknown" }));
    });
    return () => {
      alive = false;
      cancel();
    };
  }, [collectionId]);

  const dismiss = () => {
    setDismissed(true);
    window.dispatchEvent(new Event(POKEDEX_FIRST_RUN_DISMISSED_EVENT));
  };

  if (dismissed) return null;

  const available = readiness.status === "ready" ? readiness.available : null;

  return (
    <section className={styles.firstRun} aria-labelledby="pokedex-primeiros-passos">
      <span className={styles.firstRunIcon} aria-hidden="true">
        <Sparkles className="h-5 w-5" />
      </span>
      <div className={styles.firstRunBody}>
        <h3 id="pokedex-primeiros-passos" className={styles.firstRunTitle}>
          {available !== null && available > 0 ? "Sua Pokédex começa com o que você já tem" : "Sua Pokédex está pronta"}
        </h3>
        <p className={styles.firstRunText} aria-live="polite">
          {readiness.status === "loading"
            ? "Procurando no seu acervo cartas que já servem aqui…"
            : available !== null && available > 0
              ? `${formatCount(available)} ${available === 1 ? "Pokémon já tem" : "Pokémon já têm"} carta livre no seu acervo. Adicione de uma vez — você revisa antes de confirmar.`
              : available === 0
                ? "Nenhuma carta livre do seu acervo serve aqui ainda. Cadastre suas cartas no Meu acervo e elas aparecem marcadas na grade."
                : "Toque em um Pokémon para adicionar uma carta, ou use “Completar com o acervo” para trazer várias de uma vez."}
        </p>
      </div>
      <div className={styles.firstRunActions}>
        {available !== null && available > 0 ? (
          <PokedexBulkLauncher collectionId={collectionId} generation={null} label="Revisar e adicionar" className="min-h-11 gap-1.5" />
        ) : available === 0 ? (
          <Button asChild variant="outline" className="min-h-11">
            <Link href={ACERVO_PATH}>Ir para o Meu acervo</Link>
          </Button>
        ) : null}
        <button type="button" className={styles.firstRunDismiss} onClick={dismiss} aria-label="Dispensar este aviso">
          <X className="h-4 w-4" aria-hidden="true" />
        </button>
      </div>
    </section>
  );
}
