"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useId, useRef, useState, useTransition } from "react";
import { Check, Copy, Globe2, Loader2, Lock, RotateCcw, Share2, ShieldCheck, UserPlus, X } from "lucide-react";
import {
  inviteCollectionMember,
  readCollectionSharing,
  removeCollectionMember,
  setCollectionVisibility,
} from "@/app/colecoes/compartilhar/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { Input } from "@/components/ui/input";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import {
  MEMBER_LIMIT,
  type ShareMember,
  type SharingFailure,
  type SharingState,
  VIEWER_ROLE_HINT,
  VIEWER_ROLE_LABEL,
  type Visibility,
  activeOrPending,
  inviteOutcomeMessage,
  normalizeUsername,
  publicBinderHref,
  sharingFailureMessage,
  statusLabel,
} from "@/lib/colecoes/sharing";
import acervoStyles from "../acervo/acervo.module.css";
import addStyles from "../acervo/acervo-add.module.css";
import manageStyles from "../colecoes/collection-manage.module.css";
import styles from "./share.module.css";

/**
 * "Compartilhar" (V1-12 COLLECTION-SHARING-FOUNDATION-01) — botão ao lado de
 * "Ajustes" no topo da coleção, só para o titular. Abre o mesmo painel
 * lateral do Gerenciar (drawer do Meu acervo):
 *
 * 1. Convidar pelo nome de usuário exato (5303) — participante VIEWER.
 * 2. Quem pode ver: participantes, convites enviados e recusados, com
 *    remover / cancelar / convidar de novo (5305/5303).
 * 3. Visibilidade: privada ↔ pública, sempre por confirmação explícita
 *    (5307). Pública = vitrine do FICHÁRIO (5317/5318), sem galeria nem
 *    progresso; mostra o link público do fichário para copiar.
 *
 * O painel lê o estado do banco ao abrir (5308) e relê depois de cada ação:
 * nada aqui decide permissão. Sem as funções no banco, o painel explica que o
 * compartilhamento ainda não está disponível — a página da coleção não muda.
 */
export function CollectionShareButton({ collectionId, collectionName }: { collectionId: string; collectionName: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className={manageStyles.settingsButton} onClick={() => setOpen(true)} aria-haspopup="dialog">
        <Share2 className="h-4 w-4" aria-hidden="true" />
        Compartilhar
      </button>
      {open ? <SharePanel collectionId={collectionId} collectionName={collectionName} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

type Load = { status: "loading" } | { status: "error"; reason: SharingFailure } | { status: "ready"; state: SharingState };
type Notice = { tone: "success" | "error" | "warning"; text: string } | null;

function SharePanel({ collectionId, collectionName, onClose }: { collectionId: string; collectionName: string; onClose: () => void }) {
  const restoreFocus = useRestoreFocus();
  const router = useRouter();
  const [, startRefresh] = useTransition();
  const [load, setLoad] = useState<Load>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<Notice>(null);

  useEffect(() => {
    let alive = true;
    setLoad({ status: "loading" });
    readCollectionSharing({ collectionId })
      .then((result) => {
        if (!alive) return;
        setLoad(result.ok ? { status: "ready", state: result.state } : { status: "error", reason: result.reason });
      })
      .catch(() => alive && setLoad({ status: "error", reason: "unknown" }));
    return () => {
      alive = false;
    };
  }, [attempt, collectionId]);

  const reload = useCallback(() => setAttempt((n) => n + 1), []);

  /** Relê o painel depois de uma escrita (o banco é a verdade) e avisa a página. */
  const settle = useCallback(
    async (next: Notice) => {
      setNotice(next);
      const result = await readCollectionSharing({ collectionId }).catch(() => null);
      if (result?.ok) setLoad({ status: "ready", state: result.state });
      startRefresh(() => router.refresh());
    },
    [collectionId, router],
  );

  const state = load.status === "ready" ? load.state : null;

  return (
    <DialogPrimitive.Root open onOpenChange={(next) => !next && !busy && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={acervoStyles.overlay} />
        <DialogPrimitive.Content
          className={`${acervoStyles.drawer} ${manageStyles.panel}`}
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => busy && event.preventDefault()}
          onPointerDownOutside={(event) => busy && event.preventDefault()}
          onCloseAutoFocus={restoreFocus}
        >
          <div className={acervoStyles.drawerHeader}>
            <div className="min-w-0">
              <DialogPrimitive.Title className={addStyles.panelTitle}>Compartilhar coleção</DialogPrimitive.Title>
              <p className="truncate text-xs text-muted-foreground">{collectionName}</p>
            </div>
            <DialogPrimitive.Close
              disabled={busy}
              className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring disabled:opacity-40"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>

          <div className={manageStyles.body}>
            <div className={styles.live} role="status" aria-live="polite">
              {notice ? <InlineFeedback tone={notice.tone}>{notice.text}</InlineFeedback> : null}
            </div>

            {load.status === "loading" ? (
              <div className={styles.skeleton} aria-busy="true" aria-label="Carregando o compartilhamento">
                <span />
                <span />
                <span />
              </div>
            ) : load.status === "error" ? (
              <div className={styles.readError} role="alert">
                <p>{load.reason === "unavailable" ? sharingFailureMessage("unavailable") : "Não conseguimos carregar o compartilhamento agora."}</p>
                <Button variant="outline" size="sm" onClick={reload}>
                  <RotateCcw className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />
                  Tentar de novo
                </Button>
              </div>
            ) : state ? (
              <>
                <InviteSection
                  collectionId={collectionId}
                  state={state}
                  busy={busy}
                  onBusy={setBusy}
                  onDone={settle}
                />
                <MembersSection collectionId={collectionId} state={state} busy={busy} onBusy={setBusy} onDone={settle} />
                <VisibilitySection collectionId={collectionId} state={state} busy={busy} onBusy={setBusy} onDone={settle} />
                <p className={styles.privacy}>
                  <ShieldCheck className="h-4 w-4 shrink-0" aria-hidden="true" />
                  <span>
                    Nunca é compartilhado: o resto do seu acervo, onde você guarda as cartas, valores pagos, favoritos, lista de
                    desejos e suas outras coleções.
                  </span>
                </p>
              </>
            ) : null}
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

type SectionProps = {
  collectionId: string;
  state: SharingState;
  busy: boolean;
  onBusy: (busy: boolean) => void;
  onDone: (notice: Notice) => Promise<void>;
};

function InviteSection({ collectionId, state, busy, onBusy, onDone }: SectionProps) {
  const inputId = useId();
  const helpId = useId();
  const errorId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [value, setValue] = useState("");
  const [error, setError] = useState<string | null>(null);
  const full = activeOrPending(state.members) >= MEMBER_LIMIT;
  const blocked = state.archived || full;

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (busy || blocked) return;
    const username = normalizeUsername(value);
    if (!username) {
      setError(sharingFailureMessage("invalid_username"));
      inputRef.current?.focus();
      return;
    }
    setError(null);
    onBusy(true);
    const result = await inviteCollectionMember({ collectionId, username }).catch(() => ({ ok: false, reason: "unknown" }) as const);
    onBusy(false);
    if (!result.ok) {
      setError(sharingFailureMessage(result.reason));
      inputRef.current?.focus();
      return;
    }
    setValue("");
    await onDone({ tone: "success", text: inviteOutcomeMessage(result.outcome, result.member) });
  };

  return (
    <section className={manageStyles.section} aria-labelledby="share-invite">
      <h3 id="share-invite" className={manageStyles.sectionTitle}>
        Convidar alguém
      </h3>
      <p className={styles.lead}>
        A pessoa recebe o convite em <strong>Minhas coleções</strong> e, ao aceitar, vê esta coleção como{" "}
        <strong>{VIEWER_ROLE_LABEL.toLowerCase()}</strong>: {VIEWER_ROLE_HINT.charAt(0).toLowerCase() + VIEWER_ROLE_HINT.slice(1)}
      </p>
      <form className={styles.inviteForm} onSubmit={submit} noValidate>
        <label htmlFor={inputId} className={styles.label}>
          Nome de usuário
        </label>
        <div className={styles.inviteRow}>
          <div className={styles.handle}>
            <span className={styles.at} aria-hidden="true">
              @
            </span>
            <Input
              ref={inputRef}
              id={inputId}
              value={value}
              onChange={(event) => {
                setValue(event.target.value);
                if (error) setError(null);
              }}
              placeholder="colecionador"
              autoComplete="off"
              autoCapitalize="none"
              spellCheck={false}
              maxLength={21}
              disabled={busy || blocked}
              invalid={error !== null}
              aria-describedby={error ? `${helpId} ${errorId}` : helpId}
              className={styles.handleInput}
            />
          </div>
          <Button type="submit" disabled={busy || blocked || value.trim() === ""} aria-busy={busy || undefined}>
            {busy ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" /> : <UserPlus className="mr-1.5 h-4 w-4" aria-hidden="true" />}
            Convidar
          </Button>
        </div>
        <p id={helpId} className={styles.help}>
          {state.archived
            ? "Coleção arquivada: reative-a para convidar alguém."
            : full
              ? `Limite de ${MEMBER_LIMIT} pessoas entre participantes e convites.`
              : "Use o nome exato do perfil da pessoa no MMKYU — sem buscas, para ninguém ser encontrado por acaso."}
        </p>
        {error ? (
          <p id={errorId} className={styles.error} role="alert">
            {error}
          </p>
        ) : null}
      </form>
    </section>
  );
}

function MembersSection({ collectionId, state, busy, onBusy, onDone }: SectionProps) {
  const [confirming, setConfirming] = useState<string | null>(null);

  const remove = async (member: ShareMember) => {
    onBusy(true);
    const result = await removeCollectionMember({ collectionId, membershipId: member.membershipId }).catch(
      () => ({ ok: false, reason: "unknown" }) as const,
    );
    onBusy(false);
    setConfirming(null);
    const who = member.displayName;
    if (!result.ok) {
      await onDone({ tone: result.reason === "not_found" ? "warning" : "error", text: sharingFailureMessage(result.reason) });
      return;
    }
    await onDone({
      tone: "success",
      text:
        member.status === "ACTIVE"
          ? `${who} não tem mais acesso a esta coleção.`
          : member.status === "PENDING"
            ? `Convite para ${who} cancelado.`
            : `${who} saiu da lista.`,
    });
  };

  const reinvite = async (member: ShareMember) => {
    onBusy(true);
    const result = await inviteCollectionMember({ collectionId, username: member.username }).catch(
      () => ({ ok: false, reason: "unknown" }) as const,
    );
    onBusy(false);
    await onDone(result.ok ? { tone: "success", text: inviteOutcomeMessage(result.outcome, result.member) } : { tone: "error", text: sharingFailureMessage(result.reason) });
  };

  const count = state.members.filter((m) => m.status === "ACTIVE").length;

  return (
    <section className={manageStyles.section} aria-labelledby="share-members">
      <h3 id="share-members" className={manageStyles.sectionTitle}>
        Quem pode ver
      </h3>
      <ul className={styles.members} aria-label="Pessoas desta coleção">
        <li className={styles.member} data-owner="">
          <span className={styles.avatar} aria-hidden="true">
            <Lock className="h-3.5 w-3.5" />
          </span>
          <span className={styles.memberText}>
            <span className={styles.memberName}>Você</span>
            <span className={styles.memberSub}>Titular — único que altera a coleção</span>
          </span>
        </li>
        {state.members.map((member) => {
          const isConfirming = confirming === member.membershipId;
          return (
            <li key={member.membershipId} className={styles.member} data-status={member.status.toLowerCase()}>
              <span className={styles.avatar} aria-hidden="true">
                {member.displayName.charAt(0).toUpperCase()}
              </span>
              <span className={styles.memberText}>
                <span className={styles.memberName}>{member.displayName}</span>
                <span className={styles.memberSub}>
                  @{member.username} · <span className={styles.chip} data-status={member.status.toLowerCase()}>{statusLabel(member.status)}</span>
                </span>
              </span>
              <span className={styles.memberActions}>
                {isConfirming ? (
                  <>
                    <Button variant="destructive" size="sm" disabled={busy} onClick={() => void remove(member)}>
                      {member.status === "PENDING" ? "Cancelar convite" : "Remover acesso"}
                    </Button>
                    <Button variant="ghost" size="sm" disabled={busy} onClick={() => setConfirming(null)}>
                      Voltar
                    </Button>
                  </>
                ) : (
                  <>
                    {member.status === "DECLINED" && !state.archived ? (
                      <Button variant="outline" size="sm" disabled={busy} onClick={() => void reinvite(member)}>
                        Convidar de novo
                      </Button>
                    ) : null}
                    <Button
                      variant="ghost"
                      size="sm"
                      disabled={busy}
                      onClick={() => setConfirming(member.membershipId)}
                      aria-label={
                        member.status === "ACTIVE"
                          ? `Remover o acesso de ${member.displayName}`
                          : member.status === "PENDING"
                            ? `Cancelar o convite de ${member.displayName}`
                            : `Tirar ${member.displayName} da lista`
                      }
                    >
                      {member.status === "ACTIVE" ? "Remover" : member.status === "PENDING" ? "Cancelar" : "Tirar"}
                    </Button>
                  </>
                )}
              </span>
            </li>
          );
        })}
      </ul>
      <p className={manageStyles.note}>
        {count === 0
          ? state.members.length === 0
            ? "Ninguém além de você vê esta coleção."
            : "Ninguém aceitou ainda — os convites ficam esperando a resposta."
          : count === 1
            ? "1 pessoa pode ver esta coleção. Remover o acesso vale na hora."
            : `${count} pessoas podem ver esta coleção. Remover o acesso vale na hora.`}
      </p>
    </section>
  );
}

function VisibilitySection({ collectionId, state, busy, onBusy, onDone }: SectionProps) {
  const [choice, setChoice] = useState<Visibility>(state.visibility);
  const [copied, setCopied] = useState(false);
  const groupId = useId();
  const changed = choice !== state.visibility;

  useEffect(() => setChoice(state.visibility), [state.visibility]);

  const apply = async () => {
    if (!changed) return;
    onBusy(true);
    const result = await setCollectionVisibility({ collectionId, visibility: choice }).catch(() => ({ ok: false, reason: "unknown" }) as const);
    onBusy(false);
    if (!result.ok) {
      setChoice(state.visibility);
      await onDone({ tone: "error", text: sharingFailureMessage(result.reason) });
      return;
    }
    await onDone({
      tone: "success",
      text:
        result.visibility === "PUBLIC"
          ? "Fichário publicado: qualquer pessoa com o link pode folhear o fichário desta coleção."
          : "Fichário fora do ar: o link público parou de funcionar. Só você e quem você convidou continuam vendo.",
    });
  };

  const link = typeof window === "undefined" ? publicBinderHref(collectionId) : `${window.location.origin}${publicBinderHref(collectionId)}`;

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2400);
    } catch {
      setCopied(false);
    }
  };

  const options: { value: Visibility; title: string; text: string; icon: typeof Lock; disabled: boolean }[] = [
    { value: "PRIVATE", title: "Privada", text: "Só você e as pessoas que você convidar.", icon: Lock, disabled: false },
    {
      value: "PUBLIC",
      title: "Fichário público",
      text: "Qualquer pessoa com o link folheia o fichário desta coleção — capa e páginas, sem login e sem poder alterar nada.",
      icon: Globe2,
      disabled: state.archived && state.visibility !== "PUBLIC",
    },
  ];

  return (
    <section className={manageStyles.section} aria-labelledby="share-visibility">
      <h3 id="share-visibility" className={manageStyles.sectionTitle}>
        Visibilidade
      </h3>
      <div className={styles.options} role="radiogroup" aria-labelledby="share-visibility" id={groupId}>
        {options.map((option) => {
          const Icon = option.icon;
          const selected = choice === option.value;
          return (
            <label key={option.value} className={styles.option} data-selected={selected || undefined} data-disabled={option.disabled || undefined}>
              <input
                type="radio"
                name={`${groupId}-visibility`}
                value={option.value}
                checked={selected}
                disabled={busy || option.disabled}
                onChange={() => setChoice(option.value)}
              />
              <Icon className={styles.optionIcon} aria-hidden="true" />
              <span className={styles.optionText}>
                <span className={styles.optionTitle}>
                  {option.title}
                  {state.visibility === option.value ? <span className={styles.current}>atual</span> : null}
                </span>
                <span className={styles.optionSub}>{option.text}</span>
              </span>
            </label>
          );
        })}
      </div>
      {state.archived && state.visibility !== "PUBLIC" ? (
        <p className={manageStyles.note}>Coleção arquivada: reative-a para torná-la pública.</p>
      ) : null}
      {changed ? (
        <div className={styles.confirm}>
          <p>
            {choice === "PUBLIC"
              ? "Você vai publicar a visualização do fichário desta coleção: capa, nome e páginas, para qualquer pessoa com o link, sem login. Progresso, lista de cartas, seu acervo, seus locais e suas outras coleções continuam privados — bolsos de outras coleções aparecem vazios. Dá para despublicar quando quiser."
              : "Ao despublicar, o link público deixa de funcionar na hora. Quem você convidou continua vendo."}
          </p>
          <div className={styles.confirmActions}>
            <Button size="sm" disabled={busy} onClick={() => void apply()} aria-busy={busy || undefined}>
              {busy ? <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" aria-hidden="true" /> : null}
              {choice === "PUBLIC" ? "Publicar o fichário" : "Despublicar"}
            </Button>
            <Button variant="ghost" size="sm" disabled={busy} onClick={() => setChoice(state.visibility)}>
              Manter como está
            </Button>
          </div>
        </div>
      ) : state.visibility === "PUBLIC" ? (
        <div className={styles.linkRow}>
          <span className={styles.link} title={link}>
            {link.replace(/^https?:\/\//, "")}
          </span>
          <Button variant="outline" size="sm" onClick={() => void copy()} aria-live="polite">
            {copied ? <Check className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" /> : <Copy className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />}
            {copied ? "Link copiado" : "Copiar link"}
          </Button>
        </div>
      ) : null}
    </section>
  );
}
