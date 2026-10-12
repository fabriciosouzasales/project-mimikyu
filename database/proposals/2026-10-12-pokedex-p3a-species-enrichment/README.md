# Pokédex P3a — fundação do enriquecimento das espécies

| Arquivo | Papel | Status |
|---|---|---|
| `6133_create_pokemon_species_enrichment_foundation.sql` | `pokemon_type` (18 tipos semeados), `pokemon_form` (só forma padrão), `pokemon_form_type`, `pokemon_species_profile`, `pokemon_species_text`; 3 funções admin; `get_pokedex_species_detail` | **CONFIRMADO EXECUTADO** 2026-10-12 (v1.0) — promovida para `database/migrations/6133_create_pokemon_species_enrichment_foundation.sql`; este arquivo fica como registro da proposta |
| `6844_validate_pokemon_species_enrichment_foundation.sql` | Validação (BEGIN/ROLLBACK) | **v1.1 — `6844 PASS` no ensaio e após a aplicação** (v1.0 falhou só por data de fixture no futuro, recusada corretamente pela 6133) |

Autoridade: emenda do AP-017 (`docs/02-architecture-principles.md` v1.10) e `ADR-011` v1.4. Importador: `web/scripts/import-pokemon-species-profile/` (DRY-RUN padrão, piloto = as 10 espécies da P2).

## Dados autorizados

- **Espécie:** classificação (genus), descrição selecionada, lendário/mítico/bebê.
- **Forma padrão:** tipo primário/secundário (ordem por slot), altura (dm), peso (hg).
- **Vocabulário:** 18 tipos, código canônico + rótulos `pt-BR`/`en`.

Fora: habilidades, estatísticas, golpes, evoluções, formas alternativas.

## Idioma e seleção de textos

- Idiomas importados: `pt-BR` (PokéAPI `pt-br`) e `en`. Cobertura real na carga integral: `pt-BR` 0/1.025, `en` 1.025/1.025 (ver "Resultado da carga").
- **Classificação:** a única entrada do idioma.
- **Descrição (critério determinístico):** por idioma, a entrada da versão de jogo **mais recente**, identificada pelo maior id de versão da PokéAPI (cresce com a ordem de lançamento). A versão escolhida fica gravada em `source_version`.
- **Normalização técnica (só formatação):** hífen suave + quebra → palavra unida; hífen suave isolado removido; `\n \f \r \t` → espaço; espaços repetidos colapsados; bordas aparadas. Grafia, maiúsculas e pontuação originais preservadas.
- **Leitura:** `get_pokedex_species_detail(n, idioma = 'pt-BR')` devolve, para cada texto, idioma pedido oficial > idioma pedido editorial MMKYU > `en` oficial > `en` editorial, com `*_language` e `*_is_official`. Rótulo de tipo: idioma pedido, senão `en`.
- Tradução editorial futura: `pokemon_species_text.origin = 'MMKYU_EDITORIAL'`, nunca apresentada como oficial e nunca apagada pela reimportação.
- Rótulos pt-BR dos tipos: Normal, Lutador, Voador, Venenoso, Terrestre, Pedra, Inseto, Fantasma, Aço, Fogo, Água, Planta, Elétrico, Psíquico, Gelo, Dragão, Sombrio, Fada — terminologia pt-BR usada pela The Pokémon Company (Pokémon GO / TCG); alteração = UPDATE do `labels`, sem mudar o código.

## Integridade e segurança

- Vínculo pela referência oficial (`pokemon_species_external_reference`); a forma padrão é resolvida espécie → `varieties[is_default]` → Pokémon com conferência de volta; nenhum id é presumido igual.
- Uma forma padrão por espécie (índice único parcial); `profile.default_form_id` com FK composta (forma + espécie); um Pokémon da PokéAPI não pode ser forma de duas espécies.
- Idempotência: sha256 do payload sem `retrieved_at` → `UNCHANGED` sem escrita; gravação serializada por espécie (advisory lock); falha nunca apaga perfil válido.
- Tabelas com RLS ligada, sem policy e sem GRANT; escrita só pelas funções admin (`is_admin()`), leitura do colecionador só por `get_pokedex_species_detail` (authenticated). `get_pokedex_national_species` não muda.
- Textos de terceiros com `THIRD_PARTY_UNLICENSED`.

## Ordem de execução — CONCLUÍDA (2026-10-12)

1. Ensaio: 6133 + 6844 na mesma transação com `ROLLBACK` → `6844 PASS`, zero resíduo.
2. 6133 no LIVE (migration `20261012191446`) → 6844 v1.1 `PASS` → promovida para `database/migrations/`.
3. Importador: `--pilot` (DRY-RUN, 10/10) → `--pilot --apply` (10 `IMPORTED_INSERTED`).
4. Carga integral em 4 lotes (`--only=<faixa> --apply`, sem `--force`).

## Resultado da carga (2026-10-12) — P3a encerrada

| Execução | Resultado |
|---|---|
| Piloto | 10 `IMPORTED_INSERTED` |
| Lote #0001–#0300 | 294 `IMPORTED_INSERTED`, 4 `SKIPPED_ALREADY_IMPORTED`, 2 `FAILED` (exit 2) |
| Recuperação `--only=208,210` | 2 `IMPORTED_RECOVERED` |
| Lote #0301–#0600 | 299 `IMPORTED_INSERTED`, 1 `SKIPPED_ALREADY_IMPORTED` |
| Lote #0601–#0900 | 298 `IMPORTED_INSERTED`, 2 `SKIPPED_ALREADY_IMPORTED` |
| Lote #0901–#1025 | 122 `IMPORTED_INSERTED`, 3 `SKIPPED_ALREADY_IMPORTED` |

- Conciliação dos relatórios: as 1.025 espécies tiveram exatamente uma gravação efetiva cada; nenhum reprocessamento de espécie já importada.
- Falhas #208 (Steelix) e #210 (Granbull): `RECORD_PROFILE: TypeError: fetch failed` — queda transitória da conexão local → Supabase durante a gravação (dados da PokéAPI completos, registro de falha confirmado, nada gravado pela metade). Reprocessadas sem `--force`; nenhuma mudança de código ou SQL.
- Política operacional adotada nos lotes 2–4: `exit 0` continua; `exit 1` interrompe; `exit 2` só continua se todas as falhas tiverem a assinatura transitória acima; sem novas tentativas automáticas. Script operacional mantido fora do repositório.
- Relógio local deve estar sincronizado: a 6133 recusa `retrieved_at` mais de 10 min no futuro (o piloto registrou ~2 min de adiantamento local).

**Estado final no LIVE (somente leitura):** 1.025 perfis `IMPORTED` (0 `FAILED`, 0 pendentes, 0 com erro; 1.023 com 1 tentativa e 2 com 2); 1.025 formas padrão, uma por espécie, vínculos íntegros; 1.551 vínculos de tipo (499 com um tipo, 526 com dois), sem duplicidade e sempre com slot 1; altura 1–200 dm e peso 1–9.999 hg; 71 lendários, 23 míticos e 19 bebês, sem combinação conflitante. `get_pokedex_species_detail` conferida em amostras das 9 gerações (imagem, tipos com rótulo pt-BR, medidas, textos com idioma efetivo e versão). Espécies, 2.050 imagens, `card_asset` e vínculos carta → espécie inalterados; fundação 6133 inalterada.

**Cobertura de idiomas:** `en` 1.025/1.025 classificação e 1.025/1.025 descrição (todas `SOURCE`, `THIRD_PARTY_UNLICENSED`); `pt-BR` 0/1.025 — a PokéAPI não publica textos `pt-br` para espécies. Nenhum texto editorial. Versões das descrições: shield 458, legends-arceus 241, violet 120, alpha-sapphire 114, ultra-moon 63, lets-go-eevee 29.

## Pendências não bloqueantes (editoriais)

- Tradução pt-BR da classificação e da descrição como `MMKYU_EDITORIAL` (a ficha mostra `en`, identificado como tal, até lá).
- Revisar descrições com contexto regional ou narrativo fora do padrão da Pokédex — ex.: #201 Unown (primeira pessoa), #493 Arceus e #905 Enamorus (menção a Hisui) — via texto editorial, sem reimportar.
- Direitos: textos de terceiros permanecem `THIRD_PARTY_UNLICENSED`; uso comercial depende de decisão futura.
