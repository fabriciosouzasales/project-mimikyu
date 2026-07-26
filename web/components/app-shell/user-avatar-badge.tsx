import Link from "next/link";

/** Avatar do usuário logado, exibido no cabeçalho ao lado do alternador de tema — leva a /perfil. */
export function UserAvatarBadge({
  avatarUrl,
  initial,
}: {
  avatarUrl: string | null;
  initial: string;
}) {
  return (
    <Link
      href="/perfil"
      aria-label="Meu perfil"
      className="flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden rounded-full border border-border bg-surface-muted text-xs font-medium text-muted-foreground transition-colors hover:border-primary"
    >
      {avatarUrl ? (
        // Avatar hospedado no Supabase Storage — sem images.remotePatterns
        // configurado no projeto, por isso <img> em vez de next/image (mesma
        // decisão já registrada para o avatar em /perfil).
        // eslint-disable-next-line @next/next/no-img-element
        <img src={avatarUrl} alt="" className="h-full w-full object-cover" />
      ) : (
        <span aria-hidden>{initial}</span>
      )}
    </Link>
  );
}
