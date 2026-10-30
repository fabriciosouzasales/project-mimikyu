import type { ReceivedInvite } from "./sharing";

/**
 * Estado dos convites recebidos (V1-12 SHARED EXPERIENCE & GLOBAL INBOX-01),
 * compartilhado entre o Inbox do cabeçalho e a caixa de convites de Minhas
 * coleções — um só estado, as mesmas ações.
 *
 * Sem polling: lê ao montar, ao abrir o Inbox e ao recuperar o foco da aba,
 * sempre respeitando `ttlMs` (a navegação remonta o cabeçalho; o TTL evita
 * uma leitura por página). Leituras simultâneas viram uma só. A página que já
 * leu os convites no servidor semeia o estado (`seed`) sem nova ida ao banco.
 *
 * Puro e testável: o leitor e o relógio são injetados.
 */
export type InvitesSnapshot = {
  /** `null` = ainda não lido. */
  invites: ReceivedInvite[] | null;
  /** Momento da última leitura bem-sucedida (ou semente). */
  loadedAt: number;
  loading: boolean;
};

export type InvitesStore = {
  getSnapshot: () => InvitesSnapshot;
  subscribe: (listener: () => void) => () => void;
  /** Lê de novo se o estado tiver mais que `ttlMs` (ou sempre, com `force`). */
  refresh: (options?: { force?: boolean }) => Promise<void>;
  /** Convites já lidos no servidor pela página atual. */
  seed: (invites: ReceivedInvite[]) => void;
  /** Convite respondido (aceito, recusado ou já inexistente): sai da lista na hora. */
  remove: (membershipId: string) => void;
};

export const INVITES_TTL_MS = 30_000;

export function createInvitesStore(
  read: () => Promise<ReceivedInvite[] | null>,
  { ttlMs = INVITES_TTL_MS, now = () => Date.now() }: { ttlMs?: number; now?: () => number } = {},
): InvitesStore {
  let snapshot: InvitesSnapshot = { invites: null, loadedAt: 0, loading: false };
  let inflight: Promise<void> | null = null;
  // Convites respondidos nesta sessão de página: uma leitura que já estava em
  // voo antes da resposta não pode trazê-los de volta.
  const answered = new Set<string>();
  const listeners = new Set<() => void>();

  const emit = (next: InvitesSnapshot) => {
    snapshot = next;
    for (const listener of listeners) listener();
  };

  const visible = (list: ReceivedInvite[]) => list.filter((invite) => !answered.has(invite.membershipId));

  return {
    getSnapshot: () => snapshot,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    refresh({ force = false } = {}) {
      if (inflight) return inflight;
      const fresh = snapshot.invites !== null && now() - snapshot.loadedAt < ttlMs;
      if (fresh && !force) return Promise.resolve();
      emit({ ...snapshot, loading: true });
      inflight = read()
        .catch(() => null)
        .then((list) => {
          inflight = null;
          // Falha de leitura: mantém o que já havia (nada some por um erro de rede).
          if (list === null) emit({ ...snapshot, loading: false });
          else emit({ invites: visible(list), loadedAt: now(), loading: false });
        });
      return inflight;
    },
    seed(invites) {
      emit({ invites: visible(invites), loadedAt: now(), loading: snapshot.loading });
    },
    remove(membershipId) {
      answered.add(membershipId);
      if (snapshot.invites === null) return;
      emit({ ...snapshot, invites: snapshot.invites.filter((invite) => invite.membershipId !== membershipId) });
    },
  };
}
