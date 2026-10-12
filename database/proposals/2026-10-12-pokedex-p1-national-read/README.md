# Pokédex P1 — leitura da Pokédex Nacional

| Arquivo | Papel | Status |
|---|---|---|
| `6131_create_pokedex_national_read_functions.sql` | Cria `get_pokedex_generations()` e `get_pokedex_national_species(p_query, p_generation)` | **CONFIRMADO EXECUTADO** 2026-10-12 (v1.0) — promovida para `database/migrations/6131_create_pokedex_national_read_functions.sql`; este arquivo fica como registro da proposta |
| `6841_validate_pokedex_national_read_functions.sql` | Validação pós-execução (BEGIN/ROLLBACK) | **v1.1 executada — `6841 PASS`** |

**Por quê.** As tabelas `pokemon_species`, `pokemon_generation` e `pokemon_region` têm RLS sem policy e nenhum GRANT para `authenticated`. A Pokédex (D2: todo usuário autenticado, sem anônimo) precisa ler espécies e gerações sem abrir essas tabelas. Solução: duas funções `SECURITY DEFINER` de contrato fechado, mesmo padrão de `search_cards()` (Query 4032). Nenhuma tabela, policy ou GRANT de tabela muda.

**6841 v1.1 (ajustada antes da execução).** A v1.0 cobria anon e usuário autenticado; a v1.1 acrescentou o perfil administrador (id real de `admin_user` só como claim de sessão, nada gravado), a checagem do contrato de saída exato e a cobertura de todas as tabelas do catálogo Pokémon (`pokemon_species`, `pokemon_generation`, `pokemon_region`, `pokemon_species_external_reference`, `pokedex`, `pokedex_position`).

**Evidência da execução (LIVE, 2026-10-12).**
- `6841 PASS`: endurecimento das 2 funções; sem sessão → 28000; usuário comum → 1.025 espécies, 9 gerações, busca e filtro corretos; administrador → mesmo contrato, sem leitura direta das tabelas; anon → sem EXECUTE.
- Postcheck contra o baseline capturado antes da execução: contagens (species 1025, gen 9, region 11, pokedex 1, position 1025, external_reference 1025, card_primary_species 17.648, collection 0, inventory 3, physical_card 0), hash das 1.025 espécies, hash de ACL das tabelas de `public` e hash das policies de `public` — todos idênticos.
- Security Advisor: só o aviso esperado `authenticated_security_definer_function_executable` para as 2 funções (mesmo caso intencional de `search_cards`); nenhum aviso de `anon`.

**Rollback** (se necessário): `drop function public.get_pokedex_national_species(text, integer); drop function public.get_pokedex_generations();` — a interface volta a mostrar o estado de erro da Pokédex, nada mais é afetado.
