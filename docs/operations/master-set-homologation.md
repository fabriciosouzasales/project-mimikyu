# Homologação do Master Set (frontend + 5184–5199)

| Campo | Valor |
|---|---|
| **Status** | Preparado (2026-10-18, `5199-CLOSEOUT / FRONTEND-HOMOLOGATION-READINESS`; H9b acrescentado no `FRONTEND-HOMOLOGATION-GATE-01`). **Não executado.** |
| **Quem executa** | Fabrício, na própria máquina (`npm run dev`) e no SQL Editor. Escritas no LIVE só com autorização explícita registrada. |
| **Escopo** | Jornada completa do colecionador numa coleção de homologação controlada. Nenhuma coleção real é tocada. |

## 0. Ligar só na sua máquina

1. Em `web/.env.local` (nunca versionado), acrescente `NEXT_PUBLIC_MASTER_SET_LOCAL_HOMOLOGATION=1`.
2. Rode `npm run dev` em `web/`. A variável só tem efeito com `NODE_ENV=development`; `next build`/Vercel ignoram (`MASTER_SET_*_RELEASED` continuam `false`).
3. Ao terminar, apague a linha do `.env.local` e reinicie o `dev`.

## 1. Dados mínimos

- **Coleção de homologação "HOMOLOG Master Set"** — coleção de Set nova, criada pela interface, num Set onde você tem exemplares **livres** (fora de qualquer coleção) em pelo menos dois acabamentos, que tenha ao menos um terceiro acabamento disponível (para H9b) e, se possível, uma carta secreta. Escolha um local **já existente** em "Onde guardo" (para não criar local novo).
- Nenhuma coleção existente é convertida. As 3 coleções reais ficam em Set padrão.
- Os exemplares usados entram por vínculo (5046) e saem por desvínculo (5047): nada é criado, editado ou apagado em `physical_card`.

## 2. Foto do estado antes (SQL Editor, só leitura)

Troque `SEU_EMAIL` e guarde o resultado.

```sql
with me as (select u.id from auth.users u where u.email = 'SEU_EMAIL'),
inv as (select i.id from public.inventory i, me where i.owner_user_id = me.id)
select
  (select count(*) from public.collection c, me where c.owner_user_id = me.id)                         as colecoes,
  (select count(*) from public.collection c, me where c.owner_user_id = me.id and c.completion_policy = 'MASTER_SET') as master_sets,
  (select count(*) from public.physical_card pc, inv where pc.inventory_id = inv.id)                     as exemplares,
  (select count(*) from public.collection_allocation ca join public.collection c on c.id = ca.collection_id, me
     where c.owner_user_id = me.id)                                                                     as vinculos,
  (select md5(string_agg(pc.id::text||pc.card_variant_id::text||pc.language_id::text||coalesce(pc.storage_container_id::text,''), ',' order by pc.id))
     from public.physical_card pc, inv where pc.inventory_id = inv.id)                                  as fp_exemplares,
  (select md5(string_agg(ca.physical_card_id::text||ca.collection_id::text, ',' order by ca.physical_card_id))
     from public.collection_allocation ca join public.collection c on c.id = ca.collection_id, me
     where c.owner_user_id = me.id and c.name <> 'HOMOLOG Master Set')                                  as fp_vinculos_reais,
  (select count(*) from public.storage_container sc, inv where sc.inventory_id = inv.id)                 as locais;
```

## 3. Roteiro (desktop e mobile)

Cada passo: PASS se o resultado esperado aparece; STOP no primeiro desvio (anote, tire captura, não tente corrigir).

| # | Ação | Esperado (PASS) |
|---|---|---|
| H1 | Criar "HOMOLOG Master Set" (Set escolhido, local existente) | Coleção em Set padrão; título "Set padrão — uma de cada carta" |
| H2 | Ajustes → Objetivo → Master Set | Acabamentos do Set com "N cartas · você tem M"; sugestão Padrão/Holográfica/Reversa; bloco "Cartas secretas · sempre no objetivo" (se houver) |
| H3 | Revisar mudança | Prévia: hoje × depois, posições, secretas, exemplares fora do objetivo; nada gravado ainda |
| H4 | Confirmar | Sucesso com "X de Y posições"; topo vira "Master Set — os acabamentos que você escolher"; grade por posição com a linha de acabamento |
| H5 | Filtros Todas / Tenho / Faltam e paginação (`Próxima`/`Anterior` se > 120 posições) | Contagens das abas = progresso; páginas sem repetição; voltar à aba zera a página |
| H6 | Posição secreta genérica (se houver) | Linha "Secreta · qualquer acabamento" |
| H7 | Em "Faltam", posição com "No seu acervo" → Adicionar do acervo | Painel lista só exemplares livres daquela carta naquele acabamento (versão + idioma + local) |
| H8 | Adicionar um exemplar | Sucesso; grade e progresso atualizam; a posição vai para "Tenho"; o exemplar some da lista |
| H9 | Ajustes → desmarcar um acabamento → Revisar → Confirmar | Posições somem; exemplares daquele acabamento aparecem em "Exemplares fora do objetivo" (recolhível, com motivo); nada é removido |
| H9b | **Sem recarregar a página**, com a seção "fora do objetivo" **aberta** (após H9): Ajustes → desmarcar **um segundo** acabamento que também tenha exemplares vinculados → Revisar → Confirmar | O título e a lista da seção mostram o mesmo número de exemplares, incluindo os do segundo acabamento. **STOP específico:** título com um número e lista com outro — anotar os dois números e capturar. Depois, remarcar os dois acabamentos (a seção some quando o total chega a 0) |
| H10 | Ajustes → Set padrão → Revisar → Confirmar | Grade padrão volta; exemplares continuam na coleção |
| H11 | Ajustes → Master Set | Acabamentos restaurados ("Restauramos os acabamentos…"); Reativar → mesma grade de H9 |
| H12 | Estados | Rede lenta (DevTools): esqueletos; offline ao confirmar: erro claro + "Tentar novamente", nada muda; aba "Tenho" vazia mostra o estado vazio |
| H13 | Teclado | Tab/Shift+Tab/Espaço/Enter em Ajustes, painel e grade; foco visível; Esc fecha painéis (exceto durante gravação) |
| H14 | Visual | Claro e escuro; desktop (≥ 1280 px) e mobile (≈ 390 px). Capturas: Ajustes (escolha + prévia), grade (Todas/Faltam), painel Adicionar, seção fora do objetivo |

**STOP imediato** se: algum exemplar real (fora da coleção HOMOLOG) mudar de coleção, de versão, de idioma ou de local; aparecer exemplar de outra pessoa ou já vinculado; o progresso divergir da grade; qualquer texto técnico/código aparecer na tela; erro sem mensagem.

## 4. Conferência e restauração

1. Pela interface, na coleção HOMOLOG: Ajustes → **Set padrão** (se estiver em Master Set) e, em cada carta, **Tirar da coleção** os exemplares vinculados no teste.
2. Excluir a coleção (só com autorização; a coleção precisa estar sem vínculos — `delete_collection` recusa se houver):

```sql
-- SQL Editor, como você (substitua os dois valores)
begin;
select set_config('request.jwt.claims', json_build_object('sub', 'SEU_USER_ID', 'role', 'authenticated')::text, true);
set local role authenticated;
select * from public.delete_collection('ID_DA_COLECAO_HOMOLOG');
commit;
```

3. Rodar de novo a consulta do item 2. **PASS** se: `colecoes`, `master_sets`, `exemplares`, `vinculos`, `locais`, `fp_exemplares` e `fp_vinculos_reais` forem **iguais** à foto inicial.

## 5. Registro

Anotar em `docs/log.md` (uma linha) e no HANDOFF: data, Set usado, resultado H1–H14, capturas (pasta local), foto antes/depois idênticas. Publicação (`*_RELEASED = true`) só depois disso e com autorização.
