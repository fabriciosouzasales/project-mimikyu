# ADR-020 — User Profile and Username Identity Model

| Campo | Valor |
|--------|-------|
| **ADR** | ADR-020 |
| **Título** | User Profile and Username Identity Model |
| **Status** | Aprovado |
| **Data** | 2026-07-25 |
| **Decisores** | Fabrício Sales |
| **Decisão** | `public.user_profile` é uma entidade separada de `auth.users`, relacionada 1:1, guardando os dados básicos de perfil e identidade do usuário. Todo usuário possui um `username` público, único e estável — o próprio usuário não pode alterá-lo depois de criado. `display_name` é editável a qualquer momento. Correção administrativa de `username` é reconhecida como necessidade futura, mas só será desenhada quando existir um modelo de papéis e permissões aprovado. O MVP aceita cadastro só por e-mail/senha; login social exigirá um fluxo de onboarding ainda não implementado. |
| **Documentos Relacionados** | `ADR-019-web-application-as-primary-interface.md`, `../05-modelo-de-dados.md`, `../standards/STD-001-database-standards.md` |

---

# Context

O ADR-019 decidiu a stack do frontend (React/Next.js + Supabase) e identificou `user_profile` como modelagem pendente, sem decidir sua forma. Com o cadastro real via Supabase Auth já em uso, Fabrício percebeu a ausência de qualquer gestão de perfil associada — este ADR fecha essa lacuna, definindo a identidade de perfil do usuário, independente da autenticação em si.

Detalhes de implementação (estrutura de `avatar_path`, bucket de Storage, regex de validação, lista de termos reservados, políticas de RLS, numeração de Queries) não fazem parte desta decisão — ficam registrados em `05-modelo-de-dados.md`.

---

# Decision

## `user_profile` como entidade separada de `auth.users`

A autenticação (e-mail, senha, sessão) permanece inteiramente gerida pelo Supabase Auth (`auth.users`). Uma tabela própria, `public.user_profile`, relacionada 1:1 (`id` compartilhado com `auth.users.id`), guarda os **dados básicos de perfil e identidade do usuário** — nome de exibição, username e avatar. Preferências, papéis e permissões **não fazem parte do escopo desta tabela nem desta decisão**: poderão ser modelados futuramente como novos atributos de `user_profile` ou como entidades relacionadas próprias, conforme a necessidade concreta quando o módulo de papéis e permissões for proposto — este ADR não antecipa essa forma. Nenhuma informação de perfil é armazenada em `auth.users` ou em seus metadados como fonte de verdade permanente.

## `@username` como identidade pública, única e estável

Todo usuário possui um `username` público, exigido no cadastro, único em toda a plataforma — a identidade que a plataforma usará futuramente para compartilhamento de coleções, perfis públicos, URLs amigáveis e recursos sociais, mesmo que nenhuma dessas telas exista ainda. Por ser uma identidade pública com esse horizonte de uso, é **estável por padrão**: o próprio usuário não pode alterá-lo depois de criado.

## `display_name` como dado editável

Diferente do `username`, o nome de exibição (`display_name`) é puramente cosmético e pode ser alterado pelo usuário a qualquer momento, sem as restrições de estabilidade do `username`.

## Imutabilidade do username e correção administrativa futura

Nesta fase não existe nenhum mecanismo de correção de `username` — nem para o usuário, nem para um administrador. Uma função administrativa controlada para correção pontual é reconhecida como necessidade futura, mas **só será desenhada quando existir um modelo de papéis e permissões administrativas aprovado** — pertencerá ao mesmo módulo de Identidade e Acesso (mesmo milhar de numeração, ver STD-001), não abrirá um módulo novo.

## Cadastro restrito a e-mail/senha no MVP

O MVP aceita apenas cadastro por e-mail/senha. Login social (OAuth) fica fora de escopo por ora.

## Onboarding futuro necessário para OAuth

Esta arquitetura assume que o `username` é coletado no próprio formulário de cadastro, via metadados enviados ao Supabase Auth — o que só funciona quando a aplicação controla esse formulário, como no fluxo e-mail/senha. Um provedor OAuth não pergunta `username`: se/quando login social for adicionado, será necessário um fluxo de **onboarding pós-login** ("escolha seu @username") antes de liberar acesso completo a contas criadas via provedor social. Reconhecida desde já como limitação estrutural, não um detalhe a resolver de improviso quando OAuth for proposto.

---

# Consequences

## Benefícios

- Separa autenticação (Supabase Auth) de identidade de negócio (`user_profile`), permitindo evoluir uma sem acoplar à outra.
- Estabelece, desde o primeiro usuário real, uma identidade pública estável — evita migrar URLs, referências ou integrações sociais futuramente por conta de um username que muda livremente.
- Mantém `user_profile` deliberadamente enxuta nesta fase (identidade básica apenas), sem comprometer previamente como papéis/permissões serão modelados — decisão adiada para quando houver necessidade concreta e escopo próprio aprovado.

## Restrições / Pendências

- Nenhuma correção de username existe hoje, nem para o usuário nem para um administrador — um erro de digitação no cadastro é permanente até o módulo de papéis/permissões existir.
- Login social não é suportado no MVP; adicioná-lo exige o fluxo de onboarding descrito acima, ainda não implementado.
- Onde papéis, permissões e preferências serão fisicamente modelados (coluna em `user_profile` vs. tabela relacionada própria) é uma decisão em aberto, deliberadamente não antecipada por este ADR.
- Detalhes de implementação (`avatar_path`, bucket, regex, lista de reservados, RLS, numeração de Queries) ficam em `05-modelo-de-dados.md`, não neste ADR.

---

# Alternatives Considered

## Estender `auth.users` diretamente (sem tabela própria)

Rejeitada. Misturaria dado de autenticação (gerido pelo Supabase) com dado de negócio (gerido pela aplicação), dificultando evolução futura e violando a separação de camadas já registrada em ADR-019.

## Permitir troca de username pelo próprio usuário

Rejeitada por Fabrício. Uma identidade pública que muda livremente enfraquece qualquer recurso futuro construído sobre ela — a estabilidade é o requisito central desta decisão.

## Coletar username só depois do cadastro, sem distinguir provedor

Considerada, não adotada agora: adicionaria uma etapa extra ao fluxo de e-mail/senha sem necessidade concreta hoje (o MVP não tem OAuth). Documentada como o desenho a adotar quando login social for proposto, não aplicada prematuramente ao único fluxo existente.

---

# Related Documents

- `ADR-019-web-application-as-primary-interface.md`
- `../05-modelo-de-dados.md`
- `../standards/STD-001-database-standards.md`

---

# Revision History

| Versão | Descrição |
|---------|-----------|
| 1.0 | Criação — formaliza `user_profile` separado de `auth.users`, contendo apenas dados básicos de perfil e identidade (username, display_name, avatar); papéis, permissões e preferências ficam explicitamente fora do escopo desta tabela e desta decisão, a modelar futuramente como atributos ou entidades relacionadas quando houver necessidade concreta. `username` definido como identidade pública única e estável, `display_name` editável, correção administrativa futura condicionada a papéis/permissões aprovados, e limitação de MVP a e-mail/senha com onboarding futuro necessário para OAuth. Complementa ADR-019. |
