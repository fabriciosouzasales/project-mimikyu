/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1710 - Seed Reserved Username
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Carga inicial de public.reserved_username — termos que nenhum
usuário pode reivindicar como username. Lista curada, revisável
a qualquer momento (basta um novo INSERT, sem exigir migration
de schema).

Regras de Negócio:
- Idempotente via ON CONFLICT (username) DO NOTHING.
- Valores já normalizados (minúsculas), consistente com a
  normalização aplicada a qualquer username real.
- v1.1 acrescenta "me" (rotas futuras como /me, /api/me,
  /profile/me) e "about" (rota institucional comum) — sugeridos
  por Fabrício após a execução original de 48 termos. O acréscimo
  já foi aplicado incrementalmente no banco; esta versão do
  arquivo consolida a lista canônica completa (50 termos) para
  que uma instalação nova nasça direto com o conjunto atual, sem
  precisar de uma segunda Query.
================================================================
*/

INSERT INTO public.reserved_username (username) VALUES
    ('admin'), ('administrator'), ('root'), ('superuser'),
    ('moderator'), ('mod'), ('support'), ('suporte'), ('ajuda'), ('help'),
    ('contato'), ('contact'), ('about'), ('official'), ('oficial'), ('mimikyu'),
    ('system'), ('sistema'), ('null'), ('undefined'),
    ('api'), ('www'), ('security'), ('seguranca'),
    ('staff'), ('owner'), ('dono'),
    ('test'), ('teste'), ('anonymous'), ('anonimo'), ('guest'), ('convidado'),
    ('user'), ('usuario'), ('users'), ('usuarios'), ('me'),
    ('profile'), ('perfil'), ('profiles'), ('perfis'),
    ('settings'), ('configuracoes'), ('config'),
    ('login'), ('signup'), ('signin'), ('logout'), ('cadastro')
ON CONFLICT (username) DO NOTHING;
