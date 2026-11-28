#!/usr/bin/env python3
"""V1-13 · E4 — gera os artefatos de ativação e encerramento do modo TEST da barreira 5389.

Nada aqui é migration: são duas escritas de ESTADO da barreira (registro de 4 identidades e modo TEST;
volta a CLOSED com o registro vazio), cada uma com gates somente leitura e manifesto do executor v1.4.
Execução só com autorização expressa e específica, pelo executor por arquivo (STD-005 §3).
"""
import hashlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
PKG = "database\\proposals\\2026-11-27-v1-13-e4-homologation"

# Conjunto E4 = as 4 contas EXISTENTES escolhidas pelo proprietário (decisão `E4 — EXECUTION ADAPTATION`):
# T = a conta que já tem coleções (titular); E, E2 = EDITOR; V = VIEWER. Nenhum username nem e-mail entra no
# repositório: só o md5 do username (E4_CONTAS_MD5.json), gerado por
#   python build_e4.py --contas T=<username> E=<username> E2=<username> V=<username>
# A resolução para UUID acontece no banco, dentro dos gates; o PRE da abertura registra papel, UUID e
# username de cada conta na evidência do executor (fora do repositório).
import json
import re
import sys

ROLES = ["T", "E", "E2", "V"]
CONTAS_FILE = HERE / "E4_CONTAS_MD5.json"


def load_contas() -> dict:
    c = json.loads(CONTAS_FILE.read_text(encoding="utf-8")) if CONTAS_FILE.exists() else {}
    ok = sorted(c) == sorted(ROLES) and all(isinstance(v, str) and re.fullmatch(r"[0-9a-f]{32}", v) for v in c.values()) \
        and len(set(c.values())) == 4
    return c if ok else {}


CONTAS = load_contas()
MD5_ASSERT = "e4f710904f50e6e8c3f1d8e2337639e0"
MD5_OPEN = "32e2f636361732b497e8401e50f0bbe0"

LIST = ", ".join(f"'{CONTAS[r]}'" for r in ROLES) if CONTAS else "'PENDENTE'"
TESTSET = f"(select up.id from public.user_profile up where md5(up.username) in ({LIST}))"
TITULAR = f"(select up.id from public.user_profile up where md5(up.username) = '{CONTAS.get('T', 'PENDENTE')}')"
TC = f"(select c.id from public.collection c where c.owner_user_id = {TITULAR})"

FUNCS_OK = (
    f"(select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) = '{MD5_ASSERT}'\n"
    f"                                 and (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) = '{MD5_OPEN}'"
)

# Controles BLOQUEANTES de isolamento (acesso): nada da V1-13 envolve conta fora do conjunto (a barreira nunca abriu).
ISOLATION = {
    "contas_conjunto_4": f"(select count(*) from public.user_profile up where md5(up.username) in ({LIST})) = 4",
    "titular_com_colecoes": f"exists (select 1 from public.collection c where c.owner_user_id = {TITULAR} and c.lifecycle_status = 'ACTIVE')",
    "sem_editor_fora_do_conjunto": (
        "not exists (select 1 from public.collection_membership m join public.collection c on c.id = m.collection_id\n"
        f"                                 where m.role = 'EDITOR' and (m.user_id not in {TESTSET} or c.owner_user_id not in {TESTSET}))"
    ),
    "sem_auditoria_colecao_fora_do_conjunto": f"not exists (select 1 from public.collection_activity_event e where e.owner_user_id not in {TESTSET})",
}
# Contagens INFORMATIVAS (contas reais têm vida própria: compartilhamentos V1-12 e administração não bloqueiam).
INFO = {
    "admins_no_conjunto_n": f"(select count(*) from public.admin_user a where a.id in {TESTSET})",
    "membros_fora_do_conjunto_nas_colecoes_do_titular_n": (
        "(select count(*) from public.collection_membership m\n"
        f"                                 where m.collection_id in {TC} and m.user_id not in {TESTSET})"
    ),
    "participacoes_do_conjunto_em_colecoes_de_fora_n": (
        "(select count(*) from public.collection_membership m join public.collection c on c.id = m.collection_id\n"
        f"                                 where m.user_id in {TESTSET} and c.owner_user_id not in {TESTSET})"
    ),
}
# Contagem comparada à mão entre o PRE da abertura e o POST do encerramento: deve ser IGUAL.
EXTERNAL_EVENTS = (
    "(select count(*) from public.binder_activity_event b\n"
    f"                                 where b.actor_user_id is not null and b.actor_user_id <> b.owner_user_id and b.actor_user_id not in {TESTSET})"
)

# Impressões digitais do titular (antes × depois). Patrimônio (alocações, exemplares) DEVE ficar igual; condição só
# muda no exemplar escolhido para a PR-04B (restaurado no fim); organização (fichário, Pokédex, coleções) pode mudar.
def fp(expr: str, src: str) -> str:
    return f"(select md5(coalesce(string_agg({expr}, ',' order by {expr}), '')) from {src})"


INV = f"public.physical_card pc join public.inventory i on i.id = pc.inventory_id where i.owner_user_id = {TITULAR}"
LAYOUT_SLOTS = (
    "public.collection_layout l join public.collection_layout_page pg on pg.layout_id = l.id\n"
    "                                 join public.collection_layout_slot s on s.page_id = pg.id\n"
    "                                 left join public.collection_layout_slot_assignment a on a.slot_id = s.id\n"
    "                                 left join public.collection_layout_slot_expected_content e on e.slot_id = s.id\n"
    f"                                 where l.collection_id in {TC} and (a.id is not null or s.locked or e.slot_id is not null)"
)
POKE = ("public.collection_pokedex_position_assignment pa join public.collection_allocation ca on ca.id = pa.collection_allocation_id\n"
        f"                                 where ca.collection_id in {TC}")
FINGERPRINTS = [
    ("alocacoes_fp", fp("ca.id::text || ':' || ca.physical_card_id::text || ':' || ca.collection_id::text",
                        f"public.collection_allocation ca where ca.collection_id in {TC}")),
    ("exemplares_fp", fp("pc.id::text || ':' || pc.card_variant_id::text || ':' || pc.language_id::text || ':' || coalesce(pc.storage_container_id::text, '')", INV)),
    ("condicao_fp", fp("pc.id::text || ':' || coalesce(pc.condition_code, '')", INV)),
    ("fichario_fp", fp("l.id::text || ':' || pg.page_number || ':' || s.row_index || ':' || s.column_index || ':' || coalesce(a.physical_card_id::text, '') || ':' || s.locked || ':' || coalesce(e.card_id::text, '')", LAYOUT_SLOTS)),
    ("pokedex_fp", fp("pa.collection_allocation_id::text || ':' || pa.pokedex_position_id::text || ':' || pa.assignment_basis", POKE)),
    ("colecoes_fp", fp("c.id::text || ':' || c.name || ':' || coalesce(c.description, '') || ':' || coalesce(c.cover_finish, '') || ':' || coalesce(c.cover_code, '') || ':' || coalesce(c.cover_logo_path, '')",
                       f"public.collection c where c.owner_user_id = {TITULAR}")),
]
# Estado anterior DETALHADO (só no PRE da abertura): base para restauração manual pela interface.
BASELINE = [
    ("contas", "(select jsonb_agg(jsonb_build_object('papel', r.papel, 'id', up.id, 'username', up.username,\n"
               "                                   'admin', exists (select 1 from public.admin_user a where a.id = up.id),\n"
               "                                   'colecoes', (select count(*) from public.collection c where c.owner_user_id = up.id)) order by r.papel)\n"
               "                                 from public.user_profile up join (values " +
               (", ".join(f"('{r}', '{CONTAS[r]}')" for r in ROLES) if CONTAS else "('T', 'PENDENTE')") +
               ") r(papel, h) on md5(up.username) = r.h)"),
    ("colecoes_antes", "(select jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.name, 'descricao', c.description, 'modo', c.mode,\n"
                       "                                   'objetivo', c.completion_policy, 'ciclo', c.lifecycle_status, 'visibilidade', c.visibility,\n"
                       "                                   'capa', jsonb_build_object('acabamento', c.cover_finish, 'codigo', c.cover_code, 'imagem', c.cover_logo_path),\n"
                       "                                   'fichario', (select jsonb_agg(l.id) from public.collection_layout l where l.collection_id = c.id),\n"
                       "                                   'convidada_em', (select jsonb_agg(g.layout_id) from public.collection_layout_guest g where g.collection_id = c.id),\n"
                       "                                   'alocacoes', (select count(*) from public.collection_allocation ca where ca.collection_id = c.id)) order by c.name)\n"
                       f"                                 from public.collection c where c.owner_user_id = {TITULAR})"),
    ("membros_antes", "(select jsonb_agg(jsonb_build_object('colecao', m.collection_id, 'username', up.username, 'papel', m.role, 'situacao', m.status) order by m.collection_id, up.username)\n"
                      f"                                 from public.collection_membership m join public.user_profile up on up.id = m.user_id where m.collection_id in {TC})"),
    ("fichario_antes", "(select jsonb_agg(jsonb_build_object('l', l.id, 'p', pg.page_number, 'r', s.row_index, 'c', s.column_index,\n"
                       "                                   'exemplar', a.physical_card_id, 'fixo', s.locked, 'esperado', e.card_id) order by l.id, pg.page_number, s.row_index, s.column_index)\n"
                       f"                                 from {LAYOUT_SLOTS})"),
    ("paginas_antes", f"(select jsonb_agg(jsonb_build_object('l', l.id, 'paginas', (select count(*) from public.collection_layout_page pg where pg.layout_id = l.id)) order by l.id) from public.collection_layout l where l.collection_id in {TC})"),
    ("pokedex_antes", "(select jsonb_agg(jsonb_build_object('alocacao', pa.collection_allocation_id, 'posicao', pa.pokedex_position_id, 'base', pa.assignment_basis) order by pa.pokedex_position_id, pa.collection_allocation_id)\n"
                      f"                                 from {POKE})"),
    ("representantes_antes", "(select jsonb_agg(jsonb_build_object('colecao', r.collection_id, 'posicao', r.pokedex_position_id, 'alocacao', r.collection_allocation_id) order by r.collection_id, r.pokedex_position_id)\n"
                             f"                                 from public.collection_pokedex_position_primary_representative r where r.collection_id in {TC})"),
    ("especies_antes_fp", f"(select md5(coalesce(string_agg(x::text, ',' order by x::text), '')) from public.collection_layout_slot_species_reference x where x.collection_id in {TC})"),
]


def gate(title: str, doc: str, keys: list[tuple[str, str]]) -> str:
    w = max(len(k) for k, _ in keys) + 3
    body = ",\n".join(f"  {(chr(39) + k + chr(39) + ','):<{w}} {v}" for k, v in keys)
    return f"/*\n{doc}\n*/\n\nselect jsonb_build_object(\n{body}\n) as {title};\n"


def iso_keys() -> list[tuple[str, str]]:
    return list(ISOLATION.items()) + list(INFO.items()) + [("eventos_editor_externos_n", EXTERNAL_EVENTS)]


OPEN_PRE = gate("e4_open_pre",
    "V1-13 · E4 — PRE da ABERTURA do TEST (somente leitura, um SELECT, modo gate). PASS = todos os booleanos true,\n"
    "barreira CLOSED, 0 identidades, executor = papel. É também o REGISTRO DO ESTADO ANTERIOR do titular (contas, coleções,\n"
    "membros, fichários, páginas, Pokédex, representantes) e das impressões digitais *_fp, comparadas com o POST do encerramento.",
    [("executor", "current_user"),
     ("barreira", "(select s.mode from public.v1_13_barrier_state s where s.id = 1)"),
     ("identidades_teste", "(select count(*) from public.v1_13_barrier_identity)"),
     ("funcoes_barreira_canonicas", FUNCS_OK)] + iso_keys() + FINGERPRINTS + BASELINE)

OPEN_POST = gate("e4_open_post",
    "V1-13 · E4 — POST da ABERTURA (somente leitura, um SELECT, modo gate). Sem as chaves 'barreira' e 'identidades_teste'\n"
    "(o executor as exige CLOSED/0): o modo TEST e o registro são provados por booleanos próprios.",
    [("executor", "current_user"),
     ("modo_teste", "(select s.mode from public.v1_13_barrier_state s where s.id = 1) = 'TEST'"),
     ("registro_igual_contas", f"(select count(*) from public.v1_13_barrier_identity) = 4\n"
                               f"                                 and not exists (select 1 from public.v1_13_barrier_identity i where i.user_id not in {TESTSET})"),
     ("funcoes_barreira_canonicas", FUNCS_OK)] + iso_keys())

# PRE do encerramento: exigido pelo executor v1.4 (toda escrita precisa de um gate antes). NUNCA pode impedir o
# fechamento: o caso mais urgente (registro com conta indevida, modo inesperado) é justamente quando fechar.
# Por isso o único critério booleano é a existência da linha de estado; modo e registro ficam REGISTRADOS
# (texto e contagens) como evidência do estado antes do fechamento. Sem 'barreira'/'identidades_teste'
# (o executor as exigiria CLOSED/0 e bloquearia o fechamento do TEST).
CLOSE_PRE = gate("e4_close_pre",
    "V1-13 · E4 — PRE do ENCERRAMENTO (somente leitura, um SELECT, modo gate). Só registra o estado antes de fechar;\n"
    "o único critério é a linha de estado existir. Esperado após a E4 ou um STOP: modo_atual = TEST, identidades_n = 4,\n"
    "identidades_fora_do_conjunto_n = 0 (se diferente: fechar mesmo assim e registrar como incidente).",
    [("executor", "current_user"),
     ("estado_barreira_presente", "exists (select 1 from public.v1_13_barrier_state s where s.id = 1)"),
     ("modo_atual", "(select s.mode from public.v1_13_barrier_state s where s.id = 1)"),
     ("identidades_n", "(select count(*) from public.v1_13_barrier_identity)"),
     ("identidades_fora_do_conjunto_n", f"(select count(*) from public.v1_13_barrier_identity i where i.user_id not in {TESTSET})"),
     ("eventos_editor_externos_n", EXTERNAL_EVENTS)])

CLOSE_POST = gate("e4_close_post",
    "V1-13 · E4 — POST do ENCERRAMENTO (somente leitura, um SELECT, modo gate). PASS = barreira CLOSED, 0 identidades,\n"
    "booleanos true e, na conferência manual com o PRE da abertura: eventos_editor_externos_n, alocacoes_fp e exemplares_fp IGUAIS;\n"
    "condicao_fp igual depois de restaurar o exemplar da PR-04B; demais *_fp mostram o que a homologação mudou.",
    [("executor", "current_user"),
     ("barreira", "(select s.mode from public.v1_13_barrier_state s where s.id = 1)"),
     ("identidades_teste", "(select count(*) from public.v1_13_barrier_identity)"),
     ("funcoes_barreira_canonicas", FUNCS_OK)] + [kv for kv in iso_keys() if kv[0] not in ("contas_conjunto_4", "titular_com_colecoes")] + FINGERPRINTS)

ISO_DO = " or ".join(f"not ({v})" for k, v in ISOLATION.items())

OPEN_SQL = f"""/*
================================================================
Projeto.....: Project Mimikyu
Query.......: E4-OPEN — ativa o modo TEST da barreira 5389 para as 4 contas do conjunto E4 (V1-13 · E4)
Versão......: 1.0 (2026-11-27, `E4 — FINAL HOMOLOGATION EXECUTION READINESS`)
Status......: PREPARADA — NÃO EXECUTADA. Só com autorização expressa e específica, pelo executor por
              arquivo (E4_OPEN_MANIFEST.txt). Não é migration: muda só o estado da barreira.
Efeito......: registra as 4 contas do conjunto E4 (identificadas pelo md5 do username; titular, EDITOR,
              EDITOR 2 e VIEWER) em v1_13_barrier_identity e muda o modo para TEST. Qualquer conta fora do
              registro continua negada pela porta (5389).
Reversão....: E4_TEST_CLOSE.sql (CLOSED + registro vazio).
================================================================
*/

begin;
set local lock_timeout = '5s';

do $pre$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'PRECHECK E4-OPEN: barreira não está CLOSED com registro vazio';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) is distinct from '{MD5_ASSERT}'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) is distinct from '{MD5_OPEN}' then
    raise exception 'PRECHECK E4-OPEN: funções da porta diferem do canônico';
  end if;
  if {ISO_DO} then
    raise exception 'PRECHECK E4-OPEN: conjunto de contas incompleto, titular sem coleções ou isolamento violado';
  end if;
end;
$pre$;

insert into public.v1_13_barrier_identity (user_id, note)
select up.id, 'E4: conjunto de homologação'
from public.user_profile up
where md5(up.username) in ({LIST});

update public.v1_13_barrier_state
   set mode = 'TEST', changed_at = now(), change_note = 'E4: homologação V1-13 (4 identidades do conjunto)'
 where id = 1;

do $post$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'TEST'
     or (select count(*) from public.v1_13_barrier_identity) <> 4
     or exists (select 1 from public.v1_13_barrier_identity i where i.user_id not in {TESTSET}) then
    raise exception 'POSTCHECK E4-OPEN: modo ou registro fora do esperado';
  end if;
end;
$post$;

commit;
"""

CLOSE_SQL = f"""/*
================================================================
Projeto.....: Project Mimikyu
Query.......: E4-CLOSE — encerra o modo TEST: barreira CLOSED e registro de identidades vazio (V1-13 · E4)
Versão......: 1.0 (2026-11-27, `E4 — FINAL HOMOLOGATION EXECUTION READINESS`)
Status......: PREPARADA — NÃO EXECUTADA. Pelo executor por arquivo (E4_CLOSE_MANIFEST.txt), com
              autorização. É também o STOP da E4: sem pré-condição que impeça fechar.
Efeito......: modo CLOSED e nenhuma identidade registrada. Não apaga contas, coleções, convites nem
              eventos da homologação (ficam nas contas do conjunto, inertes com a barreira fechada).
================================================================
*/

begin;
set local lock_timeout = '5s';

update public.v1_13_barrier_state
   set mode = 'CLOSED', changed_at = now(), change_note = 'E4: encerramento do TEST'
 where id = 1;

delete from public.v1_13_barrier_identity;

do $post$
begin
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'POSTCHECK E4-CLOSE: barreira não ficou CLOSED com registro vazio';
  end if;
end;
$post$;

commit;
"""


def write(name: str, text: str) -> str:
    data = text.encode("utf-8")
    (HERE / name).write_bytes(data)
    return hashlib.sha256(data).hexdigest()


def set_contas(args: list[str]) -> None:
    """Grava só os md5 dos usernames (nunca o username) em E4_CONTAS_MD5.json."""
    pairs = dict(a.split("=", 1) for a in args)
    if sorted(pairs) != sorted(ROLES):
        sys.exit("informe exatamente T=, E=, E2= e V=")
    out = {}
    for r in ROLES:
        u = pairs[r].strip().lower().lstrip("@")
        if not re.fullmatch(r"[a-z0-9_]{3,20}", u):
            sys.exit(f"{r}: username inválido (formato do user_profile: [a-z0-9_]{{3,20}})")
        out[r] = hashlib.md5(u.encode()).hexdigest()
    if len(set(out.values())) != 4:
        sys.exit("as 4 contas precisam ser distintas")
    CONTAS_FILE.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    if not CONTAS:
        sys.exit("E4_CONTAS_MD5.json ausente ou incompleto: rode  python build_e4.py --contas T=... E=... E2=... V=...")
    files = {
        "E4_OPEN_PRE_readonly.sql": OPEN_PRE,
        "E4_TEST_OPEN.sql": OPEN_SQL,
        "E4_OPEN_POST_readonly.sql": OPEN_POST,
        "E4_CLOSE_PRE_readonly.sql": CLOSE_PRE,
        "E4_TEST_CLOSE.sql": CLOSE_SQL,
        "E4_CLOSE_POST_readonly.sql": CLOSE_POST,
    }
    h = {n: write(n, t) for n, t in files.items()}
    head = "# V1-13 · E4 — manifesto do executor por arquivo (STD-005 §3, v1.4). passo|arquivo|sha256|modo\n"
    open_m = head + "".join(f"{i}|{PKG}\\{n}|{h[n]}|{m}\n" for i, (n, m) in enumerate(
        [("E4_OPEN_PRE_readonly.sql", "gate"), ("E4_TEST_OPEN.sql", "write"), ("E4_OPEN_POST_readonly.sql", "gate")], 1))
    close_m = head + "".join(f"{i}|{PKG}\\{n}|{h[n]}|{m}\n" for i, (n, m) in enumerate(
        [("E4_CLOSE_PRE_readonly.sql", "gate"), ("E4_TEST_CLOSE.sql", "write"), ("E4_CLOSE_POST_readonly.sql", "gate")], 1))
    h["E4_OPEN_MANIFEST.txt"] = write("E4_OPEN_MANIFEST.txt", open_m)
    h["E4_CLOSE_MANIFEST.txt"] = write("E4_CLOSE_MANIFEST.txt", close_m)
    for n, v in h.items():
        print(f"{v}  {n}")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--contas":
        set_contas(sys.argv[2:])
        print("E4_CONTAS_MD5.json gravado; rode de novo sem argumentos para gerar os artefatos.")
    else:
        main()
