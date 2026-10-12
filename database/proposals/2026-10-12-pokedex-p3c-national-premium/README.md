# Pokédex P3c — Pokédex Nacional Premium (proposta)

| Campo | Valor |
|-------|-------|
| **Status** | 6135 **CONFIRMADO EXECUTADO** no LIVE em 2026-10-12 (migration `20261012232431`), promovida para `database/migrations/6135_create_get_pokedex_species_type_index.sql`; 6846 = PASS pós-aplicação. |
| **Data** | 2026-10-12 |
| **Escopo** | Tipos das espécies em lote para a galeria `/pokedex` (luz ambiente e chips de tipo nos cards). |

## Arquivos

| Ordem | Arquivo | Natureza |
|-------|---------|----------|
| 1 | `6135_create_get_pokedex_species_type_index.sql` | Escrita (DDL aditiva): cria `public.get_pokedex_species_type_index(p_language text default 'pt-BR')`. |
| 2 | `6846_validate_get_pokedex_species_type_index.sql` | Validação em transação com `ROLLBACK` (nenhuma escrita persiste). Esperado: `NOTICE 6846 PASS (linhas: N, com dois tipos: M)`. |

## O que a 6135 faz

Uma linha por espécie ativa com perfil `IMPORTED`: número nacional, tipo primário (código + rótulo) e tipo secundário (código + rótulo, ou nulo), lidos da forma padrão (`pokemon_species_profile.default_form_id` → `pokemon_form_type`). Rótulos no idioma pedido com recuo para `en`.

- **Aditiva**: não altera nenhuma função existente (6131/6132/6133/6134 intactas) nem tabelas.
- **Segurança**: `SECURITY DEFINER`, `SET search_path = ''`, objetos qualificados, exige `auth.uid()` (erro `28000` sem sessão), valida o idioma (`22023`), `EXECUTE` só para `authenticated` (revogado de `PUBLIC` e `anon`). Só expõe dado de catálogo público — nada administrativo nem por usuário.
- **Performance**: uma leitura em lote (~1.025 linhas, 5 colunas curtas), paginada pelo frontend no teto de 1.000 linhas do PostgREST — sem N+1.

## Dependência do frontend

`web/lib/pokedex/queries.ts` → `getPokedexSpeciesTypeIndex`. Enquanto a 6135 não existir no LIVE, a chamada recebe `PGRST202`, registra um `console.warn` e devolve `null`: a galeria funciona normalmente, com cards no tom neutro e sem chips de tipo. Nenhuma outra falha derruba a página (degrada para `null`).

## Procedimento (após autorização)

1. Executar a 6135 no SQL Editor do LIVE.
2. Executar a 6846 e confirmar `6846 PASS`.
3. Recarregar `/pokedex` e conferir luz por tipo e chips (ex.: #0001 Planta/Venenoso, #0025 Elétrico).
4. Só então promover a 6135 para `database/migrations/` como CONFIRMADO EXECUTADO.

## Ensaio no LIVE (2026-10-12)

6135 + 6846 (ambas verbatim; sha256 `e08662a4…68f4` e `a6d0883e…17ba`) numa única transação, mais um bloco final de verificações e encerramento por exceção (transação abortada, rollback integral):

- **Resultado: 6846 PASS** — 1.025 linhas (= espécies ativas com perfil IMPORTED), sem duplicidade; 526 com dois tipos (= 1.551 vínculos de tipo − 1.025 primários); #1 GRASS/POISON "Planta", #25 ELECTRIC sem secundário, #1 "Grass" em `en`; amostra de 17 espécies idêntica à ficha (6133).
- **Permissões reais**: sem sessão → 28000; `anon` (role real) → 42501; `authenticated` não-admin e administrador (`admin_user`) → 1.025 linhas; sem grant a PUBLIC; `SECURITY DEFINER` com `search_path=""`.
- **Contratos existentes**: hash das 33 funções `*pokedex*` (definição + ACL) idêntico antes, durante e depois.
- **Resíduo zero** após o rollback: função e comentário ausentes; espécies 1.025, perfis 1.025, `pokemon_form_type` 1.551, tipos 18, cartas 21.195 e ledger de migrations (418) inalterados.

## Aplicação definitiva (2026-10-12)

- 6135 conferida idêntica à ensaiada (sha256 `e08662a4…68f4`) e aplicada via `apply_migration` (`20261012232431 6135_create_get_pokedex_species_type_index`; ledger 418 → 419).
- **6846 PASS** sobre a função aplicada (execução com rollback, sem resíduo): 1.025 linhas sem duplicidade, 526 com dois tipos, rótulos pt-BR/en corretos, amostra de 17 espécies idêntica à ficha (6133).
- Permissões: ACL `{postgres=X/postgres,authenticated=X/postgres}`; `anon` real → 42501; usuário comum e administrador leem 1.025. Security Advisor: só o aviso geral `authenticated_security_definer_function_executable`, esperado pelo contrato (igual às demais RPCs da Pokédex); nenhum aviso de `anon`.
- Preservação: hash das 33 funções `*pokedex*` existentes inalterado; espécies 1.025, perfis 1.025, `pokemon_form_type` 1.551, tipos 18, cartas 21.195.

## Rollback

`drop function if exists public.get_pokedex_species_type_index(text);` — o frontend volta ao tom neutro sozinho.
