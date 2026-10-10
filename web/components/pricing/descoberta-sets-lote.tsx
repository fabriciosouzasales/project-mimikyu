"use client";

import { ArrowRight, Check, RefreshCw, Search, Sparkles } from "lucide-react";
import { useMemo, useState, useTransition } from "react";
import { Panel } from "@/components/catalogo/panel";
import { StateBadge, type StateTone } from "@/components/catalogo/state-badge";
import { Button } from "@/components/ui/button";
import {
  DataTable,
  DataTableCell,
  DataTableHead,
  DataTableHeadCell,
  DataTableHeadRow,
  DataTableRow,
} from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/empty-state";
import { InlineFeedback } from "@/components/ui/feedback";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import {
  confirmarCorrespondenciasEmLote,
  descobrirCorrespondenciasEmLote,
  type LoteEstado,
  type LoteItem,
  type LoteSetExterno,
  type ResultadoItemLote,
} from "@/app/pricing/mapeamentos-sets/descoberta/actions";
import { cn, formatManagerialDateTime, formatNumber } from "@/lib/utils";

/**
 * Descoberta de correspondências em lote (PRICING-MODULE-RECOVERY-01, Fase 3, 2026-10-10).
 *
 * Fluxo em 3 grupos, em vez de um diálogo por Set:
 *   Prontos       — data de lançamento casa com exatamente 1 Set da JustTCG (pré-selecionados).
 *   Revisar       — várias opções na mesma data, dois Sets locais disputando o mesmo Set externo,
 *                   ou o Set externo já usado por outro Set: o admin escolhe.
 *   Sem correspondência — nenhum Set na mesma data; sugestões por data próxima + lista completa.
 * Nada é gravado até "Confirmar"; a confirmação refaz a consulta no servidor e só grava o que
 * continua válido (ver actions.ts). 1 requisição à JustTCG por consulta.
 */

type Grupo = "PRONTOS" | "REVISAR" | "SEM";

const VER_TODOS = "__VER_TODOS__";

const GRUPO_DE: Record<LoteEstado, Grupo> = {
  SAFE_CANDIDATE: "PRONTOS",
  AMBIGUOUS: "REVISAR",
  CONFLICT: "REVISAR",
  TAKEN: "REVISAR",
  NOT_FOUND: "SEM",
};

const MOTIVO: Record<Exclude<LoteEstado, "SAFE_CANDIDATE">, { label: string; tone: StateTone }> = {
  AMBIGUOUS: { label: "Várias opções", tone: "warning" },
  CONFLICT: { label: "Disputado", tone: "warning" },
  TAKEN: { label: "Já em uso", tone: "danger" },
  NOT_FOUND: { label: "Sem data igual", tone: "muted" },
};

function motivoTexto(item: LoteItem): string {
  switch (item.state) {
    case "AMBIGUOUS":
      return `${item.suggestions.length} Sets da JustTCG lançados no mesmo dia`;
    case "CONFLICT":
      return `Mesmo Set externo sugerido para ${item.conflictWith.join(", ")}`;
    case "TAKEN":
      return `${item.candidate?.externalSetName ?? "Set externo"} já está vinculado a ${item.conflictWith[0] ?? "outro Set"}`;
    case "NOT_FOUND":
      return item.releaseDate
        ? item.suggestions.length > 0
          ? "Nenhum Set no mesmo dia — veja os mais próximos"
          : "Nenhum Set da JustTCG perto desta data"
        : "Set sem data de lançamento no catálogo";
    default:
      return "";
  }
}

function formatData(iso: string | null): string {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
}

function diasTexto(n: number): string {
  if (n === 0) return "mesmo dia";
  return `${n} ${n === 1 ? "dia" : "dias"}`;
}

export function DescobertaSetsLote({ pendingSets, pendingCards }: { pendingSets: number; pendingCards: number }) {
  const [items, setItems] = useState<LoteItem[] | null>(null);
  const [externalSets, setExternalSets] = useState<LoteSetExterno[]>([]);
  const [generatedAt, setGeneratedAt] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [grupo, setGrupo] = useState<Grupo>("PRONTOS");
  const [busca, setBusca] = useState("");
  const [escolha, setEscolha] = useState<Map<string, string>>(new Map());
  const [selecionados, setSelecionados] = useState<Set<string>>(new Set());
  const [confirmando, setConfirmando] = useState(false);
  const [resultado, setResultado] = useState<{ confirmed: number; falhas: ResultadoItemLote[] } | null>(null);
  const [consultando, startConsulta] = useTransition();
  const [gravando, startGravacao] = useTransition();

  function consultar() {
    setError(null);
    setResultado(null);
    setConfirmando(false);
    startConsulta(async () => {
      const res = await descobrirCorrespondenciasEmLote();
      if (!res.ok) {
        setError(res.error);
        return;
      }
      setItems(res.items);
      setExternalSets(res.externalSets);
      setGeneratedAt(res.generatedAt);
      const preEscolha = new Map<string, string>();
      const preSel = new Set<string>();
      for (const it of res.items) {
        if (it.state === "SAFE_CANDIDATE" && it.candidate) {
          preEscolha.set(it.cardSetId, it.candidate.externalSetId);
          preSel.add(it.cardSetId);
        }
      }
      setEscolha(preEscolha);
      setSelecionados(preSel);
      const temProntos = res.items.some((i) => i.state === "SAFE_CANDIDATE");
      setGrupo(temProntos ? "PRONTOS" : res.items.some((i) => GRUPO_DE[i.state] === "REVISAR") ? "REVISAR" : "SEM");
    });
  }

  const contagem = useMemo(() => {
    const c: Record<Grupo, number> = { PRONTOS: 0, REVISAR: 0, SEM: 0 };
    for (const it of items ?? []) c[GRUPO_DE[it.state]]++;
    return c;
  }, [items]);

  const visiveis = useMemo(() => {
    const q = busca.trim().toLowerCase();
    return (items ?? [])
      .filter((it) => GRUPO_DE[it.state] === grupo)
      .filter((it) => !q || `${it.cardSetCode} ${it.cardSetName} ${it.expansionName}`.toLowerCase().includes(q));
  }, [items, grupo, busca]);

  // Set externo escolhido por outro Set local na sessão atual — evita escolher o mesmo duas vezes.
  const externoEscolhidoPor = useMemo(() => {
    const m = new Map<string, string>();
    for (const [cardSetId, ext] of escolha) {
      if (selecionados.has(cardSetId)) {
        const code = items?.find((i) => i.cardSetId === cardSetId)?.cardSetCode;
        if (code) m.set(ext, code);
      }
    }
    return m;
  }, [escolha, selecionados, items]);

  const selecionadosValidos = useMemo(
    () => (items ?? []).filter((it) => selecionados.has(it.cardSetId) && escolha.has(it.cardSetId)),
    [items, selecionados, escolha],
  );
  const cartasSelecionadas = selecionadosValidos.reduce((acc, it) => acc + it.activeCardCount, 0);

  function alternar(cardSetId: string) {
    if (!escolha.has(cardSetId)) return;
    setConfirmando(false);
    setSelecionados((prev) => {
      const next = new Set(prev);
      if (next.has(cardSetId)) next.delete(cardSetId);
      else next.add(cardSetId);
      return next;
    });
  }

  function alternarVisiveis(marcar: boolean) {
    setConfirmando(false);
    setSelecionados((prev) => {
      const next = new Set(prev);
      for (const it of visiveis) {
        if (!escolha.has(it.cardSetId)) continue;
        if (marcar) next.add(it.cardSetId);
        else next.delete(it.cardSetId);
      }
      return next;
    });
  }

  function escolher(cardSetId: string, externalSetId: string) {
    setConfirmando(false);
    setEscolha((prev) => {
      const next = new Map(prev);
      if (externalSetId) next.set(cardSetId, externalSetId);
      else next.delete(cardSetId);
      return next;
    });
    setSelecionados((prev) => {
      const next = new Set(prev);
      if (externalSetId) next.add(cardSetId);
      else next.delete(cardSetId);
      return next;
    });
  }

  function confirmar() {
    const decisoes = selecionadosValidos.map((it) => ({ cardSetId: it.cardSetId, externalSetId: escolha.get(it.cardSetId)! }));
    startGravacao(async () => {
      const res = await confirmarCorrespondenciasEmLote(decisoes);
      setConfirmando(false);
      if (!res.ok) {
        setError(res.error);
        return;
      }
      setError(null);
      const ok = new Set(res.results.filter((r) => r.ok).map((r) => r.cardSetId));
      setItems((prev) => (prev ?? []).filter((it) => !ok.has(it.cardSetId)));
      setSelecionados((prev) => new Set([...prev].filter((id) => !ok.has(id))));
      setEscolha((prev) => new Map([...prev].filter(([id]) => !ok.has(id))));
      setResultado({ confirmed: res.confirmed, falhas: res.results.filter((r) => !r.ok) });
    });
  }

  // ---------- Estado inicial ----------
  if (items === null) {
    return (
      <Panel className="p-5 sm:p-6">
        {consultando ? (
          <DescobertaSkeleton />
        ) : (
          <div className="flex flex-col gap-5 sm:flex-row sm:items-center sm:justify-between">
            <div className="max-w-xl space-y-1.5">
              <h2 className="text-base font-medium text-foreground">
                {pendingSets > 0
                  ? `${formatNumber(pendingSets)} Sets ainda sem correspondência na JustTCG`
                  : "Todos os Sets já têm correspondência"}
              </h2>
              <p className="text-sm text-muted-foreground">
                {pendingSets > 0
                  ? `São ${formatNumber(pendingCards)} cartas sem preço. A descoberta compara a data de lançamento de cada Set com o catálogo da JustTCG numa única consulta e separa o que pode ser confirmado direto do que precisa da sua escolha.`
                  : "Quando novos Sets entrarem no catálogo, volte aqui para vinculá-los."}
              </p>
              {error && (
                <div className="pt-2">
                  <InlineFeedback tone="error">{error}</InlineFeedback>
                </div>
              )}
            </div>
            {pendingSets > 0 && (
              <div className="flex shrink-0 flex-col items-start gap-1.5 sm:items-end">
                <Button onClick={consultar}>
                  <Sparkles className="h-4 w-4" aria-hidden="true" />
                  Descobrir correspondências
                </Button>
                <span className="text-[11px] text-muted-foreground">Usa 1 requisição da cota diária</span>
              </div>
            )}
          </div>
        )}
      </Panel>
    );
  }

  const todosVisiveisMarcados =
    visiveis.filter((it) => escolha.has(it.cardSetId)).length > 0 &&
    visiveis.filter((it) => escolha.has(it.cardSetId)).every((it) => selecionados.has(it.cardSetId));

  return (
    <div className="space-y-3">
      {/* Resumo + reconsulta */}
      <Panel className="flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between">
        <div role="group" aria-label="Grupos de Sets" className="flex flex-wrap gap-1.5">
          <GrupoTab ativo={grupo === "PRONTOS"} onClick={() => setGrupo("PRONTOS")} label="Prontos para confirmar" count={contagem.PRONTOS} tone="success" />
          <GrupoTab ativo={grupo === "REVISAR"} onClick={() => setGrupo("REVISAR")} label="Revisar" count={contagem.REVISAR} tone="warning" />
          <GrupoTab ativo={grupo === "SEM"} onClick={() => setGrupo("SEM")} label="Sem correspondência" count={contagem.SEM} tone="muted" />
        </div>
        <div className="flex items-center gap-3 text-xs text-muted-foreground">
          {generatedAt && <span>Consultado {formatManagerialDateTime(generatedAt)}</span>}
          <Button variant="outline" size="sm" onClick={consultar} disabled={consultando || gravando}>
            <RefreshCw className={cn("h-3.5 w-3.5", consultando && "animate-spin motion-reduce:animate-none")} aria-hidden="true" />
            {consultando ? "Consultando…" : "Consultar de novo"}
          </Button>
        </div>
      </Panel>

      <div aria-live="polite" className="space-y-2">
        {error && <InlineFeedback tone="error">{error}</InlineFeedback>}
        {resultado && resultado.confirmed > 0 && (
          <InlineFeedback tone="success">
            {resultado.confirmed === 1 ? "1 Set confirmado." : `${formatNumber(resultado.confirmed)} Sets confirmados.`} As cartas
            começam a ser vinculadas nos próximos minutos (1 Set a cada 5 min) e os preços chegam na sincronização seguinte.
          </InlineFeedback>
        )}
        {resultado && resultado.falhas.length > 0 && (
          <InlineFeedback tone="warning">
            <span>
              {resultado.falhas.length === 1 ? "1 Set não foi confirmado" : `${resultado.falhas.length} Sets não foram confirmados`}:{" "}
              {resultado.falhas.map((f) => `${f.cardSetCode} (${f.error})`).join("; ")}
            </span>
          </InlineFeedback>
        )}
      </div>

      <Panel className="overflow-hidden">
        <div className="flex flex-col gap-2 border-b border-border px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-xs text-muted-foreground">{DESCRICAO_GRUPO[grupo]}</p>
          <div className="relative w-full sm:w-64">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
            <Input
              value={busca}
              onChange={(e) => setBusca(e.target.value)}
              placeholder="Buscar Set"
              aria-label="Buscar Set por código ou nome"
              className="h-8 pl-8 text-xs"
            />
          </div>
        </div>

        {visiveis.length === 0 ? (
          <EmptyState
            title={busca ? "Nenhum Set encontrado" : VAZIO_GRUPO[grupo].title}
            description={busca ? "Tente outro código ou nome." : VAZIO_GRUPO[grupo].description}
          />
        ) : (
          <div className="px-4">
            <DataTable>
              <DataTableHead>
                <DataTableHeadRow>
                  <DataTableHeadCell className="w-8">
                    <input
                      type="checkbox"
                      className="h-3.5 w-3.5 accent-primary"
                      checked={todosVisiveisMarcados}
                      onChange={(e) => alternarVisiveis(e.target.checked)}
                      aria-label="Selecionar todos os Sets visíveis"
                    />
                  </DataTableHeadCell>
                  <DataTableHeadCell>Set do catálogo</DataTableHeadCell>
                  <DataTableHeadCell className="hidden md:table-cell">Lançamento</DataTableHeadCell>
                  <DataTableHeadCell align="right" className="hidden sm:table-cell">Cartas</DataTableHeadCell>
                  <DataTableHeadCell className="w-6" aria-hidden="true" />
                  <DataTableHeadCell>Set na JustTCG</DataTableHeadCell>
                </DataTableHeadRow>
              </DataTableHead>
              <tbody>
                {visiveis.map((it) => (
                  <LinhaSet
                    key={it.cardSetId}
                    item={it}
                    externalSets={externalSets}
                    escolhido={escolha.get(it.cardSetId) ?? ""}
                    marcado={selecionados.has(it.cardSetId)}
                    externoEscolhidoPor={externoEscolhidoPor}
                    onToggle={() => alternar(it.cardSetId)}
                    onEscolher={(ext) => escolher(it.cardSetId, ext)}
                  />
                ))}
              </tbody>
            </DataTable>
          </div>
        )}
      </Panel>

      {/* Barra de confirmação — fica visível ao rolar listas longas */}
      <div className="sticky bottom-3 z-10">
        <Panel
          className={cn(
            "flex flex-col gap-3 p-3 shadow-[0_8px_24px_-12px_hsl(var(--foreground)/0.35)] sm:flex-row sm:items-center sm:justify-between",
            selecionadosValidos.length === 0 && "opacity-90",
          )}
        >
          <p className="text-sm text-foreground">
            {selecionadosValidos.length === 0 ? (
              <span className="text-muted-foreground">Selecione os Sets que deseja vincular.</span>
            ) : (
              <>
                <span className="font-medium">{formatNumber(selecionadosValidos.length)}</span>{" "}
                {selecionadosValidos.length === 1 ? "Set selecionado" : "Sets selecionados"}
                <span className="text-muted-foreground"> · {formatNumber(cartasSelecionadas)} cartas passam a receber preço</span>
              </>
            )}
          </p>
          <div className="flex items-center gap-2">
            {confirmando ? (
              <>
                <Button variant="outline" size="sm" onClick={() => setConfirmando(false)} disabled={gravando}>
                  Cancelar
                </Button>
                <Button size="sm" onClick={confirmar} disabled={gravando}>
                  <Check className="h-3.5 w-3.5" aria-hidden="true" />
                  {gravando ? "Confirmando…" : `Sim, vincular ${formatNumber(selecionadosValidos.length)}`}
                </Button>
              </>
            ) : (
              <Button size="sm" onClick={() => setConfirmando(true)} disabled={selecionadosValidos.length === 0 || consultando}>
                Confirmar correspondências
              </Button>
            )}
          </div>
        </Panel>
      </div>
    </div>
  );
}

const DESCRICAO_GRUPO: Record<Grupo, string> = {
  PRONTOS: "A data de lançamento bate com exatamente um Set da JustTCG. Revise e confirme.",
  REVISAR: "Mais de uma opção possível. Escolha o Set da JustTCG correspondente.",
  SEM: "Nenhum Set da JustTCG no mesmo dia. Escolha manualmente se reconhecer o Set, ou deixe para depois.",
};

const VAZIO_GRUPO: Record<Grupo, { title: string; description: string }> = {
  PRONTOS: { title: "Nenhum Set pronto", description: "Os Sets restantes precisam da sua escolha nas outras abas." },
  REVISAR: { title: "Nada para revisar", description: "Nenhum Set com opções ambíguas." },
  SEM: { title: "Todos os Sets têm alguma sugestão", description: "Nenhum Set ficou sem correspondência." },
};

function GrupoTab({
  ativo,
  onClick,
  label,
  count,
  tone,
}: {
  ativo: boolean;
  onClick: () => void;
  label: string;
  count: number;
  tone: "success" | "warning" | "muted";
}) {
  return (
    <button
      type="button"
      aria-pressed={ativo}
      onClick={onClick}
      className={cn(
        "inline-flex h-8 items-center gap-2 rounded-md border px-3 text-xs transition-colors",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background",
        ativo
          ? "border-primary/60 bg-primary/10 text-foreground"
          : "border-transparent text-muted-foreground hover:bg-surface-muted hover:text-foreground",
      )}
    >
      {label}
      <span
        className={cn(
          "min-w-[1.5rem] rounded-full px-1.5 py-0.5 text-[11px] font-medium tabular-nums leading-none",
          tone === "success" && "bg-success/15 text-success",
          tone === "warning" && "bg-warning/15 text-warning",
          tone === "muted" && "bg-muted text-muted-foreground",
        )}
      >
        {count}
      </span>
    </button>
  );
}

function LinhaSet({
  item,
  externalSets,
  escolhido,
  marcado,
  externoEscolhidoPor,
  onToggle,
  onEscolher,
}: {
  item: LoteItem;
  externalSets: LoteSetExterno[];
  escolhido: string;
  marcado: boolean;
  externoEscolhidoPor: Map<string, string>;
  onToggle: () => void;
  onEscolher: (externalSetId: string) => void;
}) {
  const seguro = item.state === "SAFE_CANDIDATE";
  const sugestaoIds = new Set(item.suggestions.map((s) => s.externalSetId));
  // Lista completa (~250 Sets) só é montada quando pedida — evita milhares de <option> no DOM.
  const [listaCompleta, setListaCompleta] = useState(Boolean(escolhido) && !sugestaoIds.has(escolhido));
  const externoPorId = useMemo(() => new Map(externalSets.map((e) => [e.externalSetId, e])), [externalSets]);
  const desabilitar = (id: string) => {
    const ext = externoPorId.get(id);
    if (ext?.takenBy) return `em uso por ${ext.takenBy}`;
    const outro = externoEscolhidoPor.get(id);
    if (outro && outro !== item.cardSetCode) return `escolhido para ${outro}`;
    return null;
  };

  return (
    <DataTableRow className={cn(marcado && "bg-primary/[0.04]")}>
      <DataTableCell>
        <input
          type="checkbox"
          className="h-3.5 w-3.5 accent-primary disabled:opacity-40"
          checked={marcado}
          disabled={!escolhido}
          onChange={onToggle}
          aria-label={`Selecionar ${item.cardSetCode} ${item.cardSetName}`}
        />
      </DataTableCell>
      <DataTableCell>
        <div className="min-w-0">
          <p className="truncate text-sm text-foreground">
            <span className="mr-1.5 text-xs font-medium tabular-nums text-muted-foreground">{item.cardSetCode}</span>
            {item.cardSetName}
          </p>
          <p className="truncate text-[11px] text-muted-foreground">
            {item.expansionName}
            <span className="md:hidden"> · {formatData(item.releaseDate)}</span>
          </p>
        </div>
      </DataTableCell>
      <DataTableCell className="hidden whitespace-nowrap tabular-nums md:table-cell">{formatData(item.releaseDate)}</DataTableCell>
      <DataTableCell align="right" className="hidden tabular-nums sm:table-cell">
        {formatNumber(item.activeCardCount)}
      </DataTableCell>
      <DataTableCell className="text-muted-foreground/60">
        <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
      </DataTableCell>
      <DataTableCell className="min-w-[14rem]">
        {seguro && item.candidate ? (
          <div className="min-w-0">
            <p className="truncate text-sm text-foreground">{item.candidate.externalSetName}</p>
            <p className="text-[11px] text-success">Mesma data de lançamento</p>
          </div>
        ) : (
          <div className="space-y-1.5 py-0.5">
            <div className="flex items-center gap-2">
              <StateBadge tone={MOTIVO[item.state as Exclude<LoteEstado, "SAFE_CANDIDATE">].tone}>
                {MOTIVO[item.state as Exclude<LoteEstado, "SAFE_CANDIDATE">].label}
              </StateBadge>
              <span className="truncate text-[11px] text-muted-foreground">{motivoTexto(item)}</span>
            </div>
            <Select
              value={escolhido}
              onChange={(e) => {
                if (e.target.value === VER_TODOS) {
                  setListaCompleta(true);
                  return;
                }
                onEscolher(e.target.value);
              }}
              aria-label={`Set da JustTCG para ${item.cardSetCode}`}
              className="h-8 text-xs"
            >
              <option value="">Escolher Set da JustTCG…</option>
              {item.suggestions.length > 0 && (
                <optgroup label={item.state === "AMBIGUOUS" ? "Lançados no mesmo dia" : "Datas mais próximas"}>
                  {item.suggestions.map((s) => {
                    const motivo = desabilitar(s.externalSetId);
                    return (
                      <option key={s.externalSetId} value={s.externalSetId} disabled={Boolean(motivo)}>
                        {s.externalSetName} · {formatData(s.releaseDate)}
                        {item.state !== "AMBIGUOUS" ? ` (${diasTexto(s.daysApart)})` : ""}
                        {motivo ? ` — ${motivo}` : ""}
                      </option>
                    );
                  })}
                </optgroup>
              )}
              {listaCompleta ? (
                <optgroup label="Todos os Sets da JustTCG">
                {externalSets
                  .filter((e) => !sugestaoIds.has(e.externalSetId))
                  .map((e) => {
                    const motivo = desabilitar(e.externalSetId);
                    return (
                      <option key={e.externalSetId} value={e.externalSetId} disabled={Boolean(motivo)}>
                        {e.externalSetName} · {formatData(e.releaseDate)}
                        {motivo ? ` — ${motivo}` : ""}
                      </option>
                    );
                  })}
              </optgroup>
              ) : (
                <option value={VER_TODOS}>Ver todos os Sets da JustTCG…</option>
              )}
            </Select>
          </div>
        )}
      </DataTableCell>
    </DataTableRow>
  );
}

function DescobertaSkeleton() {
  return (
    <div className="space-y-4" aria-busy="true" aria-live="polite">
      <p className="text-sm text-muted-foreground">Consultando a JustTCG e comparando datas de lançamento…</p>
      <div className="flex gap-2">
        <Skeleton className="h-8 w-44" />
        <Skeleton className="h-8 w-24" />
        <Skeleton className="h-8 w-40" />
      </div>
      <div className="space-y-2">
        {Array.from({ length: 6 }).map((_, i) => (
          <Skeleton key={i} className="h-10 w-full" />
        ))}
      </div>
    </div>
  );
}
