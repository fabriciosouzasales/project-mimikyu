"use client";

import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { AlertTriangle, BookOpenCheck, Info, Loader2 } from "lucide-react";
import { createBinder, previewBinder } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import { Button } from "@/components/ui/button";
import { formatCount, pluralize } from "@/lib/colecoes/acervo";
import {
  BINDER_MODELS,
  type BinderFailure,
  type BinderModelKey,
  type BinderPreview,
  type CollectionKind,
  DEFAULT_MODEL_KEY,
  type ExtraPolicy,
  binderFailureMessage,
  extrasBreakdown,
  modelByKey,
  positionNoun,
  previewVerdict,
  recoveryForBinder,
} from "@/lib/colecoes/binder";
import type { BinderFinish } from "@/lib/colecoes/binder-finish";
import { BinderPageGrid, pocketsFromSample } from "./binder-page";
import styles from "./binder.module.css";

type Notice = { tone: "info" | "warning" | "error"; text: string } | null;

/**
 * Montagem do Fichário Digital (P2-B): escolher o modelo, ver a prévia real
 * (5224, não grava) e confirmar com o `plan_token` daquela prévia.
 *
 * - A prévia é refeita a cada troca de modelo ou de opção de adicionais — o
 *   token muda com eles; só a resposta mais recente vale.
 * - Montar envia exatamente modelo, opção e token exibidos. `PLAN_CHANGED`
 *   (a coleção mudou) descarta o token, refaz a prévia e exige nova
 *   confirmação: nada é criado em silêncio.
 * - A escolha de adicionais não é persistida (C-193).
 */
export function BinderAssembly({
  collectionId,
  finish,
  kind,
}: {
  collectionId: string;
  finish: BinderFinish;
  kind: CollectionKind;
}) {
  const router = useRouter();
  const [model, setModel] = useState<BinderModelKey>(DEFAULT_MODEL_KEY);
  const [policy, setPolicy] = useState<ExtraPolicy>("PRINCIPAL_ONLY");
  const [preview, setPreview] = useState<BinderPreview | null>(null);
  const [previewError, setPreviewError] = useState<BinderFailure | null>(null);
  const [loadingPreview, setLoadingPreview] = useState(true);
  const [notice, setNotice] = useState<Notice>(null);
  const [creating, startCreate] = useTransition();
  const requestId = useRef(0);

  const runPreview = useCallback(
    async (nextModel: BinderModelKey, nextPolicy: ExtraPolicy) => {
      const id = ++requestId.current;
      setLoadingPreview(true);
      setPreviewError(null);
      const result = await previewBinder({ collectionId, model: nextModel, extraPolicy: nextPolicy });
      if (id !== requestId.current) return; // uma resposta mais nova já chegou ou está a caminho
      setLoadingPreview(false);
      if (!result.ok) {
        setPreview(null);
        setPreviewError(result.reason);
        return;
      }
      setPreview(result.preview);
    },
    [collectionId],
  );

  useEffect(() => {
    void runPreview(model, policy);
  }, [model, policy, runPreview]);

  const verdict = preview ? previewVerdict(preview) : null;
  const ready = verdict === "ready" && preview !== null && !loadingPreview && preview.planToken !== null;
  const selected = modelByKey(model);
  const extras = preview ? extrasBreakdown(preview) : [];
  const extrasTotal = preview?.extrasTotal ?? 0;

  function confirm() {
    if (!ready || !preview?.planToken) return;
    const token = preview.planToken;
    setNotice(null);
    startCreate(async () => {
      const result = await createBinder({ collectionId, model, extraPolicy: policy, planToken: token });
      if (result.ok) {
        setNotice({ tone: "info", text: result.outcome === "CREATED" ? "Fichário montado. Abrindo…" : binderFailureMessage("already_exists") });
        router.refresh();
        return;
      }
      const recovery = recoveryForBinder(result.reason);
      setNotice({ tone: result.reason === "plan_changed" ? "warning" : "error", text: binderFailureMessage(result.reason) });
      if (recovery === "open_binder") {
        router.refresh();
      } else if (recovery === "refresh_preview") {
        setPreview(null);
        await runPreview(model, policy);
      }
    });
  }

  return (
    <div className={styles.assembly}>
      <div>
        <p className={styles.intro}>
          O fichário digital organiza esta coleção em páginas, como um fichário de verdade: cada{" "}
          {kind === "FREE" ? "carta ganha um bolso, na ordem em que entrou na coleção" : "posição ganha um bolso, na ordem do checklist"}
          {kind === "SET" || kind === "MASTER_SET" ? ", e as que faltam ficam reservadas" : ""}. Nenhuma carta sai da coleção nem muda de lugar
          no mundo físico.
        </p>

        <div className={styles.block}>
          <h2 className={styles.sectionTitle} id="modelo-titulo">
            Modelo de página
          </h2>
          <p className={styles.sectionHelp}>Colunas × linhas de bolsos, como nas folhas do seu fichário físico.</p>
          <fieldset className={styles.models} aria-labelledby="modelo-titulo">
            {BINDER_MODELS.map((option) => (
              <label key={option.key} className={styles.modelOption}>
                <input
                  type="radio"
                  name="binder-model"
                  value={option.key}
                  checked={model === option.key}
                  onChange={() => setModel(option.key)}
                />
                <span className={styles.modelGlyph} style={{ "--cols": option.columns } as React.CSSProperties} aria-hidden="true">
                  {Array.from({ length: option.pockets }).map((_, index) => (
                    <span key={index} />
                  ))}
                </span>
                <span className={styles.modelName}>
                  {option.columns} × {option.rows}
                </span>
                <span className={styles.modelPockets}>{option.pockets} bolsos</span>
              </label>
            ))}
          </fieldset>
        </div>

        {extrasTotal > 0 || policy === "APPEND_PAGES" ? (
          <div className={styles.block}>
            <h2 className={styles.sectionTitle} id="adicionais-titulo">
              Cartas adicionais
            </h2>
            <p className={styles.sectionHelp}>
              {pluralize(extrasTotal, "carta repete ou não tem posição", "cartas repetem ou não têm posição")} no checklist. Vale só para esta
              montagem.
            </p>
            <fieldset className={styles.policy} aria-labelledby="adicionais-titulo">
              <label className={styles.policyOption}>
                <input type="radio" name="binder-policy" checked={policy === "PRINCIPAL_ONLY"} onChange={() => setPolicy("PRINCIPAL_ONLY")} />
                <strong>Somente a coleção principal</strong>
                <span>Uma carta por bolso. As adicionais continuam na coleção, fora do fichário.</span>
              </label>
              <label className={styles.policyOption}>
                <input type="radio" name="binder-policy" checked={policy === "APPEND_PAGES"} onChange={() => setPolicy("APPEND_PAGES")} />
                <strong>Páginas adicionais</strong>
                <span>As adicionais entram em páginas próprias, depois do checklist — nunca no meio dele.</span>
              </label>
            </fieldset>
          </div>
        ) : null}
      </div>

      <div className={styles.preview} aria-live="polite" aria-busy={loadingPreview || undefined}>
        <div className={styles.previewStage}>
          <div className={styles.binder} data-finish={finish}>
            <BinderPageGrid
              pockets={preview && verdict === "ready" ? pocketsFromSample(preview.sample, selected.columns, selected.rows) : null}
              columns={selected.columns}
              rows={selected.rows}
              pageNumber={1}
              side="single"
              loading={loadingPreview}
              priority
            />
          </div>
          {loadingPreview ? (
            <div className={styles.previewBusy}>
              <span className="inline-flex items-center gap-2">
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                Preparando a prévia…
              </span>
            </div>
          ) : null}
        </div>

        {previewError ? (
          <div className={styles.notice} data-tone="error" role="alert">
            <AlertTriangle className="h-4 w-4" aria-hidden="true" />
            <div>
              <p>{binderFailureMessage(previewError)}</p>
              <Button variant="outline" size="sm" className="mt-2" onClick={() => void runPreview(model, policy)}>
                Ver a prévia de novo
              </Button>
            </div>
          </div>
        ) : null}

        {preview && verdict && verdict !== "ready" && !loadingPreview ? <VerdictNotice verdict={verdict} preview={preview} /> : null}

        {preview && verdict === "ready" ? (
          <>
            <dl className={styles.facts}>
              <div className={styles.fact}>
                <dt>No fichário</dt>
                <dd>
                  {formatCount(preview.positionsTotal ?? 0)}
                  <small>{positionNoun(kind, preview.positionsTotal ?? 0)}</small>
                </dd>
              </div>
              <div className={styles.fact}>
                <dt>Com carta</dt>
                <dd>
                  {formatCount(preview.positionsOwned ?? 0)}
                  <small>{(preview.positionsReserved ?? 0) > 0 ? `${formatCount(preview.positionsReserved ?? 0)} reservadas para completar` : "nada reservado"}</small>
                </dd>
              </div>
              <div className={styles.fact}>
                <dt>Páginas</dt>
                <dd>
                  {formatCount(preview.pagesTotal ?? 0)}
                  <small>{pluralize(preview.slotsTotal ?? 0, "bolso", "bolsos")}</small>
                </dd>
              </div>
            </dl>

            {extras.length > 0 ? (
              <p className={styles.extrasNote}>
                <strong>{pluralize(extrasTotal, "carta adicional", "cartas adicionais")}</strong>:{" "}
                {extras.map((item) => `${formatCount(item.count)} ${item.label}`).join(", ")}.{" "}
                {policy === "APPEND_PAGES"
                  ? `${pluralize(preview.extrasPlaced ?? 0, "vai", "vão")} para as páginas adicionais.`
                  : "Ficam na coleção, fora do fichário."}
              </p>
            ) : null}
          </>
        ) : null}

        {notice ? (
          <div className={styles.notice} data-tone={notice.tone} role={notice.tone === "info" ? "status" : "alert"}>
            {notice.tone === "info" ? <Info className="h-4 w-4" aria-hidden="true" /> : <AlertTriangle className="h-4 w-4" aria-hidden="true" />}
            <p>{notice.text}</p>
          </div>
        ) : null}

        <div className={styles.confirmRow}>
          <Button size="lg" onClick={confirm} disabled={!ready || creating} aria-describedby="montar-nota">
            {creating ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : <BookOpenCheck className="h-4 w-4" aria-hidden="true" />}
            {creating ? "Montando…" : ready && preview?.pagesTotal ? `Montar fichário · ${pluralize(preview.pagesTotal, "página", "páginas")}` : "Montar fichário"}
          </Button>
          <p id="montar-nota" className={styles.confirmNote}>
            Monta exatamente o que está na prévia. Se a coleção mudar antes, mostramos a prévia atualizada para você confirmar de novo.
          </p>
        </div>
      </div>
    </div>
  );
}

function VerdictNotice({ verdict, preview }: { verdict: ReturnType<typeof previewVerdict>; preview: BinderPreview }) {
  const text =
    verdict === "exists"
      ? "Esta coleção já tem um fichário. Recarregue a página para abri-lo."
      : verdict === "archived"
        ? "A coleção está arquivada. Reative-a para montar o fichário."
        : verdict === "not_eligible"
          ? "O local padrão desta coleção não é do tipo Fichário. Ajuste em Ajustes → Onde guardo."
          : verdict === "too_large"
            ? `Esta coleção tem ${formatCount(preview.allocationsTotal)} cartas — acima do limite atual de ${formatCount(preview.maxAllocations)} para montar de uma vez. Nada foi alterado.`
            : "Não há uma montagem disponível para esta coleção.";
  return (
    <div className={styles.notice} data-tone="warning" role="status">
      <AlertTriangle className="h-4 w-4" aria-hidden="true" />
      <p>{text}</p>
    </div>
  );
}
