# Pokédex P3b — página de detalhes da espécie

| Arquivo | Papel | Status |
|---|---|---|
| `6134_create_get_pokedex_species_hero_artwork.sql` | Função de leitura `get_pokedex_species_hero_artwork(n)`: caminho do PNG original (475 px) + WebP de uma espécie, para o palco da ficha | **CONFIRMADO EXECUTADO** 2026-10-12 (v1.0, migration `20261012212558`) — promovida para `database/migrations/6134_create_get_pokedex_species_hero_artwork.sql`; este arquivo fica como registro da proposta |
| `6845_validate_get_pokedex_species_hero_artwork.sql` | Validação (BEGIN/ROLLBACK): segurança, contrato, casos-limite e cobertura | `6845 PASS` no ensaio e após a aplicação (cobertura 1.025/1.025; rollback, sem resíduo) |

## Dependência da interface

A rota `/pokedex/[numero]` funciona **com ou sem** a 6134:

- **Sem a 6134**: o palco usa o WebP de 320 px de `get_pokedex_species_detail` (6133). A chamada à função ausente falha uma vez por requisição e é tratada como "sem arte original" (log de aviso no servidor, sem erro para o usuário).
- **Com a 6134**: o palco usa `srcset` com o WebP 320w e o PNG 475w; o navegador escolhe pelo tamanho exibido × densidade da tela.

Nada mais depende dela. A galeria, a 6131, a 6132 e a 6133 não mudam.

## Segurança

- Função `SECURITY DEFINER`, `search_path = ''`, nomes qualificados, exige `auth.uid()` (28000 sem sessão).
- `EXECUTE` só para `authenticated`; revogado de `public` e `anon`.
- Devolve só caminhos dentro do bucket público `pokemon-species-artwork` e as dimensões; o front valida o formato do caminho antes de montar a URL.

## Execução

1. Ensaio: 6134 + 6845 na mesma transação com `ROLLBACK` → `6845 PASS`, zero resíduo.
2. 6134 no LIVE (migration `20261012212558`, conteúdo idêntico ao ensaiado) → 6845 `PASS (cobertura: 1025 espécies)` → promovida para `database/migrations/`.

**Postcheck (somente leitura):** ACL `{postgres=X/postgres,authenticated=X/postgres}` — `anon` e `public` sem EXECUTE; 1.025/1.025 caminhos PNG (`original-*.png`) e WebP (`w320-*.webp`) no formato esperado; espécies, imagens, perfis, funções da 6133, `get_pokedex_national_species`, `card_asset` e vínculos carta → espécie idênticos ao baseline. Security Advisor: a função aparece só no aviso geral `authenticated_security_definer_function_executable`, junto das demais RPCs autenticadas (esperado pelo contrato); nenhum aviso de `anon`.

**Pendente para homologação:** lint, build e conferência visual locais (Fabrício).
