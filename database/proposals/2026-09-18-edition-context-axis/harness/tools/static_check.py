# 2830H — verificação estática local dos envelopes (não conecta a banco). Uso: python3 tools/static_check.py
import re,sys,pathlib
H=pathlib.Path(__file__).resolve().parent.parent
def code(s):  # remove -- comments, keep strings
    out=[]
    for l in s.splitlines():
        i=l.find('--')
        out.append(l if i<0 else l[:i])
    return '\n'.join(out)
def nostr(c):
    c=re.sub(r"\$re\$.*?\$re\$","''",c,flags=re.S)
    return re.sub(r"'(?:[^']|'')*'","''",c)
res=[]
def chk(name,cond,detail=''):
    res.append((name,bool(cond),detail))
for f,exp,tag in [('2830H_E01_section1_structural.sql',['1.1','1.2','1.3','1.4','1.5','1.6','1.7','1.8','1.9','1.10','1.11','1.12'],'h2830_e01'),
                  ('2830H_E02_identity_terminal_D1_D5.sql',['D1','D2','D3','D4','D5'],'h2830_e02')]:
    s=(H/f).read_text(encoding='utf-8'); c=code(s); U=c.upper()
    chk(f+': 1 DO por arquivo', len(re.findall(r'\bDO\s+\$',c))==1)
    chk(f+': dollar-quote abre/fecha', c.count('$'+tag+'$')==2 and c.rstrip().endswith('$'+tag+'$;'))
    body=c.split('$'+tag+'$')[1]
    bodyns=nostr(body)
    stmts_outside=c.split('$'+tag+'$')[0].strip()
    chk(f+': nada executável fora do DO', stmts_outside.upper().strip()=='DO')
    for tok in [r'\bCOMMIT\b',r'\bROLLBACK\b',r'\bCREATE\b',r'\bALTER\b',r'\bDROP\b',r'\bTEMP\b',r'\bTEMPORARY\b',r'SET_CONFIG',r'\bSET\s+ROLE\b',r'\bSET\s+LOCAL\b',r'\bSET\s+SESSION\b',r'\bGRANT\b',r'\bREVOKE\b',r'\bTRUNCATE\b',r'\bDELETE\b',r'\bUPDATE\b',r'PG_SLEEP',r'DBLINK',r'\bNET\.',r'\bPERFORM\b',r'\bEXECUTE\b',r'RAISE\s+NOTICE',r'RAISE\s+WARNING',r'RAISE\s+INFO',
                r'\bCOMMENT\b',r'\bSECURITY\s+LABEL\b',r'\bREINDEX\b',r'\bREFRESH\b',r'\bIMPORT\b',r'\bLISTEN\b',r'\bNOTIFY\b',
                r'\bLOAD\b',r'\bCALL\b',r'\bCOPY\b',r'\bLOCK\b',r'\bMERGE\b']:
        chk(f+f': proibido ausente {tok}', not re.search(tok,bodyns.upper()))
    cases=re.findall(r"v_case\s*:=\s*'([^']+)'",body)
    chk(f+': casos na ordem = esperado', cases==exp, str(cases))
    exp_arr=re.search(r"c_expected\s+CONSTANT\s+text\[\]\s*:=\s*ARRAY\[(.*?)\]",body,re.S).group(1)
    chk(f+': c_expected = esperado', re.findall(r"'([^']+)'",exp_arr)==exp)
    codes=set(re.findall(r"ERRCODE\s*=\s*'([A-Z0-9]{5})'",body))
    chk(f+': ERRCODEs só H283C/F/P', codes<= {'H283C','H283F','H283P'}, str(codes))
    chk(f+': H283P exatamente 1', len(re.findall(r"ERRCODE\s*=\s*'H283P'",body))==1)
    # H283P é o último RAISE do corpo
    last=[m.group(0) for m in re.finditer(r"ERRCODE\s*=\s*'H283[CFP]'",body)][-1]
    chk(f+': último sinal é H283P', "H283P" in last)
    # cada caso: 1 sinal H283C, 1 handler H283C, 1 handler H283F re-raise, 1 WHEN OTHERS convertendo
    blocks=re.split(r"v_case\s*:=\s*'[^']+'\s*;",body)[1:]
    for cid,b in zip(cases,blocks):
        b=b.split('v_case :=')[0]
        ok = (len(re.findall(r"ERRCODE\s*=\s*'H283C'",b))==1 and
              "WHEN SQLSTATE 'H283C'" in b and "WHEN SQLSTATE 'H283F' THEN RAISE;" in b and
              'v_done := v_done || v_case' in b)
        chk(f+f': caso {cid} estrutura de subtransação', ok)
        # negativos: todo "EXCEPTION WHEN OTHERS THEN v_got := true" deve ser seguido de checagem de sqlstate+constraint
        negs=len(re.findall(r'EXCEPTION WHEN OTHERS THEN\s+v_got := true;',b))
        sqlst=len(re.findall(r"v_state <> '(23514|23505)' OR v_con IS DISTINCT FROM '",b))
        if negs: chk(f+f': caso {cid} negativos={negs} com SQLSTATE+constraint', sqlst>=1 and 'IF NOT v_got' in b, f'negs={negs} checks={sqlst}')
    # BEGIN/END balance (END IF/LOOP excluídos)
    nb=len(re.findall(r'\bBEGIN\b',U)); ne=len(re.findall(r'\bEND\b(?!\s+(IF|LOOP))',U))
    chk(f+': BEGIN/END balanceados', nb==ne, f'{nb}/{ne}')
    n_if=len(re.findall(r'(?<!END )\bIF\b',U)); n_eif=len(re.findall(r'\bEND\s+IF\b',U))
    chk(f+': IF/END IF balanceados', n_if==n_eif, str(n_if)+'/'+str(n_eif))
    chk(f+': parênteses balanceados', nostr(c).count('(')==nostr(c).count(')'))
    chk(f+': aspas simples pares', c.count("'")%2==0)
    ins=re.findall(r'INSERT INTO [^;]*;',body,re.S)
    chk(f+f': INSERTs={len(ins)} todos com marcador', all('v_marker' in i for i in ins))
for f in ['2830H_E00_precheck_inventory.sql','2830H_E99_postcheck_residue.sql']:
    raw=re.sub(r"\$re\$.*?\$re\$","''",(H/f).read_text(encoding='utf-8'),flags=re.S)
    c=code(raw); U=nostr(c).upper()
    chk(f+': 1 statement', U.count(';')==1 and U.rstrip().endswith(';'))
    for tok in [r'\bINSERT\b',r'\bUPDATE\b',r'\bDELETE\b',r'\bCREATE\b',r'\bALTER\b',r'\bDROP\b',r'SET_CONFIG',r'\bSET\b',r'\bDO\b',r'\bTEMP\b',
                r'\bINTO\b',r'\bGRANT\b',r'\bREVOKE\b',r'\bCOMMENT\b',r'\bSECURITY\s+LABEL\b',r'\bREINDEX\b',r'\bREFRESH\b',r'\bIMPORT\b',
                r'\bTRUNCATE\b',r'\bMERGE\b',r'\bCOPY\b',r'\bCALL\b',r'\bLOCK\b',r'\bLISTEN\b',r'\bNOTIFY\b']:
        chk(f+f': ausente {tok}', not re.search(tok,U))
    chk(f+': parênteses balanceados', nostr(c).count('(')==nostr(c).count(')'))

# ---------------------------------------------------------------------------
# CORRECTION-01: 1.12 com MAINTAIN; baselines E00/E99; P7
# ---------------------------------------------------------------------------
import json
PRIVS=['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']
e01=(H/'2830H_E01_section1_structural.sql').read_text(encoding='utf-8')
b112=code(e01).split("v_case := '1.12'")[1]
arrs=re.findall(r"unnest\(ARRAY\[([^\]]*)\]\)\s+AS\s+p\(priv\)",b112)
chk('1.12: 2 matrizes de privilégio', len(arrs)==2, str(len(arrs)))
chk('1.12: cada matriz = 8 privilégios PG17 (inclui MAINTAIN)', all(re.findall(r"'([A-Z]+)'",a)==PRIVS for a in arrs))
chk('1.12: anon e authenticated conferidos', "has_table_privilege('anon'" in b112 and "has_table_privilege('authenticated'" in b112)
e00=(H/'2830H_E00_precheck_inventory.sql').read_text(encoding='utf-8')
e99=(H/'2830H_E99_postcheck_residue.sql').read_text(encoding='utf-8')
def block(t,name):
    m=re.search(r'-- '+name+r':BEGIN\n(.*?)\n\s*-- '+name+r':END',t,re.S); return m.group(1) if m else None
for name in ['BASELINE-BUILDER','FREEZE-CANON']:
    a,b=block(e00,name),block(e99,name)
    chk(f'{name}: presente em E00 e E99', a is not None and b is not None)
    chk(f'{name}: idêntico byte a byte E00 x E99', a is not None and a==b)
canon_txt=re.search(r"SELECT '(\{.*?\})'::jsonb AS c",block(e00,'FREEZE-CANON') or '',re.S)
canon=json.loads(canon_txt.group(1)) if canon_txt else {}
chk('CANON: JSON válido', bool(canon))
req={'trait','profile','profile_trait','mapping','mapping_null_signature','card_variant','card_variant_ec_nonnull','staging_rows','staging_max_upd_utc','staging_status','operational_tristate','cancelled_without_key','lineage','jobs','jobs_by_status','jobs_max_upd_utc','jobs_in_flight'}
chk('CANON: chaves canônicas exatas', set(canon)==req, str(sorted(set(canon)^req)))
chk('CANON: staging_status soma = staging_rows', sum(canon.get('staging_status',{}).values())==canon.get('staging_rows'))
chk('CANON: jobs_by_status soma = jobs', sum(canon.get('jobs_by_status',{}).values())==canon.get('jobs'))
chk('CANON: sem chaves sem valor canônico (action_log, mapping_trait, marker_*)', not ({'action_log','mapping_trait','marker_trait','marker_profile','marker_mapping'} & set(canon)))
bkeys=set(re.findall(r"^\s*'([a-z_]+)',\s*",block(e00,'BASELINE-BUILDER') or '',re.M))
chk('BUILDER: toda chave canônica é produzida pelo builder', req<=bkeys, str(sorted(req-bkeys)))
g00=['g_objects_1x','g_objects_D','g_roles_1_12','g_pg17_maintain_privilege','g_game_source','g_freeze_canonical_equal','g_no_sequences_touched_now',
     'g_p7_all_classified','g_p7_identity_pinned','g_p7_search_path_safe','g_p7_no_external_or_dynamic','g_p7_no_ddl','g_p7_lexically_supported',
     'g_p7_no_unresolved','g_p7_no_unqualified_dml','g_p7_writes_in_scope','g_p7_closure_complete','g_no_rules',
     'g_evt_inventory_complete','g_evt_ddl_only','g_evt_all_adjudicated','g_rls_bypass','g_no_residue','g_no_concurrency']   # G-1: os 24 gates, todos com definição conferida
c00=code(e00)
for gname in g00: chk(f'E00: gate {gname} definido', re.search(r'AS\s+'+gname+r'\b',c00) is not None)
_gcte=c00[c00.index('\ngates AS ('):c00.index('\nSELECT to_jsonb(g)')]
_gdef=re.findall(r'AS\s+(g_[A-Za-z0-9_]+)',_gcte)
chk('E00: CTE gates define EXATAMENTE os 24 gates reconciliados (sem extra, sem falta, sem duplicata)', sorted(_gdef)==sorted(g00) and len(_gdef)==len(set(_gdef))==24, str(sorted(set(_gdef)^set(g00))))
# Predicado de cada gate (CORRECTION-01): o nome definido não basta — o segmento que precede 'AS <gate>' precisa conter
# os termos que o tornam efetivo, e nenhum gate pode ser esvaziado por 'WHERE false' / 'OR true' / 'true AS'.
_parts=re.split(r'AS\s+(g_[A-Za-z0-9_]+)',_gcte)
_seg={_parts[i]:_parts[i-1] for i in range(1,len(_parts),2)}
GATE_TERMS={
 'g_objects_1x':["'constraints_1x'","= 7","'indexes_1x'","= 4"], 'g_objects_D':["'indexes_D'","= 5"],
 'g_roles_1_12':["'roles_anon_authenticated'","= 2"], 'g_pg17_maintain_privilege':[">= 170000"],
 'g_game_source':["'game_pokemon'","'source_tcgdex'","= 1"], 'g_freeze_canonical_equal':["NOT EXISTS (SELECT 1 FROM canon_diff)"],
 'g_no_sequences_touched_now':["FROM seq s","r.touched_now"],
 'g_p7_all_classified':["gate_scope","class IN ('UNCLASSIFIED','DENIED')"], 'g_p7_identity_pinned':["gate_scope","class = 'ALLOWLIST_MISMATCH'"],
 'g_p7_search_path_safe':["gate_scope","search_path_unsafe"], 'g_p7_no_external_or_dynamic':["gate_scope","external_signal OR dynamic_sql"],
 'g_p7_no_ddl':["gate_scope","ddl_statement"], 'g_p7_lexically_supported':["gate_scope","unsupported_lexeme"],
 'g_p7_no_unresolved':["p7_unresolved_qualified WHERE gate_scope","resolution IN ('UNRESOLVED','DENIED')"],
 'g_p7_no_unqualified_dml':["p7_unqualified_writes WHERE gate_scope"], 'g_p7_writes_in_scope':["w.gate_scope","NOT w.target_exists","w.target NOT IN"],
 'g_p7_closure_complete':["p7_reach WHERE gate_scope AND depth >= 8"], 'g_no_rules':["FROM p7_rules","rel.gate_scope"],
 'g_evt_inventory_complete':["pg_catalog.pg_event_trigger","FROM evt)"], 'g_evt_ddl_only':["FROM evt WHERE enabled <> 'D'"],
 'g_evt_all_adjudicated':["FROM evt_unadjudicated"], 'g_rls_bypass':["force_rls","o.owner <> current_user"],
 'g_no_residue':["'marker_trait'","'marker_profile'","'marker_mapping'"], 'g_no_concurrency':["'other_sessions_in_txn'","= 0"]}
chk('E00: termos de predicado declarados para os 24 gates', set(GATE_TERMS)==set(g00))
for _g,_terms in GATE_TERMS.items():
    _t=_seg.get(_g,'')
    chk(f'E00: predicado de {_g} contém {len(_terms)} termo(s) efetivo(s) e não é esvaziado',
        all(x in _t for x in _terms) and not re.search(r'WHERE\s+false|OR\s+true|^\s*,?\s*true\s*$',_t,re.I|re.M), _g)
chk('E00: gate antigo g_no_enabled_event_triggers substituído (não coexistem)', re.search(r'AS\s+g_no_enabled_event_triggers\b',c00) is None)
chk('E00: gate_pass agrega TODOS os g_* (bool_and + NULL=falha)', 'bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g))' in c00 and 'WHERE v IS NULL' in c00)
chk('E00: exporta d_baseline e d_baseline_md5', "'d_baseline'," in c00 and "'d_baseline_md5'," in c00 and 'md5(b::text)' in c00)
chk('E00: P7 fecho recursivo + classificação + UNCLASSIFIED', 'WITH RECURSIVE walk' in c00 and "'UNCLASSIFIED'" in e00 and 'p7_allowlist' in c00)
chk('E00: P7 raízes trigger+check+default+index', all(x in e00 for x in ["'trigger '","'check '","'default '","'index '"]))
c99=code(e99)
for ph in ['__E00_D_BASELINE__','__E00_D_BASELINE_MD5__','__E00_ROLE_SETTING_ROWS__']:
    chk(f'E99: marcador {ph} exatamente 1x no código', len(re.findall(r"'"+ph+r"'",c99))==1)
g99=['g_captured_present','g_captured_integrity','g_keys_identical','g_baseline_equal','g_freeze_canonical_equal','g_marker_absent','g_no_open_txn_others','g_lock_timeout_default','g_role_setting_unchanged']
for gname in g99: chk(f'E99: gate {gname} definido', re.search(r'AS\s+'+gname+r'\b',c99) is not None)
chk('E99: gate_pass agrega TODOS os g_* (bool_and + NULL=falha)', 'bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g))' in c99 and 'WHERE v IS NULL' in c99)
chk('E99: diff por chave sobre a UNIÃO das chaves', 'all_keys' in c99 and 'UNION' in c99 and 'd_diff' in c99)


# ---------------------------------------------------------------------------
# CORRECTION-02: MODELO DO P7 v3 (sem banco). Os padrões, palavras-chave,
# lista negra e pinos da allowlist são EXTRAÍDOS do próprio E00 — o modelo
# testa o mesmo texto que o PostgreSQL executará. Tradução ARE→Python:
# \m e \M → \b (fronteiras de palavra); o resto é sintaxe comum.
# ---------------------------------------------------------------------------
import hashlib
e00=(H/'2830H_E00_precheck_inventory.sql').read_text(encoding='utf-8')
REP=dict((n,v) for v,n in re.findall(r"\$re\$(.*?)\$re\$\s+AS\s+([a-z_]+)",e00,re.S))
chk('P7 modelo: 12 padrões extraídos do E00', set(REP)=={'lex','unsupported_raw','unsupported_lexed','lock_or_upsert','qcall','ucall','qdml','udml','signal_raw','dynamic_lexed','ddl_lexed','sql_into_lexed'}, str(sorted(REP)))
def are(p): return p.replace(r'\m',r'\b').replace(r'\M',r'\b')
R={k:re.compile(are(v),re.I if k in ('lock_or_upsert','qdml','udml','signal_raw','dynamic_lexed','ddl_lexed','sql_into_lexed') else 0) for k,v in REP.items()}
def lf(src): return src.replace('\r\n','\n')   # D-6: normalização determinística, SÓ CRLF (CR isolado permanece)
KW=set(re.findall(r"'([a-z_]+)'",re.search(r"p7_keywords\(word\) AS \(\s*SELECT unnest\(ARRAY\[(.*?)\]\)",e00,re.S).group(1)))
DENY=set(re.findall(r"\('([a-z_]+)'\)",re.search(r"p7_denylist\(proname\) AS \(\s*VALUES(.*?)\n\),",e00,re.S).group(1)))
ALLOW={}
for row in re.findall(r"^\s*\(('(?:internal|public|extensions)'.*?)\),?\s*$",re.search(r"p7_allowlist\(.*?\) AS \(\s*VALUES(.*?)\n\),",e00,re.S).group(1),re.M):
    f=[x.strip() for x in re.findall(r"ARRAY\['[^']*'\]|NULL::text\[\]|'(?:[^']|'')*'|true|false|NULL",row)]
    unq=lambda x: None if x in ('NULL','NULL::text[]') else (x=='true' if x in ('true','false') else (re.findall(r"'([^']*)'",x) if x.startswith('ARRAY') else x[1:-1].replace("''","'")))
    v=[unq(x) for x in f]
    ALLOW[(v[0],v[1],v[2])]=dict(lang=v[3],secdef=v[4],vol=v[5],config=v[6],md5=v[7],csym=v[8],ext=v[9],cls=v[10])
chk('P7 modelo: allowlist com 12 entradas pinadas', len(ALLOW)==12, str(len(ALLOW)))
# catálogo simulado (pg_catalog) — suficiente para os corpos reais e os controles
PGCAT_FN={'upper','lower','btrim','trim','regexp_replace','cardinality','now','coalesce','format','count','array_agg',
          'jsonb_typeof','jsonb_exists','gen_random_uuid','unnest','md5','pg_notify','set_config','pg_sleep','txid_current'}
PGCAT_TYPE={'text','uuid','int4','varchar','numeric','timestamp','bool'}
SCOPE={'public.card_edition_context_trait','public.card_edition_context_profile','public.card_edition_context_profile_trait',
       'public.card_edition_context_external_mapping','public.card_edition_context_external_mapping_trait'}
RELATIONS=SCOPE|{'public.card_variant','public.catalog_admin_action_log','public.catalog_variant_import_row'}
def p7_gate(fns, ext_members):
    """fns: dict fqkey->(nsp,name,idargs,lang,secdef,vol,config,prosrc). Retorna (pass, motivos)."""
    reasons=[]; procs={(f[0],f[1]) for f in fns.values()}|{('pg_catalog',n) for n in PGCAT_FN}
    for k,(nsp,name,ida,lang,secdef,vol,cfg,src) in fns.items():
        # classificação
        if nsp=='pg_catalog':
            cls='DENIED' if name in DENY else 'BUILTIN'
        else:
            a=ALLOW.get((nsp,name,ida))
            if a is None: cls='UNCLASSIFIED'
            elif (lang!=a['lang'] or secdef!=a['secdef'] or (a['vol'] is not None and vol!=a['vol'])
                  or (a['config'] is not None and cfg!=a['config'])
                  or (a['md5'] is not None and hashlib.md5(lf(src).encode()).hexdigest()!=a['md5'])
                  or (a['csym'] is not None and src!=a['csym'])
                  or (a['ext'] is not None and k not in ext_members.get(a['ext'],set()))): cls='ALLOWLIST_MISMATCH'
            else: cls=a['cls']
        if cls in ('UNCLASSIFIED','DENIED'): reasons.append('g_p7_all_classified:'+k)
        if cls=='ALLOWLIST_MISMATCH': reasons.append('g_p7_identity_pinned:'+k)
        if lang in ('c','internal'): continue
        lexed=R['lex'].sub(' ',src)
        if nsp!='pg_catalog' and not (cfg is not None and sum(1 for c in cfg if c.startswith('search_path='))==1 and 'search_path=""' in cfg):
            reasons.append('g_p7_search_path_safe:'+k)
        if R['signal_raw'].search(src) or (lang=='plpgsql' and R['dynamic_lexed'].search(lexed)): reasons.append('g_p7_no_external_or_dynamic:'+k)
        if R['unsupported_raw'].search(src) or R['unsupported_lexed'].search(lexed): reasons.append('g_p7_lexically_supported:'+k)
        if R['ddl_lexed'].search(lexed) or (lang=='sql' and R['sql_into_lexed'].search(lexed)): reasons.append('g_p7_no_ddl:'+k)
        t=R['lock_or_upsert'].sub(' ',lexed)
        for m in R['qcall'].finditer(t):
            ref=(m.group(1).lower(),m.group(2).lower())
            if ref not in procs and '.'.join(ref) not in RELATIONS: reasons.append('g_p7_no_unresolved:'+k+'->'+'.'.join(ref))
        for m in R['ucall'].finditer(t):
            n=m.group(1).lower()
            if n in KW: continue
            if n in DENY or not (n in PGCAT_FN or n in PGCAT_TYPE): reasons.append('g_p7_no_unresolved:'+k+'->'+n)
        for m in R['qdml'].finditer(t):
            tgt=m.group(4).lower()+'.'+m.group(5).lower()
            if tgt not in RELATIONS or tgt not in SCOPE: reasons.append('g_p7_writes_in_scope:'+k+'->'+tgt)
        for m in R['udml'].finditer(t): reasons.append('g_p7_no_unqualified_dml:'+k+'->'+m.group(4))
    return (not reasons, reasons)
# corpos REAIS do repositório (mesma extração dos pinos)
REPO=H.parent.parent.parent
real={}
for f,nsp_default in [('proposals/2026-09-18-edition-context-axis/2206_create_edition_context_composition_guards.sql',None),
                      ('proposals/2026-09-18-edition-context-axis/2207_create_card_edition_context_external_mapping.sql',None),
                      ('schema/2095_create_normalize_external_catalog_value_function.sql',None)]:
    src=(REPO/f).read_text(encoding='utf-8')
    for m in re.finditer(r'CREATE OR REPLACE FUNCTION ([a-z_]+)\.([a-z_]+)\(([^)]*)\)(.*?)AS \$\$(.*?)\$\$;',src,re.S):
        nsp,name,args,hdr,body=m.groups()
        ida=' '.join(args.lower().split())
        lang=re.search(r'LANGUAGE (\w+)',hdr).group(1)
        vol='s' if 'STABLE' in hdr else ('i' if 'IMMUTABLE' in hdr else 'v')
        real[nsp+'.'+name]=(nsp,name,ida,lang,'SECURITY DEFINER' in hdr,vol,['search_path=""'],body)
real['extensions.unaccent(text)']=('extensions','unaccent','text','c',False,'s',None,'unaccent_dict')
real['extensions.unaccent(regdictionary, text)']=('extensions','unaccent','regdictionary, text','c',False,'s',None,'unaccent_dict')
EXT={'unaccent':{'extensions.unaccent(text)','extensions.unaccent(regdictionary, text)'}}
chk('P7 modelo: 12 funções reais carregadas', len(real)==12, str(len(real)))
ok,why=p7_gate(real,EXT)
chk('P7 CONTROLE POSITIVO: definições reais do repositório passam (sem falso STOP)', ok, '; '.join(why[:5]))
def body_with(extra): return '\nBEGIN\n'+extra+'\n    RETURN NEW;\nEND;\n'
EXPECT={
 'chamada NÃO qualificada a função desconhecida':'g_p7_no_unresolved',
 'chamada NÃO qualificada a builtin negado (pg_notify)':'g_p7_no_unresolved',
 'DML NÃO qualificado (UPDATE card_variant)':'g_p7_no_unqualified_dml',
 'DML NÃO qualificado (INSERT INTO audit_log)':'g_p7_no_unqualified_dml',
 'DML NÃO qualificado com ONLY (DELETE FROM ONLY t)':'g_p7_no_unqualified_dml',
 'DML qualificado FORA do escopo (public.card_variant)':'g_p7_writes_in_scope',
 'DML qualificado para relação inexistente (public.ghost)':'g_p7_writes_in_scope',
 'chamada qualificada NÃO resolvida (internal.ghost_fn)':'g_p7_no_unresolved',
 'função permitida pelo NOME com corpo alterado (md5)':'g_p7_identity_pinned',
 'função permitida pelo NOME com assinatura diferente':'g_p7_all_classified',
 'função permitida com SECURITY DEFINER divergente':'g_p7_identity_pinned',
 'função permitida com linguagem divergente':'g_p7_identity_pinned',
 'função C permitida com símbolo divergente':'g_p7_identity_pinned',
 'search_path ausente':'g_p7_search_path_safe',
 'search_path inseguro (public)':'g_p7_search_path_safe',
 'search_path duplicado':'g_p7_search_path_safe',
 'search_path com pg_temp':'g_p7_search_path_safe',
 'função não classificada alcançada':'g_p7_all_classified',
 'SQL dinâmico (EXECUTE)':'g_p7_no_external_or_dynamic',
 'E-string escondendo conteúdo':'g_p7_lexically_supported',
 'dollar-quote interno':'g_p7_lexically_supported',
 'identificador entre aspas duplas chamado':'g_p7_lexically_supported',
 'nome em três partes':'g_p7_lexically_supported',
 'espaço entre schema, ponto e função (x . f)':'g_p7_no_unresolved',
 'chamada aninhada não qualificada (f(g(x)))':'g_p7_no_unresolved',
 'sinal de efeito externo (net.http_post)':'g_p7_no_external_or_dynamic',
 'DDL estático no corpo (CREATE TEMP TABLE)':'g_p7_no_ddl',
 'DDL estático no corpo (GRANT)':'g_p7_no_ddl',
 'DDL estático no corpo (COMMENT ON)':'g_p7_no_ddl',
 'função sql com SELECT INTO (cria tabela)':'g_p7_no_ddl',
 'EOL: CR isolado (não é CRLF) no corpo pinado':'g_p7_identity_pinned',
 'EOL: CRLF + alteração de conteúdo':'g_p7_identity_pinned',
 'EOL: CRLF + SECURITY DEFINER divergente':'g_p7_identity_pinned'}
def neg(label, fns):
    ok,why=p7_gate(fns,EXT); exp=EXPECT[label]
    chk('P7 CONTROLE NEGATIVO bloqueado: '+label+' [gate '+exp+']', (not ok) and any(w.startswith(exp+':') for w in why), 'motivos='+str(why[:3]))
    return why
base=dict(real)
def mut_body(fq, newbody):
    d=dict(base); t=list(d[fq]); t[7]=newbody; d[fq]=tuple(t); return d
evil=('internal','evil_fn','', 'plpgsql', True,'v',['search_path=""'], body_with('    PERFORM 1;'))
neg('chamada NÃO qualificada a função desconhecida', {**base,'x':('internal','x_trigger','','plpgsql',True,'v',['search_path=""'],body_with('    NEW.a := evil_fn(1);'))})
neg('chamada NÃO qualificada a builtin negado (pg_notify)', mut_body('internal.guard_edition_context_trait_active', body_with("    PERFORM pg_notify('c', 'x');")))
neg('DML NÃO qualificado (UPDATE card_variant)', mut_body('internal.guard_edition_context_trait_active', body_with('    UPDATE card_variant SET is_default = false;')))
neg('DML NÃO qualificado (INSERT INTO audit_log)', mut_body('internal.guard_edition_context_trait_active', body_with('    INSERT INTO audit_log (a) VALUES (1);')))
neg('DML NÃO qualificado com ONLY (DELETE FROM ONLY t)', mut_body('internal.guard_edition_context_trait_active', body_with('    DELETE FROM ONLY t WHERE true;')))
neg('DML qualificado FORA do escopo (public.card_variant)', mut_body('internal.guard_edition_context_trait_active', body_with('    UPDATE public.card_variant SET is_default = false;')))
neg('DML qualificado para relação inexistente (public.ghost)', mut_body('internal.guard_edition_context_trait_active', body_with('    DELETE FROM public.ghost;')))
neg('chamada qualificada NÃO resolvida (internal.ghost_fn)', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM internal.ghost_fn(1);')))
neg('função permitida pelo NOME com corpo alterado (md5)', mut_body('internal.guard_edition_context_trait_active', real['internal.guard_edition_context_trait_active'][7].replace('RETURN NEW;','RETURN NULL;')))
d=dict(base); t=list(d['public.normalize_external_catalog_value']); t[2]='p_value text, p_extra text'; d['public.normalize_external_catalog_value']=tuple(t)
neg('função permitida pelo NOME com assinatura diferente', d)
d=dict(base); t=list(d['internal.seal_edition_context_composition']); t[4]=False; d['internal.seal_edition_context_composition']=tuple(t)
neg('função permitida com SECURITY DEFINER divergente', d)
d=dict(base); t=list(d['public.normalize_external_catalog_value']); t[3]='plpgsql'; d['public.normalize_external_catalog_value']=tuple(t)
neg('função permitida com linguagem divergente', d)
d=dict(base); t=list(d['extensions.unaccent(text)']); t[7]='evil_symbol'; d['extensions.unaccent(text)']=tuple(t)
neg('função C permitida com símbolo divergente', d)
neg('função C permitida fora da extensão', {k:v for k,v in base.items()} ) if False else None
ok_ext,_=p7_gate(base,{'unaccent':set()}); chk('P7 CONTROLE NEGATIVO bloqueado: função C permitida sem pertença à extensão', not ok_ext)
for label,cfg in [('search_path ausente',None),('search_path inseguro (public)',['search_path=public']),
                  ('search_path duplicado',['search_path=""','search_path=public']),('search_path com pg_temp',['search_path=pg_temp'])]:
    d=dict(base); t=list(d['internal.guard_edition_context_trait_active']); t[6]=cfg; d['internal.guard_edition_context_trait_active']=tuple(t)
    neg(label, d)
neg('função não classificada alcançada', {**base,'internal.evil_fn':evil})
neg('SQL dinâmico (EXECUTE)', mut_body('internal.guard_edition_context_trait_active', body_with("    EXECUTE 'SELECT 1';")))
neg('E-string escondendo conteúdo', mut_body('internal.guard_edition_context_trait_active', body_with("    NEW.a := E'x\\\\' ; evil_fn(1) ; ''';")))
neg('dollar-quote interno', mut_body('internal.guard_edition_context_trait_active', body_with("    NEW.a := $q$ x $q$;")))
neg('identificador entre aspas duplas chamado', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM "evil"(1);')))
neg('nome em três partes', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM db.internal.evil_fn(1);')))
neg('espaço entre schema, ponto e função (x . f)', mut_body('internal.guard_edition_context_trait_active', body_with('    PERFORM internal . evil_fn(1);')))
neg('chamada aninhada não qualificada (f(g(x)))', mut_body('internal.guard_edition_context_trait_active', body_with('    NEW.a := upper(evil_fn(1));')))
neg('sinal de efeito externo (net.http_post)', mut_body('internal.guard_edition_context_trait_active', body_with("    PERFORM net.http_post('u');")))
# controles positivos de NÃO-falso-STOP: comentário/literal/lock não são dependências
fine=body_with("    -- UPDATE que não é DML: evil_fn( update card_variant\n    /* INSERT INTO ghost (x) */\n    NEW.a := 'texto com evil_fn(1) e UPDATE card_variant';\n    PERFORM 1 FROM public.card_edition_context_trait t WHERE t.id = NEW.trait_id FOR UPDATE;")
d=mut_body('internal.guard_edition_context_trait_active', fine);
# ajusta o pino md5 do corpo modificado só neste controle positivo
key=('internal','guard_edition_context_trait_active',''); saved=dict(ALLOW[key]); ALLOW[key]['md5']=hashlib.md5(fine.encode()).hexdigest()
ok,why=p7_gate(d,EXT); ALLOW[key]=saved
chk('P7 CONTROLE POSITIVO: comentário, literal e FOR UPDATE não geram dependência', ok, '; '.join(why))


# ---------------------------------------------------------------------------
# STOP-ADJUDICATION-01 (proposta): D-6 (EOL), P7 sem DDL, P7-EVT (event
# triggers). Sem banco. Os valores LIVE usados abaixo vêm da Tentativa 03
# (LIVE-STAGE1-EXECUTION-RECORD.md §6) e são citados como evidência, não
# consultados.
# ---------------------------------------------------------------------------
# D-6.1 — pinos = md5 do corpo do repositório normalizado (os dois lados)
for (nsp,name,ida),a in ALLOW.items():
    if a['md5'] is None: continue
    fq=nsp+'.'+name
    chk(f'D-6: pino de {fq} = md5(LF(corpo do repositório))', fq in real and hashlib.md5(lf(real[fq][7]).encode()).hexdigest()==a['md5'])
    chk(f'D-6: corpo do repositório de {fq} sem CR', fq in real and '\r' not in real[fq][7])
chk('D-6: E00 compara md5(replace(prosrc, CRLF, LF)) com o pino', "md5(replace(f.prosrc, chr(13) || chr(10), chr(10))) IS DISTINCT FROM a.body_md5" in c00)
chk('D-6: E00 não compara mais md5(prosrc) bruto com o pino', 'md5(f.prosrc) IS DISTINCT FROM a.body_md5' not in c00)
chk('D-6: E00 exporta md5 bruto + LF + cr_count + crlf_count + d_p7_eol_normalized',
    all(x in c00 for x in ["'body_md5', CASE","'body_md5_lf', CASE","'cr_count',","'crlf_count',","'d_p7_eol_normalized',"]))
# D-6.2 — reprodução da evidência LIVE (Tentativa 03): o corpo do repositório com LF→CRLF
nec='public.normalize_external_catalog_value'
live_nec=real[nec][7].replace('\n','\r\n')
chk('D-6 EVIDÊNCIA: repo LF→CRLF reproduz md5_raw LIVE 81361bb8… (L2)', hashlib.md5(live_nec.encode()).hexdigest()=='81361bb8f52ce142803d69c2b3028ae8')
chk('D-6 EVIDÊNCIA: len 104 e cr_count 2 iguais à L2', len(live_nec)==104 and live_nec.count('\r')==2)
chk('D-6 EVIDÊNCIA: md5 LF do corpo LIVE reconstruído = pino 1fdc2e7e…', hashlib.md5(lf(live_nec).encode()).hexdigest()=='1fdc2e7ebe2297f8db85be4aad2e5d33')
ok,why=p7_gate(mut_body(nec, live_nec),EXT)
chk('D-6 CONTROLE POSITIVO: corpo LIVE (CRLF) com demais atributos iguais passa o pino normalizado', ok, '; '.join(why[:3]))
neg('EOL: CR isolado (não é CRLF) no corpo pinado', mut_body(nec, real[nec][7].replace('\n','\r',1)))
neg('EOL: CRLF + alteração de conteúdo', mut_body(nec, live_nec.replace("' '","'_'")))
d=mut_body(nec, live_nec); t=list(d[nec]); t[4]=True; d[nec]=tuple(t)
neg('EOL: CRLF + SECURITY DEFINER divergente', d)
# P7 sem DDL — corpos reais sem DDL + controles negativos
for fq,v in real.items():
    if v[3] in ('c','internal'): continue
    lx=R['lex'].sub(' ',v[7])
    chk(f'P7-DDL: corpo real de {fq} sem comando DDL', not R['ddl_lexed'].search(lx) and not (v[3]=='sql' and R['sql_into_lexed'].search(lx)))
tg='internal.guard_edition_context_trait_active'
neg('DDL estático no corpo (CREATE TEMP TABLE)', mut_body(tg, body_with('    CREATE TEMP TABLE x (a int);')))
neg('DDL estático no corpo (GRANT)', mut_body(tg, body_with('    GRANT SELECT ON public.card_edition_context_trait TO anon;')))
neg('DDL estático no corpo (COMMENT ON)', mut_body(tg, body_with("    COMMENT ON TABLE public.card_edition_context_trait IS 'x';")))
neg('função sql com SELECT INTO (cria tabela)', mut_body(nec, "\n    SELECT 1 INTO public.ghost;\n"))
fine_ddl=body_with("    -- CREATE TABLE em comentário\n    NEW.a := 'DROP TABLE em literal';\n    NEW.created_at := now();")
key=('internal','guard_edition_context_trait_active',''); saved=dict(ALLOW[key]); ALLOW[key]['md5']=hashlib.md5(fine_ddl.encode()).hexdigest()
ok,why=p7_gate(mut_body(tg, fine_ddl),EXT); ALLOW[key]=saved
chk('P7-DDL CONTROLE POSITIVO: DDL em comentário/literal e identificador created_at não disparam', ok, '; '.join(why))

# P7-EVT — event triggers (CORRECTION-01: G-2 lógica de 3 valores, G-3 completude, G-4 identidade de 12 atributos)
DDL_EVENTS={'ddl_command_start','ddl_command_end','sql_drop','table_rewrite'}
EVT_EQ=['name','event','enabled','owner','fn','fn_language','fn_owner','fn_secdef','fn_md5_lf']   # '=' do SQL: NULL nunca casa
EVT_INDF=['tags','fn_config','fn_extension']                                                       # IS NOT DISTINCT FROM: NULL é estado pinado
EVT_ID=['name','event','tags','enabled','owner','fn','fn_language','fn_owner','fn_secdef','fn_config','fn_extension','fn_md5_lf']
m=re.search(r"evt_allowlist\((.*?)\) AS \(\s*(.*?)\n\),",e00,re.S)
chk('EVT: evt_allowlist presente no E00', m is not None)
EVT_COLS=[x.strip() for x in m.group(1).split(',')] if m else []
chk('EVT: evt_allowlist = 12 atributos de identidade + justification (G-4)', EVT_COLS==EVT_ID+['justification'], str(EVT_COLS))
allow_body=m.group(2) if m else ''
def allow_rows(txt):
    """Extrai linhas VALUES (...) de um texto de allowlist; cada linha vira lista de literais."""
    rows=[]
    for r in re.findall(r"^\s*\(('(?:[^']|'')*'.*?)\),?\s*$",txt,re.M):
        f=re.findall(r"ARRAY\[[^\]]*\](?:::text\[\])?|'(?:[^']|'')*'|true|false|NULL(?:::[a-z\[\]]+)?",r)
        rows.append(f)
    return rows
def row_valid(f):
    """Regras para QUALQUER linha futura: 13 campos; justification não vazia; evento DDL; nenhum atributo de '=' em NULL."""
    if len(f)!=13: return False
    d=dict(zip(EVT_ID+['justification'],f))
    lit=lambda x: None if x.startswith('NULL') else x
    if lit(d['justification']) is None or not re.sub(r"^'|'$","",d['justification']).strip(): return False
    if lit(d['event']) is None or d['event'].strip("'") not in DDL_EVENTS: return False
    if any(lit(d[k]) is None for k in EVT_EQ): return False
    return True
ROWS=allow_rows(allow_body)
# D-9 APROVADA (BATCH12-2830-D9-EVENT-TRIGGER-ALLOWLIST-01): EXATAMENTE as 6 identidades da L4, pinadas aqui e
# conferidas contra a saída integral da L4 registrada em LIVE-STAGE1-EXECUTION-RECORD.md (proveniência).
def lit2py(x):
    x=x.strip()
    if x.startswith('NULL'): return None
    if x in ('true','false'): return x=='true'
    if x.startswith('ARRAY['): return [v.replace("''","'") for v in re.findall(r"'((?:[^']|'')*)'",x)]
    return x[1:-1].replace("''","'")
_A=('supabase_admin','plpgsql',False,['search_path=""'],None)
D9_AUTH={
 'issue_graphql_placeholder':('sql_drop',['DROP EXTENSION'],'extensions.set_graphql_placeholder()','a2bc2d00b2cc2f5e8d2d6b8d73e2c360','EXCEPCIONAL',['CREATE OR REPLACE FUNCTION graphql_public.graphql','placeholder']),
 'issue_pg_cron_access':('ddl_command_end',['CREATE EXTENSION'],'extensions.grant_pg_cron_access()','3a3917aad6ddd66182bf45b7490c3029','EXCEPCIONAL',['ALTER DEFAULT PRIVILEGES','pg_cron']),
 'issue_pg_graphql_access':('ddl_command_end',['CREATE EXTENSION'],'extensions.grant_pg_graphql_access()','dd3f3e2bb94cff45ef24b9cecb6af1c8','EXCEPCIONAL',['DROP FUNCTION','ALTER EXTENSION','GRANT EXECUTE','concessões de privilégios']),
 'issue_pg_net_access':('ddl_command_end',['CREATE EXTENSION'],'extensions.grant_pg_net_access()','2ee4e6920eeba3068bcfa838105352e2','EXCEPCIONAL',['CREATE USER','acesso à rede','SECURITY DEFINER']),
 'pgrst_ddl_watch':('ddl_command_end',None,'extensions.pgrst_ddl_watch()','7f27b8118fea5c88b0164331292859e3','ORDINÁRIO',['tags NULL','NOTIFY pgrst','superfície ampla']),
 'pgrst_drop_watch':('sql_drop',None,'extensions.pgrst_drop_watch()','bc09cc3003d66f91844af4cb05e203b7','ORDINÁRIO',['tags NULL','NOTIFY pgrst','superfície ampla'])}
def d9_ident(n):
    ev,tags,fn,md5,_,_t=D9_AUTH[n]
    return dict(name=n,event=ev,tags=tags,enabled='O',owner=_A[0],fn=fn,fn_language=_A[1],fn_owner=_A[0],fn_secdef=_A[2],fn_config=_A[3],fn_extension=_A[4],fn_md5_lf=md5)
ALLOW_PY=[dict(zip(EVT_ID+['justification'],[lit2py(x) for x in r])) for r in ROWS]
chk('D-9: evt_allowlist tem EXATAMENTE 6 linhas, sem nome repetido', len(ROWS)==6 and len({a['name'] for a in ALLOW_PY})==6, str(len(ROWS)))
chk('D-9: conjunto de nomes = os 6 aprovados', {a['name'] for a in ALLOW_PY}==set(D9_AUTH))
for a in ALLOW_PY:
    n=a['name']
    if n not in D9_AUTH: continue
    exp=d9_ident(n)
    chk(f'D-9 {n}: 12 atributos = pino aprovado (tipos, arrays, NULL e md5 integral)', all(a[k]==exp[k] and type(a[k])==type(exp[k]) for k in EVT_ID), str([k for k in EVT_ID if a[k]!=exp[k]]))
    j=a['justification'] or ''
    cat,terms=D9_AUTH[n][4],D9_AUTH[n][5]
    chk(f'D-9 {n}: justificativa (a)-(f), L4, md5, categoria {cat}, restrição aos envelopes atuais e termos obrigatórios',
        all(t in j for t in ['(a)','(b)','(c)','(d)','(e)','(f)','D-9 APROVADA','ACEITE '+cat,'BATCH12-2830-LIVE-L4-EVENT-TRIGGER-INVENTORY-01',exp['fn_md5_lf'],'Aceite restrito aos envelopes atuais','não autoriza novas operações, migrations nem DDL','Reavaliar']+terms), n)
_rows_txt=[l for l in allow_body.splitlines() if l.strip().startswith("('")]
chk('D-9: tipagem explícita em todas as linhas (text[] em tags/fn_config, NULL::text em fn_extension, booleano literal)',
    len(_rows_txt)==6 and all(('::text[]' in l and ", false, ARRAY[" in l and "NULL::text, '" in l) for l in _rows_txt))
# proveniência: pinos = saída integral da L4 registrada
_rec=(H/'LIVE-STAGE1-EXECUTION-RECORD.md').read_text(encoding='utf-8')
_l4sec=_rec[_rec.index('## L4 — inventário de event triggers'):] if '## L4 — inventário de event triggers' in _rec else ''
_l4blk=re.findall(r"```json\n(.*?)\n```",_l4sec,re.S)
chk('D-9 PROVENIÊNCIA: saída integral da L4 presente no registro (md5 fc0d8cf7…)', bool(_l4blk) and hashlib.md5(_l4blk[0].encode()).hexdigest()=='fc0d8cf7595bbcb84f544211612cede4')
_L4=json.loads(_l4blk[0])[0]['l4']['l4_event_triggers'] if _l4blk else {'triggers':[]}
_L4ID={t['name']:{k:t[k] for k in EVT_ID} for t in _L4['triggers']}
chk('D-9 PROVENIÊNCIA: cada linha da allowlist = identidade da L4 (12 atributos, literal)', len(_L4ID)==6 and all(_L4ID.get(a['name'])=={k:a[k] for k in EVT_ID} for a in ALLOW_PY))
chk('D-9 PROVENIÊNCIA: L4 íntegra (triggers_md5 recalculado)', bool(_L4['triggers']) and hashlib.md5(json.dumps(_L4['triggers'],ensure_ascii=False,separators=(', ',': ')).encode()).hexdigest()==_L4.get('triggers_md5'))
chk('EVT: toda linha presente na allowlist é válida (vácuo verdadeiro com 0 linhas)', all(row_valid(r) for r in ROWS))
GOOD="  ('pgrst_ddl_watch', 'ddl_command_end', NULL::text[], 'O', 'supabase_admin', 'extensions.pgrst_ddl_watch()', 'plpgsql', 'supabase_admin', true, NULL::text[], NULL, '"+'0'*32+"', 'L4 <prov>; justificativa (a)-(f)'),"
chk('EVT VALIDADOR controle positivo: linha sintética completa é aceita', row_valid(allow_rows(GOOD)[0]))
for label,bad in [('justificativa vazia',GOOD.replace("'L4 <prov>; justificativa (a)-(f)'","''")),
                  ('justificativa só com espaços',GOOD.replace("'L4 <prov>; justificativa (a)-(f)'","'   '")),
                  ('justificativa NULL',GOOD.replace("'L4 <prov>; justificativa (a)-(f)'","NULL")),
                  ('evento login',GOOD.replace("'ddl_command_end'","'login'")),
                  ('fn_md5_lf NULL',GOOD.replace("'"+'0'*32+"'","NULL")),
                  ('fn_secdef NULL',GOOD.replace(", true,",", NULL,")),
                  ('owner NULL',GOOD.replace("'O', 'supabase_admin'","'O', NULL")),
                  ('linha sem justification (12 campos)',GOOD.replace(", 'L4 <prov>; justificativa (a)-(f)'",""))]:
    chk('EVT VALIDADOR CONTROLE NEGATIVO rejeita linha futura: '+label, not row_valid(allow_rows(bad)[0]))
un=re.search(r"evt_unadjudicated AS \((.*?)\n\),",c00,re.S).group(1)
for col in EVT_EQ:
    chk(f"EVT: casamento a.{col} = e.{col} (NULL nunca casa)", re.search(r'\ba\.'+col+r'\s*=\s*e\.'+col+r'\b',un) is not None)
for col in EVT_INDF:
    chk(f"EVT: casamento a.{col} IS NOT DISTINCT FROM e.{col}", ('a.'+col+' IS NOT DISTINCT FROM e.'+col) in un)
chk("EVT: justificativa obrigatória também no SQL (NULLIF(btrim(a.justification), '') IS NOT NULL)", "NULLIF(btrim(a.justification), '') IS NOT NULL" in un)
chk("EVT: exceção só para evento DDL (lista literal no casamento)", "a.event IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite')" in un)
chk("EVT: g_evt_ddl_only com a mesma lista DDL", "event NOT IN ('ddl_command_start','ddl_command_end','sql_drop','table_rewrite'))" in c00)
chk('EVT: inventário exporta identidade completa (tags, owner, fn, secdef, proconfig, extensão, md5 bruto e LF)',
    all(x in c00 for x in ['e.evttags','pg_get_userbyid(e.evtowner)','AS fn_secdef','AS fn_config','AS fn_extension','AS fn_md5_raw','AS fn_md5_lf']))
_evt=re.search(r"\nevt AS \((.*?)\n\),",c00,re.S).group(1)
chk('EVT G-3: CTE evt sem filtro — termina nos JOINs (nenhum WHERE fora da subconsulta de extensão)',
    _evt.rstrip().endswith('JOIN pg_language l  ON l.oid = p.prolang') and len(re.findall(r'\bWHERE\b',_evt))==1 and 'FROM pg_event_trigger e' in _evt)
chk('EVT G-3: g_evt_inventory_complete compara count(pg_event_trigger) DIRETO com count(evt)',
    re.search(r"\(SELECT count\(\*\) FROM pg_catalog\.pg_event_trigger\) = \(SELECT count\(\*\) FROM evt\)\s*AS g_evt_inventory_complete",c00) is not None)
chk("EVT: d_evt_catalog_count, d_evt_unadjudicated e d_evt_allowlist_absent exportados", all(x in c00 for x in ["'d_evt_catalog_count',","'d_evt_unadjudicated',","'d_evt_allowlist_absent',"]))
def eq3(a,b): return a is not None and b is not None and a==b      # SQL '='
def indf(a,b): return a==b                                          # IS NOT DISTINCT FROM
def evt_gate(live, allow, catalog_count=None):
    """Modelo com semântica SQL (G-2). catalog_count = count(pg_event_trigger) lido direto (G-3)."""
    reasons=[]
    if catalog_count is not None and catalog_count!=len(live): reasons.append('g_evt_inventory_complete:'+str(catalog_count)+'!='+str(len(live)))
    for e in live:
        if e['enabled']=='D': continue
        if e['event'] not in DDL_EVENTS: reasons.append('g_evt_ddl_only:'+e['name'])
        if not any(a['event'] in DDL_EVENTS and all(eq3(a[k],e[k]) for k in EVT_EQ) and all(indf(a[k],e[k]) for k in EVT_INDF)
                   and a.get('justification') is not None and a['justification'].strip()!='' for a in allow):
            reasons.append('g_evt_all_adjudicated:'+e['name'])
    return (not reasons, reasons)
def evt_join(catalog, procs):
    """Simula o CTE evt: JOIN interno de pg_event_trigger com pg_proc (trigger sem função some)."""
    return [dict(t, **procs[t['foid']]) for t in catalog if t['foid'] in procs]
# inventário da Tentativa 03 (nome, evento, estado = evidência LIVE; demais campos SINTÉTICOS só para o modelo)
T03=[('issue_graphql_placeholder','sql_drop'),('pgrst_ddl_watch','ddl_command_end'),('pgrst_drop_watch','sql_drop'),
     ('issue_pg_cron_access','ddl_command_end'),('issue_pg_net_access','ddl_command_end'),('issue_pg_graphql_access','ddl_command_end')]
live=[dict(name=n,event=ev,enabled='O',tags=None,owner='SYNTH_owner',fn='SYNTH.'+n+'()',fn_language='plpgsql',fn_owner='SYNTH_owner',
           fn_secdef=False,fn_config=None,fn_extension=None,fn_md5_lf='0'*32) for n,ev in T03]
ok,why=evt_gate(live,[],6)
chk('EVT REPRODUÇÃO: 6 habilitados + allowlist vazia ⇒ STOP (igual à Tentativa 03)', (not ok) and len([w for w in why if w.startswith('g_evt_all_adjudicated:')])==6)
allow=[dict(e,justification='L4 <prov>; justificativa (a)-(f)') for e in live]
ok,_=evt_gate(live,allow,6); chk('EVT CONTROLE POSITIVO: identidade completa adjudicada, NULL=NULL em tags/fn_config/fn_extension ⇒ passa', ok)
def evt_neg(label, live2, allow2, gate, cc=None):
    ok,why=evt_gate(live2,allow2,len(live2) if cc is None else cc)
    chk('EVT CONTROLE NEGATIVO bloqueado: '+label+' [gate '+gate+']', (not ok) and any(w.startswith(gate+':') for w in why), str(why[:2]))
def mut(i,**kw):
    l2=[dict(e) for e in live]; l2[i].update(kw); return l2
for fld,val in [('fn_md5_lf','f'*32),('fn','extensions.evil()'),('tags',['CREATE EXTENSION']),('owner','postgres'),('fn_owner','postgres'),
                ('fn_language','sql'),('enabled','A'),('event','ddl_command_start'),('name','renamed_hook')]:
    evt_neg(f'mesmo trigger, {fld} divergente', mut(1,**{fld:val}), allow, 'g_evt_all_adjudicated')
# G-4: alterações isoladas dos atributos novos
evt_neg('fn_secdef false→true (isolado)', mut(2,fn_secdef=True), allow, 'g_evt_all_adjudicated')
evt_neg('fn_config NULL→{search_path=""} (isolado)', mut(2,fn_config=['search_path=""']), allow, 'g_evt_all_adjudicated')
a2=[dict(a) for a in allow]; a2[2]['fn_config']=['search_path=""']
evt_neg('fn_config {search_path=""}→NULL (isolado)', live, a2, 'g_evt_all_adjudicated')
evt_neg('fn_config {search_path=""}→{search_path=public} (isolado)', mut(2,fn_config=['search_path=public']), a2, 'g_evt_all_adjudicated')
evt_neg('fn_extension NULL→pg_net (isolado)', mut(2,fn_extension='pg_net'), allow, 'g_evt_all_adjudicated')
a3=[dict(a) for a in allow]; a3[2]['fn_extension']='pg_graphql'
evt_neg('fn_extension pg_graphql→NULL (isolado)', live, a3, 'g_evt_all_adjudicated')
evt_neg('fn_extension pg_graphql→pg_net (isolado)', mut(2,fn_extension='pg_net'), a3, 'g_evt_all_adjudicated')
# G-2: NULL com semântica SQL
for k in ['owner','fn','fn_md5_lf','fn_secdef']:
    a4=[dict(a) for a in allow]; a4[4][k]=None; l4=mut(4,**{k:None})
    evt_neg(f'NULL em {k} nos dois lados não casa (= do SQL)', l4, a4, 'g_evt_all_adjudicated')
a5=[dict(a) for a in allow]; a5[1]['tags']=['CREATE EXTENSION']
evt_neg('evttags: allowlist com tag × LIVE NULL', live, a5, 'g_evt_all_adjudicated')
evt_neg('evttags: mesma lista em outra ordem', mut(1,tags=['B','A']), [dict(a,tags=['A','B']) if a['name']==live[1]['name'] else a for a in allow], 'g_evt_all_adjudicated')
# justificativa obrigatória (espelho do NULLIF(btrim(...)))
for lab,j in [('vazia',''),('só espaços','   '),('NULL',None)]:
    evt_neg(f'justificativa {lab} não adjudica', live, [dict(a,justification=j) for a in allow], 'g_evt_all_adjudicated')
evt_neg('trigger novo não adjudicado', live+[dict(live[0],name='evil_ddl_hook')], allow, 'g_evt_all_adjudicated')
login=dict(live[0],name='on_login_x',event='login')
evt_neg('evento login mesmo com linha na allowlist', live+[login], allow+[dict(login,justification='x')], 'g_evt_ddl_only')
evt_neg('evento login: allowlist não o torna adjudicado', live+[login], allow+[dict(login,justification='x')], 'g_evt_all_adjudicated')
ok,_=evt_gate(live+[dict(live[0],name='disabled_x',enabled='D')],allow,7); chk('EVT CONTROLE POSITIVO: trigger desabilitado (D) é inventariado sem efeito de gate', ok)
# G-3: incompletude do inventário (JOIN interno perde trigger cuja função não é encontrada)
cat=[dict(name=n,event=ev,enabled='O',tags=None,owner='SYNTH_owner',foid=i) for i,(n,ev) in enumerate(T03)]
procs={i:dict(fn='SYNTH.'+n+'()',fn_language='plpgsql',fn_owner='SYNTH_owner',fn_secdef=False,fn_config=None,fn_extension=None,fn_md5_lf='0'*32) for i,(n,ev) in enumerate(T03)}
inv=evt_join(cat,procs); ok,_=evt_gate(inv,allow,len(cat)); chk('EVT G-3 CONTROLE POSITIVO: catálogo 6 = inventário 6, adjudicado ⇒ passa', ok and len(inv)==6)
p2=dict(procs); del p2[3]; inv2=evt_join(cat,p2)
evt_neg('inventário incompleto: função não encontrada some do JOIN (catálogo 6 × evt 5)', inv2, allow, 'g_evt_inventory_complete', cc=len(cat))
cat2=cat+[dict(name='ghost_hook',event='ddl_command_end',enabled='O',tags=None,owner='x',foid=99)]
evt_neg('inventário incompleto: trigger adicional sem função resolvida (catálogo 7 × evt 6)', evt_join(cat2,procs), allow, 'g_evt_inventory_complete', cc=len(cat2))
# Envelopes autorizados não emitem comando da matriz de disparo (DDL/GRANT/COMMENT/SECURITY LABEL/SELECT INTO de SQL puro)
for f in ['2830H_E00_precheck_inventory.sql','2830H_E99_postcheck_residue.sql']:
    raw=re.sub(r"\$re\$.*?\$re\$","''",(H/f).read_text(encoding='utf-8'),flags=re.S); U=nostr(code(raw)).upper()
    chk(f'EVT: {f} (SQL puro) sem comando da matriz de disparo nem SELECT INTO', not re.search(r'\b(CREATE|ALTER|DROP|GRANT|REVOKE|COMMENT|SECURITY\s+LABEL|INTO|REINDEX|REFRESH|IMPORT)\b',U))
for f,tag in [('2830H_E01_section1_structural.sql','h2830_e01'),('2830H_E02_identity_terminal_D1_D5.sql','h2830_e02')]:
    body=nostr(code((H/f).read_text(encoding='utf-8')).split('$'+tag+'$')[1]).upper()
    chk(f'EVT: {f} (PL/pgSQL) sem comando da matriz de disparo (SELECT … INTO é atribuição PL/pgSQL)', not re.search(r'\b(CREATE|ALTER|DROP|GRANT|REVOKE|COMMENT|SECURITY\s+LABEL|REINDEX|REFRESH|IMPORT|EXECUTE)\b',body))

# D-9 — modelo com a allowlist REAL do E00 contra o inventário REAL da L4
REAL_LIVE=[dict(v) for v in _L4ID.values()]
ok,why=evt_gate(REAL_LIVE,ALLOW_PY,len(REAL_LIVE))
chk('D-9 CONTROLE POSITIVO: allowlist real × inventário real da L4 ⇒ g_evt_all_adjudicated e g_evt_inventory_complete passam', ok and len(REAL_LIVE)==6, str(why[:2]))
ALT={'name':'x_renamed','event':'ddl_command_start','tags':['ALTER TABLE'],'enabled':'A','owner':'postgres','fn':'extensions.evil()','fn_language':'sql',
     'fn_owner':'postgres','fn_secdef':True,'fn_config':['search_path=public'],'fn_extension':'pg_net','fn_md5_lf':'f'*32}
_n=_f=0
for i,t in enumerate(REAL_LIVE):
    for k in EVT_ID:
        l2=[dict(x) for x in REAL_LIVE]; l2[i][k]=ALT[k]
        if k=='tags' and t['tags'] is not None: l2[i][k]=None          # tags com filtro → NULL (superfície ampliada)
        ok,why=evt_gate(l2,ALLOW_PY,len(l2)); _n+=1; _f+= (not ok) and any(w.startswith('g_evt_all_adjudicated:') for w in why)
chk(f'D-9 CONTROLE NEGATIVO: alteração isolada de cada um dos 12 atributos em cada um dos 6 triggers reais reprova ({_f}/{_n})', _f==_n==72)
evt_neg('D-9 real: trigger adicional além dos 6', REAL_LIVE+[dict(REAL_LIVE[4],name='pgrst_extra_watch')], ALLOW_PY, 'g_evt_all_adjudicated')
evt_neg('D-9 real: linha removida da allowlist (5 de 6)', REAL_LIVE, [a for a in ALLOW_PY if a['name']!='issue_pg_net_access'], 'g_evt_all_adjudicated')
evt_neg('D-9 real: justificativa esvaziada', REAL_LIVE, [dict(a,justification='  ') if a['name']=='pgrst_ddl_watch' else a for a in ALLOW_PY], 'g_evt_all_adjudicated')
evt_neg('D-9 real: inventário incompleto (catálogo 7 × evt 6)', REAL_LIVE, ALLOW_PY, 'g_evt_inventory_complete', cc=7)
evt_neg('D-9 real: evento login adicionado, mesmo copiando identidade para a allowlist', REAL_LIVE+[dict(REAL_LIVE[0],name='on_login',event='login')], ALLOW_PY+[dict(ALLOW_PY[0],name='on_login',event='login')], 'g_evt_ddl_only')
ok,_=evt_gate(REAL_LIVE+[dict(REAL_LIVE[0],name='disabled_hook',enabled='D')],ALLOW_PY,7); chk('D-9 CONTROLE POSITIVO: trigger adicional DESABILITADO não reprova (inventariado)', ok)

# ---------------------------------------------------------------------------
# CORRECTION-01 (G-5): roteiro reconciliado com o E00 vigente e a L4 revisada
# ---------------------------------------------------------------------------
rb=(H/'LIVE-STAGE1-RUNBOOK.md').read_text(encoding='utf-8')
_e00b=(H/'2830H_E00_precheck_inventory.sql').read_bytes()
_blob=hashlib.sha1(b'blob %d\x00'%len(_e00b)+_e00b).hexdigest(); _md5=hashlib.md5(_e00b).hexdigest()
_pc2=[l for l in rb.splitlines() if l.startswith('| PC-2 |')]
chk('ROTEIRO PC-2: exige o blob e o md5 do E00 VIGENTE (calculados deste arquivo)', len(_pc2)==1 and _blob in _pc2[0] and _md5 in _pc2[0], _blob+' '+_md5)
chk('ROTEIRO PC-2: nenhum hash antigo do E00 como critério (97410c3a, d00b7cec, a10ffd81, 470db26f, 88e9e7a4, a9352afc)', len(_pc2)==1 and not re.search(r'97410c3a|d00b7cec|a10ffd81|470db26f|88e9e7a4|a9352afc',_pc2[0]))
_e00row=[l for l in rb.splitlines() if l.startswith('| **E00** — precheck |')]
chk('ROTEIRO §0: linha do E00 com blob/md5 vigentes e sem hash antigo', len(_e00row)==1 and _blob in _e00row[0] and _md5 in _e00row[0] and not re.search(r'97410c3a|a10ffd81|88e9e7a4',_e00row[0]))
chk('ROTEIRO §3.3: submissão do E00 cita o blob vigente', re.search(r'Submeter o \*\*conteúdo integral\*\* de `2830H_E00_precheck_inventory\.sql` \(blob `'+_blob+'`', rb) is not None)
chk('ROTEIRO: cabeçalho, PC-4 e P-1 citam o protocolo v1.6',
    '`LIVE-VALIDATION-PROTOCOL.md` **v1.6**' in rb and re.search(r'^\| PC-4 \|.*protocolo \*\*v1\.6\*\*',rb,re.M) and re.search(r'^\| P-1 \|.*protocolo v1\.6',rb,re.M))
_blocks=re.findall(r"```sql\n(.*?)```",rb,re.S)
_md5s=[hashlib.md5(b.encode()).hexdigest() for b in _blocks]
_decl={k:re.search(r'^\| \*\*'+k+r'\*\*.*?md5[^`]*`([0-9a-f]{32})`',rb,re.M) for k in ['L1','L3','L2','L4']}
chk('ROTEIRO: 4 blocos SQL (L1, L3, L2, L4)', len(_blocks)==4, str(len(_blocks)))
chk('ROTEIRO: md5 declarado em §0 = md5 do bloco (L1, L3, L2, L4)', all(_decl[k] and _decl[k].group(1) in _md5s for k in _decl), str(_md5s))
L4=_blocks[3] if len(_blocks)==4 else ''
_L4u=re.sub(r"'(?:[^']|'')*'","''",L4).upper()
chk('L4: um único statement, só leitura (sem DDL/DML/SET/INTO/DO)', _L4u.count(';')==1 and not re.search(r'\b(CREATE|ALTER|DROP|GRANT|REVOKE|COMMENT|INSERT|UPDATE|DELETE|MERGE|TRUNCATE|SET|INTO|DO|EXECUTE|CALL|COPY)\b',_L4u))
chk('L4: contagem e nomes lidos DIRETO do catálogo', 'count(*)' in L4 and 'jsonb_agg(e.evtname::text ORDER BY e.evtname) AS catalog_names' in L4 and L4.count('FROM pg_catalog.pg_event_trigger e')==2)
chk('L4: inventário com LEFT JOIN (trigger sem função não some) e fn_resolved', all(x in L4 for x in ['LEFT JOIN pg_proc p','LEFT JOIN pg_namespace n','LEFT JOIN pg_language l',"'fn_resolved',  p.oid IS NOT NULL"]))
chk('L4: completude e integridade na saída (catalog_count, inventory_count, inventory_complete, triggers_md5)',
    all("'"+k+"'" in L4 for k in ['catalog_count','catalog_names','inventory_count','inventory_complete','triggers_md5','triggers']))
chk('L4: exporta os 12 atributos pinados pelo E00', all("'"+k+"'" in L4 for k in ['name','event','tags','enabled','owner','fn','fn_language','fn_owner','fn_secdef','fn_config','fn_extension','fn_md5_lf']))


e99t=(H/'2830H_E99_postcheck_residue.sql').read_text(encoding='utf-8')
chk('E99: comentário declara TRÊS marcadores (não dois)', 'EXATAMENTE TRÊS marcadores' in e99t and 'EXATAMENTE dois' not in e99t)
chk('E99: md5 declarado como fidelidade da cópia, NÃO origem da rodada', 'NÃO' in e99t and 'prova de QUAL rodada' in e99t)
chk('E99: vinculação documental E00 → envelope → E99 explícita', 'VINCULAÇÃO DOCUMENTAL' in e99t and 'checked_at(E00) < submissão do envelope' in e99t)

bad=[r for r in res if not r[1]]
for n,ok,d in res: print(('PASS ' if ok else 'FAIL ')+n+(' '+d if d and not ok else ''))
print(f'TOTAL {len(res)} PASS {len(res)-len(bad)} FAIL {len(bad)}')


# ===========================================================================
# BATCH12-2830-P5-L1-E03-IMPLEMENTATION-01 — PERFIS E03 / E03T / E03P
# Contrato: L1-E03-IMPLEMENTATION-READINESS.md v1.1 (blob 220fbd8b…), §5 e §6
# (regras E03-1 a E03-19; E03-20 = P8/DP-4 em
# BATCH12-2830-P5-L1-E03-DECISION-AND-IMPLEMENTATION-01). Contagem SEPARADA do baseline acima (444): as
# verificações novas não entram em `res`, para o baseline continuar
# reproduzível byte a byte. Três blocos, cada um com total próprio:
#   E03-PERFIL ............ regras aplicadas aos arquivos reais (E03, E03T, E03P)
#   E03-VERIFICADOR-NEG ... mutações deliberadamente inseguras que TÊM de
#                           ser rejeitadas pela regra indicada
#   E03-VERIFICADOR-POS ... controles positivos do próprio verificador
# ===========================================================================
READINESS=(H/'L1-E03-IMPLEMENTATION-READINESS.md').read_text(encoding='utf-8')
S2206=(REPO/'proposals/2026-09-18-edition-context-axis/2206_create_edition_context_composition_guards.sql').read_text(encoding='utf-8')
DDL=''.join((REPO/('proposals/2026-09-18-edition-context-axis/'+f)).read_text(encoding='utf-8') for f in
            ['2203_create_card_edition_context_trait_table.sql','2204_create_card_edition_context_profile_table.sql',
             '2205_create_card_edition_context_profile_trait_table.sql'])
IMM_S='SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal IMMEDIATE;'
DEF_S='SET CONSTRAINTS public.trg_cecp_seal, public.trg_cecem_seal DEFERRED;'
TOKENS5={'EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION','EDITION_CONTEXT_COMPOSITION_IMMUTABLE','EDITION_CONTEXT_TRAIT_INACTIVE',
         'EDITION_CONTEXT_SIGNATURE_MISMATCH','EDITION_CONTEXT_SIGNATURE_IMMUTABLE'}
PAIRS_23505={('uq_cecp_game_signature','card_edition_context_profile'),('pk_cecpt','card_edition_context_profile_trait')}
TABLES3={'public.card_edition_context_trait','public.card_edition_context_profile','public.card_edition_context_profile_trait'}
RESET_REQ=['v_t1','v_t2','v_t3','v_ti','v_p','v_pa','v_pb','v_code_p','v_code_pa','v_code_pb','v_q','v_step']
UPDATE_RE=re.compile(r"^UPDATE public\.card_edition_context_profile SET (traits_signature = (ARRAY\[v_t\w+\]|NULL)|name = [^;]+) WHERE id = v_p\w* AND code = v_code_p\w*$")
DELETE_RE=re.compile(r"^DELETE FROM public\.card_edition_context_profile_trait WHERE profile_id = v_p\w* AND trait_id = v_t\w*$")
FORB3=[r'\bCOMMIT\b',r'\bROLLBACK\b',r'\bSAVEPOINT\b',r'\bRELEASE\b',r'\bCREATE\b',r'\bALTER\b',r'\bDROP\b',r'\bTEMP\b',r'\bTEMPORARY\b',
       r'SET_CONFIG',r'\bSET\s+ROLE\b',r'\bSET\s+LOCAL\b',r'\bSET\s+SESSION\b',r'\bSET\s+TRANSACTION\b',r'\bRESET\b',r'\bGRANT\b',r'\bREVOKE\b',
       r'\bTRUNCATE\b',r'PG_SLEEP',r'DBLINK',r'\bNET\.',r'\bPERFORM\b',r'\bEXECUTE\b',r'RAISE\s+NOTICE',r'RAISE\s+WARNING',r'RAISE\s+INFO',
       r'RAISE\s+LOG',r'RAISE\s+DEBUG',r'\bCOMMENT\b',r'\bSECURITY\s+LABEL\b',r'\bREINDEX\b',r'\bREFRESH\b',r'\bIMPORT\b',r'\bLISTEN\b',
       r'\bNOTIFY\b',r'\bLOAD\b',r'\bCALL\b',r'\bCOPY\b',r'\bLOCK\b',r'\bMERGE\b',r'\bDISCARD\b',r'\bPREPARE\b',r'\bVACUUM\b',
       r'\bANALYZE\b',r'\bCLUSTER\b',r'\bDO\b',r'\bON\s+CONFLICT\b',r'\bFOR\s+UPDATE\b',r'\bFOR\s+SHARE\b']
def norm(s): return ' '.join(s.split())
# gabarito da sonda: extraído da PRÓPRIA readiness v1.1 (§2.6.2) + a atribuição de v_order_q descrita no mesmo parágrafo
_g=re.search(r"#### 2\.6\.2.*?```sql\n(.*?)```",READINESS,re.S)
PROBE_CANON=norm(code(_g.group(1))).replace('v_qok := NULL; BEGIN','v_qok := NULL; v_order_q := v_ord_p + 1090; BEGIN') if _g else ''
PROBE_BLOCK_RE=re.compile(r"v_qn\s*:=\s*v_qn \+ 1;.*?END IF;\s*v_q\s*:=\s*NULL;",re.S)

SPEC_E03=dict(label='E03',tag='h2830_e03',env='E03_SECAO2_COMPOSICAO_PROFILE',
              cases=['2.1','2.2','2.3','2.4','2.5','2.7','2.8','2.9','2.10','2.11','2.12','2.13','2.14'],
              n_imm=11,n_def=13,n_probe=11,n_neg=9,n_update=4,n_delete=1,tokens=TOKENS5,rowcount_case='2.14',step_cases=['2.2','2.7'],
              imm_per_case={'2.1':1,'2.2':1,'2.3':1,'2.4':1,'2.5':0,'2.7':2,'2.8':0,'2.9':1,'2.10':1,'2.11':0,'2.12':1,'2.13':1,'2.14':1},
              lock_timeout=True)
SPEC_E03T=dict(label='E03T',tag='h2830_e03t',env='E03T_N1_CONTROLE',cases=['T1','T2','T3'],
               n_imm=4,n_def=5,n_probe=4,n_neg=1,n_update=0,n_delete=0,tokens={'EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION'},
               rowcount_case=None,step_cases=['T2'],imm_per_case={'T1':1,'T2':1,'T3':2},lock_timeout=False)

def _neg_blocks(cs):
    """Sub-blocos negativos: (begin, exc, end_handler_exclusive). Padrão E01: BEGIN … EXCEPTION WHEN OTHERS THEN v_got := true; … END;"""
    out=[]
    for m in re.finditer(r'EXCEPTION WHEN OTHERS THEN\s+v_got := true;',cs):
        b=max((x.start() for x in re.finditer(r'\bBEGIN\b',cs[:m.start()])),default=-1)
        e=cs.find('END;',m.end())
        out.append((b,m.start(),e+4 if e>=0 else -1))
    return out

# --------------------------------------------------------------------------
# DP-4 = A (BATCH12-2830-P5-L1-E03-DECISION-AND-IMPLEMENTATION-01), SÓ para o
# E03: o preâmbulo P8 é a PRIMEIRA instrução executável do bloco principal,
# exatamente como abaixo (espaços livres; texto e ordem exatos). Somente este
# SET LOCAL é excluído do E03-2/E03-5; qualquer outro SET LOCAL, SET de sessão,
# set_config ou ALTER continua reprovando. O E03T (DP-4 = B) continua sem SET
# LOCAL algum.
# --------------------------------------------------------------------------
LT_PRE_RE=re.compile(r"BEGIN\s*SET LOCAL lock_timeout = '5s';\s*"
                     r"IF current_setting\('lock_timeout'\) IS DISTINCT FROM '5s' THEN\s*"
                     r"RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format\(\s*"
                     r"'H2830_FAIL: envelope=%s caso=PREFLIGHT lock_timeout=%s \(esperado 5s\)', c_env, current_setting\('lock_timeout'\)\);\s*"
                     r"END IF;")
def lt_split(body):
    """(preâmbulo canônico no início exato do bloco principal?, corpo sem ele)."""
    m0=re.search(r'\bBEGIN\b',body)
    if not m0: return False,body
    m=LT_PRE_RE.match(body,m0.start())
    if not m: return False,body
    return True,body[:m0.start()]+'BEGIN'+body[m.end():]

def e03_rules(src,S):
    out=[]
    def ck(rule,name,cond,det=''): out.append((f"{S['label']} {rule}: {name}",bool(cond),det))
    c=code(src); tag=S['tag']
    # E03-1 ------------------------------------------------------------------
    parts=c.split('$'+tag+'$')
    ck('E03-1','um único DO $'+tag+'$ … $'+tag+'$;',len(re.findall(r'\bDO\s+\$',c))==1 and len(parts)==3 and c.rstrip().endswith('$'+tag+'$;'))
    ck('E03-1','nada executável fora do DO',len(parts)==3 and parts[0].strip().upper()=='DO' and parts[2].strip()==';')
    body=parts[1] if len(parts)==3 else ''
    ns=nostr(body); U=ns.upper()
    lt_ok,body_eff=lt_split(body) if S.get('lock_timeout') else (False,body)
    ns_eff=nostr(body_eff); U_eff=ns_eff.upper()
    # E03-20 (DP-4) ----------------------------------------------------------
    if S.get('lock_timeout'):
        ck('E03-20',"primeira instrução executável do bloco principal = SET LOCAL lock_timeout = '5s' seguida da asserção fail-closed exata (IS DISTINCT FROM '5s' ⇒ H283F caso=PREFLIGHT), antes de qualquer leitura ou escrita",lt_ok)
        ck('E03-20',"exatamente 1 SET LOCAL e 1 asserção de lock_timeout no corpo; nenhum outro uso de lock_timeout",
           len(re.findall(r'\bSET\s+LOCAL\b',U))==1 and len(re.findall(r"current_setting\('lock_timeout'\)",body))==2
           and len(re.findall(r'lock_timeout',body,re.I))==4,str(len(re.findall(r'lock_timeout',body,re.I))))
    else:
        ck('E03-20',"sem SET LOCAL e sem lock_timeout (DP-4 = B vale só para este envelope)",
           not re.search(r'\bSET\s+LOCAL\b',U) and not re.search(r'lock_timeout',body,re.I))
    # E03-2 ------------------------------------------------------------------
    hits=[t for t in FORB3 if re.search(t,U_eff)]
    ck('E03-2','tokens proibidos ausentes (COMMIT, EXECUTE, TEMP, SET LOCAL/ROLE/SESSION, set_config, DDL, LOCK, …)',not hits,str(hits))
    # E03-3 / E03-4 --------------------------------------------------------------
    ups=[norm(x)[:-1] for x in re.findall(r'\bUPDATE\b[^;]*;',ns)]
    ck('E03-3',f"UPDATE só em profile de fixture (WHERE id = v_p… AND code = v_code_p…), {S['n_update']} esperados",
       len(ups)==S['n_update'] and all(UPDATE_RE.match(u) for u in ups),str([u for u in ups if not UPDATE_RE.match(u)] or len(ups)))
    dels=[norm(x)[:-1] for x in re.findall(r'\bDELETE\b[^;]*;',ns)]
    ck('E03-4',f"DELETE só na N:N de fixture (profile_id = v_p… AND trait_id = v_t…), {S['n_delete']} esperados",
       len(dels)==S['n_delete'] and all(DELETE_RE.match(d) for d in dels),str([d for d in dels if not DELETE_RE.match(d)] or len(dels)))
    # E03-5 ------------------------------------------------------------------
    ns_noup=re.sub(r'\bUPDATE\b[^;]*;',' ',ns_eff)
    sets=[norm(x) for x in re.findall(r'\bSET\b[^;]*;',ns_noup)]
    ck('E03-5','todo SET é exatamente SET CONSTRAINTS dos 2 selos IMMEDIATE|DEFERRED',all(s in (IMM_S,DEF_S) for s in sets),str([s for s in sets if s not in (IMM_S,DEF_S)]))
    ck('E03-5',f"totais: {S['n_imm']} IMMEDIATE e {S['n_def']} DEFERRED",sets.count(IMM_S)==S['n_imm'] and sets.count(DEF_S)==S['n_def'],f'{sets.count(IMM_S)}/{sets.count(DEF_S)}')
    # segmentação por caso (mesma regra do perfil E01)
    cases=re.findall(r"v_case\s*:=\s*'([^']+)'",body)
    segs=[s.split('v_case :=')[0] for s in re.split(r"v_case\s*:=\s*'[^']+'\s*;",body)[1:]]
    # E03-6 ------------------------------------------------------------------
    ok6=True; det6=[]
    for cid,sg in zip(cases,segs):
        ims=[m.start() for m in re.finditer(re.escape(IMM_S),sg)]; dfs=[m.start() for m in re.finditer(re.escape(DEF_S),sg)]
        negs=_neg_blocks(sg)
        if len(dfs)<len(ims) or ims!=[] and not all(any(d>i for d in dfs) for i in ims): ok6=False; det6.append(cid)
        if len(ims)!=S['imm_per_case'].get(cid,-1): ok6=False; det6.append(cid+':#imm')
        for (b,x,e) in negs:
            nb=sg[b:x]; nh=sg[x:e]
            if IMM_S in nb and not (DEF_S in nb[nb.index(IMM_S):] and DEF_S in nh): ok6=False; det6.append(cid+':neg')
    ck('E03-6','cada IMMEDIATE seguido de DEFERRED no mesmo caso; negativo com DEFERRED no corpo e no handler; IMMEDIATE por caso = matriz §2.6.5',ok6,str(det6))
    # E03-7 ------------------------------------------------------------------
    tg=[norm(t) for t in re.findall(r'\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+([A-Za-z_\.]+)',ns)]
    ck('E03-7','alvos de INSERT/UPDATE/DELETE ⊂ {trait, profile, profile_trait} (qualificados)',tg and set(tg)<=TABLES3,str(sorted(set(tg)-TABLES3)))
    cn=norm(body)
    ins_all=re.findall(r'INSERT INTO [^;]*;',cn)
    ins_tp=re.findall(r"INSERT INTO public\.(card_edition_context_trait|card_edition_context_profile) \(([^)]*)\) VALUES \((.*?)\) RETURNING id INTO (v_\w+);",cn)
    ins_nn=re.findall(r"INSERT INTO public\.card_edition_context_profile_trait \(profile_id, trait_id, game_id\) VALUES \((v_p\w*), (v_t\w+|v_arr\[\d\]), v_game\);",cn)
    def _split(v):
        o=[];d=0;cur=''
        for ch in v:
            if ch=='(' : d+=1
            if ch==')' : d-=1
            if ch==',' and d==0: o.append(cur.strip()); cur=''
            else: cur+=ch
        o.append(cur.strip()); return o
    okm=True; detm=[]
    for tbl,cols,vals,var in ins_tp:
        mp=dict(zip([x.strip() for x in cols.split(',')],_split(vals)))
        cv=mp.get('code',''); nv=mp.get('name','')
        if not ('v_marker' in nv and ('v_marker' in cv or re.fullmatch(r'v_code_p\w*',cv))) or mp.get('game_id')!='v_game': okm=False; detm.append(var)
    assigns=re.findall(r'\b(v_code_p\w*)\s*:=\s*([^;]*);',cn)
    ok_assign=all(r=='NULL' or r.startswith("v_marker || '") for _,r in assigns)
    ck('E03-7','todo INSERT é trait/profile com v_marker em code e name (code = v_marker… ou v_code_p… := v_marker…) ou N:N de fixture (v_p…, v_t…|v_arr[n], v_game)',
       len(ins_all)==len(ins_tp)+len(ins_nn) and okm and ok_assign,f'ins={len(ins_all)} tp={len(ins_tp)} nn={len(ins_nn)} {detm}')
    idas=re.findall(r'\b(v_(?:t\d|ti|p|pa|pb|q))\s*:=\s*([^;]*);',cn)
    intos=re.findall(r'(\S+ \S+) INTO (v_(?:t\d|ti|p|pa|pb|q))\b',cn)
    ck('E03-7','ids de fixture só por RETURNING id INTO (atribuição direta só := NULL): UPDATE/DELETE nunca alcançam linha pré-existente',
       all(r=='NULL' for _,r in idas) and all(pre=='RETURNING id' for pre,_ in intos),str([x for x in idas if x[1]!='NULL']+[x for x in intos if x[0]!='RETURNING id']))
    # E03-8 ------------------------------------------------------------------
    negs=_neg_blocks(body); ok8=True; det8=[]; used=set()
    p0001=re.compile(r"v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with\(v_msg, '([A-Z_]+):'\)")
    p23505=re.compile(r"v_state IS NULL OR v_state <> '23505' OR v_con IS DISTINCT FROM '([a-z_]+)' OR v_tab IS DISTINCT FROM '([a-z_]+)'")
    for (b,x,e) in negs:
        if b<0 or e<0 or re.search(r'\bBEGIN\b',body[b+5:x]): ok8=False; det8.append('estrutura'); continue
        nxt=[p for p in [body.find('v_got := false',e),body.find('BEGIN',e),body.find("v_case :=",e)] if p>=0]
        seg=body[e:min(nxt) if nxt else len(body)]
        m1=p0001.search(seg); m2=p23505.search(seg)
        good=('IF NOT v_got THEN' in seg) and ((m1 and m1.group(1) in TOKENS5) or (m2 and (m2.group(1),m2.group(2)) in PAIRS_23505))
        if m1: used.add(m1.group(1))
        if not good: ok8=False; det8.append(seg[:60])
    ck('E03-8',f"{S['n_neg']} negativos, cada um com IF NOT v_got e checagem estrita (P0001 + starts_with do token completo; ou 23505 + constraint + tabela)",
       ok8 and len(negs)==S['n_neg'],f'{len(negs)} {det8[:2]}')
    # E03-9 ------------------------------------------------------------------
    ck('E03-9','tokens usados = conjunto esperado ⊂ os 5 do §1.2, e cada um existe literalmente (com ":") na 2206',
       used==S['tokens'] and all((t+':') in S2206 for t in used),str(sorted(used)))
    # E03-10 -----------------------------------------------------------------
    ck('E03-10','sem LIKE/ILIKE/SIMILAR/~ (tokens só por starts_with)',not re.search(r'\b(I?LIKE|SIMILAR)\b',U) and not re.search(r'v_msg\s*!?~',ns))
    # E03-11 -----------------------------------------------------------------
    ce=re.search(r"c_expected\s+CONSTANT\s+text\[\]\s*:=\s*ARRAY\[(.*?)\]",body,re.S)
    cel=re.findall(r"'([^']+)'",ce.group(1)) if ce else []
    ck('E03-11','casos na ordem contratual = c_expected; 2.6 ausente',cases==S['cases'] and cel==S['cases'] and '2.6' not in cases+cel,str(cases))
    ck('E03-11',"c_env = '"+S['env']+"'",re.search(r"c_env\s+CONSTANT\s+text\s*:=\s*'"+S['env']+"';",body) is not None)
    # E03-12 -----------------------------------------------------------------
    codes=re.findall(r"ERRCODE\s*=\s*'([A-Z0-9]{5})'",body)
    ck('E03-12','ERRCODEs só H283C/H283F/H283P/H283S',set(codes)<={'H283C','H283F','H283P','H283S'},str(set(codes)))
    ck('E03-12','H283P exatamente 1 e último sinal do corpo',codes.count('H283P')==1 and codes and codes[-1]=='H283P')
    okc=True
    for cid,sg in zip(cases,segs):
        if not (len(re.findall(r"ERRCODE\s*=\s*'H283C'",sg))==1 and "WHEN SQLSTATE 'H283C'" in sg and "WHEN SQLSTATE 'H283F' THEN RAISE;" in sg
                and 'v_done := v_done || v_case' in sg and re.search(r"RAISE EXCEPTION USING ERRCODE = 'H283C', MESSAGE = v_case;\s*EXCEPTION\s*WHEN SQLSTATE 'H283C' THEN",sg)): okc=False
    ck('E03-12','estrutura de subtransação por caso igual à do E01 (1 H283C final, handlers H283C/H283F/OTHERS)',okc and len(cases)==len(S['cases']))
    pbs=[(m.start(),m.end()) for m in PROBE_BLOCK_RE.finditer(body)]
    inside=lambda pos: any(a<=pos<b for a,b in pbs)
    s_raise=[m.start() for m in re.finditer(r"ERRCODE\s*=\s*'H283S'",body)]
    s_when=[m.start() for m in re.finditer(r"WHEN SQLSTATE 'H283S'",body)]
    c_in=[m.start() for m in re.finditer(r"'H283C'",body) if inside(m.start())]
    ck('E03-12','H283S só dentro de bloco de sonda (raise e handler, 1 de cada por sonda); nenhum H283C dentro de sonda',
       len(s_raise)==len(s_when)==len(pbs)==S['n_probe'] and all(inside(p) for p in s_raise+s_when) and not c_in,f'{len(s_raise)}/{len(s_when)}/{len(pbs)}')
    ck('E03-12',f"gate do envelope: v_done = c_expected e v_qn = {S['n_probe']} antes do terminal",
       'IF v_done IS DISTINCT FROM c_expected THEN' in body and f"IF v_qn <> {S['n_probe']} THEN" in body and body.rfind(f"IF v_qn <> {S['n_probe']} THEN")<body.rfind("'H283P'"))
    ck('E03-12','terminal H2830_ROLLBACK_PASS com pass, casos, marker e elapsed_ms (sem caminho de COMMIT)',
       "'H2830_ROLLBACK_PASS: envelope=%s pass=%s/%s casos=%s marker=%s elapsed_ms=%s'" in body and re.search(r"elapsed_ms.*?\)\);\s*END\s*$",body,re.S) is not None)
    # E03-13 -----------------------------------------------------------------
    ok13=all(all(re.search(r'\b'+v+r' := NULL;',sg[:sg.find('BEGIN')]) for v in RESET_REQ) for sg in segs)
    ck('E03-13','reset das variáveis de fixture, v_q e v_step a NULL antes do BEGIN de cada caso',ok13 and segs)
    # E03-14 -----------------------------------------------------------------
    if S['rowcount_case']:
        sg=dict(zip(cases,segs)).get(S['rowcount_case'],'')
        ck('E03-14',S['rowcount_case']+': GET DIAGNOSTICS v_n = ROW_COUNT seguido de IF v_n <> 1',re.search(r'GET DIAGNOSTICS v_n = ROW_COUNT;\s*IF v_n <> 1 THEN',sg) is not None)
    # E03-15 -----------------------------------------------------------------
    ok15=True; det15=[]
    for cid,sg in zip(cases,segs):
        pb=[(m.start(),m.end()) for m in PROBE_BLOCK_RE.finditer(sg)]
        negs=_neg_blocks(sg)
        ims=[m.start() for m in re.finditer(re.escape(IMM_S),sg)]
        if len(pb)!=len(ims) or len(pb)!=S['imm_per_case'].get(cid,-1): ok15=False; det15.append(cid+':#'); continue
        ev=sorted([(i,'I') for i in ims]+[(a,'P') for a,_ in pb])
        if [k for _,k in ev]!=['I','P']*len(pb): ok15=False; det15.append(cid+':ordem')
        for a,_ in pb:
            if any(b<=a<e for b,_,e in negs): ok15=False; det15.append(cid+':dentro-neg')
            anchors=[m.end() for m in re.finditer(re.escape(DEF_S),sg[:a]) if not any(b<=m.start()<e for b,_,e in negs)]
            anchors+=[e for b,x,e in negs if e<=a and IMM_S in sg[b:x]]
            if not anchors: ok15=False; det15.append(cid+':sem-âncora'); continue
            gap=nostr(sg[max(anchors):a])
            if re.search(r'\b(INSERT|UPDATE|DELETE|SET)\b',gap): ok15=False; det15.append(cid+':escrita-antes-da-sonda')
            lastimm=max([i for i in ims if i<a],default=-1)
            if max(anchors)<lastimm: ok15=False; det15.append(cid+':DEFERRED-antes-do-IMMEDIATE')
    ck('E03-15',f"#sondas = #IMMEDIATE por caso ({S['n_probe']} no total), alternância IMMEDIATE→sonda, nível de caso, fora de negativo/handler, sem escrita nem SET entre DEFERRED/END do negativo e a sonda",
       ok15 and len(pbs)==S['n_probe'],str(det15))
    # E03-16 -----------------------------------------------------------------
    Uc=nostr(c).upper()
    nb=len(re.findall(r'\bBEGIN\b',Uc)); ne=len(re.findall(r'\bEND\b(?!\s+(IF|LOOP))',Uc))
    n_if=len(re.findall(r'(?<!END )\bIF\b',Uc)); n_eif=len(re.findall(r'\bEND\s+IF\b',Uc))
    ck('E03-16','BEGIN/END, IF/END IF, parênteses e aspas balanceados',nb==ne and n_if==n_eif and nostr(c).count('(')==nostr(c).count(')') and c.count("'")%2==0,f'{nb}/{ne} {n_if}/{n_eif}')
    # E03-17 -----------------------------------------------------------------
    blocks=[norm(body[a:b]) for a,b in pbs]
    ck('E03-17','gabarito da sonda extraído da readiness v1.1 §2.6.2',bool(PROBE_CANON) and 'H283S' in PROBE_CANON)
    ck('E03-17',f"cada bloco de sonda é IDÊNTICO ao gabarito (INSERT/SELECT/IF/RAISE H283S; handlers H283S exato → H283F RAISE → OTHERS→H283F; pós-checagem), {S['n_probe']} blocos",
       len(blocks)==S['n_probe'] and all(b==PROBE_CANON for b in blocks) and len(re.findall(r'v_qn\s*:=\s*v_qn \+ 1;',body))==S['n_probe'],
       str([i for i,b in enumerate(blocks) if b!=PROBE_CANON]))
    # E03-18 -----------------------------------------------------------------
    rest=PROBE_BLOCK_RE.sub(' ',body)
    vq=[m for m in re.finditer(r'\bv_q\b',rest)]
    ck('E03-18','fora dos blocos de sonda, v_q só aparece na declaração e no reset do início do caso',
       all(re.match(r'v_q\s*:=\s*NULL;|v_q\s+uuid;',rest[m.start():]) for m in vq) and len(vq)==len(S['cases'])+1,str(len(vq)))
    # E03-19 -----------------------------------------------------------------
    ok19=True
    for cid in S['step_cases']:
        sg=dict(zip(cases,segs)).get(cid,'')
        nn=[(b,x,e) for (b,x,e) in _neg_blocks(sg) if IMM_S in sg[b:x]]
        if len(nn)!=1: ok19=False; continue
        b,x,e=nn[0]; nbody=sg[b+5:x]
        stmts=re.findall(r'(v_step := \'[A-Z0-9_]+\';\s*)?(INSERT INTO|SET CONSTRAINTS)',nbody)
        acc=re.search(r"IF v_state IS NULL[^\n]*THEN",sg[e:])
        if not (stmts and all(p for p,_ in stmts) and re.search(r"v_step := 'IMMEDIATE';\s*"+re.escape(IMM_S),nbody)
                and acc and acc.group(0).endswith("OR v_step IS DISTINCT FROM 'IMMEDIATE' THEN")): ok19=False
    ck('E03-19',f"negativos com IMMEDIATE ({', '.join(S['step_cases'])}): v_step antes de cada statement, 'IMMEDIATE' imediatamente antes do SET e exigido no aceite",ok19)
    return out

# --------------------------------------------------------------------------
# PERFIL E03P (SELECT único) — mesmo perfil E00/E99 + gates e pinos
# --------------------------------------------------------------------------
G03P=['g_game_pokemon_one','g_s2_triggers','g_no_other_triggers_l1','g_seal_constraint_names_unique','g_deferrable_only_seal',
      'g_s2_constraints','g_s2_error_tokens','g_s2_function_pins','g_nn_no_sequence','g_nn_rls_bypass','g_marker_absent_now']
G03P_TERMS={'g_game_pokemon_one':["public.game WHERE code = 'POKEMON'",") = 1"],
 'g_s2_triggers':["t.tgtype = e.tgtype","t.enabled = 'O'","t.fn_oid = to_regprocedure(e.fn)","t.deferrable = e.is_constraint","t.initdeferred = e.is_constraint","t.attrs = e.attrs",") = 4"],
 'g_no_other_triggers_l1':["NOT EXISTS (SELECT 1 FROM trg t","e.tgname = t.tgname AND e.relname = t.relname"],
 'g_seal_constraint_names_unique':["conname = 'trg_cecp_seal') = 1","conname = 'trg_cecem_seal') = 1","contype <> 't' OR NOT condeferrable OR NOT condeferred"],
 'g_deferrable_only_seal':["WHERE condeferrable","NOT (conname = 'trg_cecp_seal' AND relname = 'card_edition_context_profile')",") = 1"],
 'g_s2_constraints':["c.contype = e.contype AND c.convalidated) = 11","indisunique AND indisvalid AND indisready","pred = '(traits_signature IS NOT NULL)'","cols = ARRAY['game_id','traits_signature']"],
 'g_s2_error_tokens':["FROM fn_tok WHERE present) = 5"],'g_s2_function_pins':["body_md5_lf = pin) = 4","fn_oid IS NOT NULL"],
 'g_nn_no_sequence':["NOT EXISTS (SELECT 1 FROM nn_seq)"],'g_nn_rls_bypass':["NOT force_rls AND owner = current_user) = 1"],
 'g_marker_absent_now':["marker_trait = 0 AND marker_profile = 0"]}
def e03p_rules(src):
    out=[]
    def ck(rule,name,cond,det=''): out.append((f"E03P {rule}: {name}",bool(cond),det))
    c=code(src); Un=nostr(c).upper()
    ck('P-1','1 statement',Un.count(';')==1 and Un.rstrip().endswith(';'))
    FORBP=[r'\bINSERT\b',r'\bUPDATE\b',r'\bDELETE\b',r'\bCREATE\b',r'\bALTER\b',r'\bDROP\b',r'SET_CONFIG',r'\bSET\b',r'\bDO\b',r'\bTEMP\b',
           r'\bINTO\b',r'\bGRANT\b',r'\bREVOKE\b',r'\bCOMMENT\b',r'\bSECURITY\s+LABEL\b',r'\bREINDEX\b',r'\bREFRESH\b',r'\bIMPORT\b',
           r'\bTRUNCATE\b',r'\bMERGE\b',r'\bCOPY\b',r'\bCALL\b',r'\bLOCK\b',r'\bLISTEN\b',r'\bNOTIFY\b',r'\bEXECUTE\b',r'PG_SLEEP',r'DBLINK']
    hits=[t for t in FORBP if re.search(t,Un)]
    ck('P-1','perfil E00/E99: sem DML, DDL, SET, DO, TEMP, INTO, …',not hits,str(hits))
    ck('P-1','parênteses balanceados',nostr(c).count('(')==nostr(c).count(')'))
    gi=c.find('\ngates AS ('); ge=c.find('\nSELECT to_jsonb(g)')
    gc=c[gi:ge] if gi>=0 and ge>gi else ''
    gd=re.findall(r'AS\s+(g_[A-Za-z0-9_]+)',gc)
    ck('P-2','CTE gates define EXATAMENTE os 11 gates da readiness §5 (sem extra, falta ou duplicata)',sorted(gd)==sorted(G03P) and len(gd)==len(set(gd))==11,str(sorted(set(gd)^set(G03P))))
    pt=re.split(r'AS\s+(g_[A-Za-z0-9_]+)',gc); seg={pt[i]:pt[i-1] for i in range(1,len(pt),2)}
    for g,terms in G03P_TERMS.items():
        t=seg.get(g,'')
        ck('P-3',f'predicado de {g} com {len(terms)} termo(s) efetivo(s), não esvaziado',all(x in t for x in terms) and not re.search(r'WHERE\s+false|OR\s+true|>=\s*[0-9]|^\s*,?\s*true\s*$',t,re.I|re.M),g)
    ck('P-4','gate_pass = bool_and de TODOS os g_* e NULL = falha',"'gate_pass', (SELECT bool_and(v::boolean) FROM jsonb_each_text(to_jsonb(g))" in c and 'WHERE v IS NULL' in c)
    fe=re.findall(r"\('([a-z_]+)',\s*'([0-9a-f]{32})',\s*ARRAY\[([^\]]*)\]\)",c)
    pins={n:p for n,p,_ in fe}; toks={n:set(re.findall(r"'([A-Z_]+):'",t)) for n,_,t in fe}
    ck('P-5','4 pinos = md5(LF(corpo da 2206)) = pinos do E00 (p7_allowlist)',len(pins)==4 and all(
        ('internal.'+n) in real and hashlib.md5(lf(real['internal.'+n][7]).encode()).hexdigest()==p and ALLOW.get(('internal',n,''),{}).get('md5')==p for n,p in pins.items()),str(pins))
    exp_tok={'seal_edition_context_composition':{'EDITION_CONTEXT_PROFILE_EMPTY_COMPOSITION'},
             'guard_edition_context_composition_immutable':{'EDITION_CONTEXT_COMPOSITION_IMMUTABLE'},
             'enforce_edition_context_signature_write':{'EDITION_CONTEXT_SIGNATURE_MISMATCH','EDITION_CONTEXT_SIGNATURE_IMMUTABLE'},
             'guard_edition_context_trait_active':{'EDITION_CONTEXT_TRAIT_INACTIVE'}}
    ck('P-6','tokens por função = §1.2 (5 no total) e cada um presente no corpo da própria função na 2206',toks==exp_tok and all(
        all((t+':') in real['internal.'+n][7] for t in ts) for n,ts in toks.items()),str(toks))
    te=re.findall(r"\('(trg_[a-z_]+)',\s*'([a-z_]+)',\s*(\d+),\s*'([a-z_\.]+\(\))',\s*(true|false),\s*ARRAY\[([^\]]*)\]",c)
    def tgt(ddl):
        m=re.search(r'(BEFORE|AFTER) (.*?) ON public\.([a-z_]+)\s',ddl,re.S)
        ev=m.group(2); t=1+(2 if m.group(1)=='BEFORE' else 0)+(4 if 'INSERT' in ev else 0)+(8 if 'DELETE' in ev else 0)+(16 if 'UPDATE' in ev else 0)
        cols=re.findall(r'UPDATE OF ([a-z_, ]+)',ev); return t,m.group(3),[x.strip() for x in cols[0].split(',')] if cols else []
    d06={}
    for m in re.finditer(r'CREATE (CONSTRAINT )?TRIGGER (trg_[a-z_]+)\n(.*?)EXECUTE FUNCTION ([a-z_\.]+)\(\);',S2206,re.S):
        t,rel,cols=tgt(m.group(3)); d06[m.group(2)]=(rel,t,m.group(4)+'()',bool(m.group(1)),cols,'DEFERRABLE INITIALLY DEFERRED' in m.group(3))
    okt=len(te)==4 and all(n in d06 and d06[n][0]==r and d06[n][1]==int(t) and d06[n][2]==f and d06[n][3]==(ic=='true') and d06[n][5]==(ic=='true')
                           and d06[n][4]==re.findall(r"'([a-z_]+)'",a) for n,r,t,f,ic,a in te) and set(d06)=={n for n,*_ in te}
    ck('P-7','trg_exp = os 4 CREATE TRIGGER da 2206 (tabela, tgtype calculado, função, constraint/deferrable, UPDATE OF)',okt,str(te))
    ce=re.findall(r"\('((?:pk|fk|uq|ck)_[a-z_]+)',\s*'([a-z_]+)',\s*'([pfuc])'\)",c)
    kind={'p':'PRIMARY KEY','f':'FOREIGN KEY','u':'UNIQUE','c':'CHECK'}
    okc=len(ce)==11 and all(re.search(r'CONSTRAINT '+n+r'\b\s+'+kind[k],DDL) for n,_,k in ce)
    ck('P-8','con_exp = 11 constraints declaradas nas 2203–2205 com o tipo correto',okc,str(len(ce)))
    return out

# --------------------------------------------------------------------------
# Execução sobre os arquivos reais
# --------------------------------------------------------------------------
res3=[]
E03F=(H/'2830H_E03_section2_profile_composition.sql').read_text(encoding='utf-8')
E03TF=(H/'2830H_E03T_n1_controlled_probe.sql').read_text(encoding='utf-8')
E03PF=(H/'2830H_E03P_precheck_section2.sql').read_text(encoding='utf-8')
res3+=e03_rules(E03F,SPEC_E03)
res3+=e03_rules(E03TF,SPEC_E03T)
res3+=e03p_rules(E03PF)
for f in ['2830H_E03_section2_profile_composition.sql','2830H_E03T_n1_controlled_probe.sql','2830H_E03P_precheck_section2.sql']:
    raw=(H/f).read_bytes()
    res3.append((f'ARQUIVO {f}: LF, sem CR, sem tab, sem espaço no fim de linha, termina em LF',
                 b'\r' not in raw and b'\t' not in raw and not re.search(rb' +\n',raw) and raw.endswith(b'\n'),''))
res3.append(('E03 × 2830: 13 casos = linhas "-- 2.x" da 2830 v7.0 l. 453–477 exceto 2.6',
             sorted(SPEC_E03['cases'],key=lambda x:int(x.split('.')[1]))==[x for x in re.findall(r'^--\s+(2\.\d+)\b',
             '\n'.join((REPO/'proposals/2026-09-18-edition-context-axis/2830_validate_edition_context_foundation.sql').read_text(encoding='utf-8').splitlines()[452:477]),re.M) if x!='2.6'],''))
res3.append(('E03 × readiness v1.1: casos = §3.2 e §4 (13, 2.6 fora)',
             re.findall(r'^\| \*\*(2\.\d+)\*\* \|',READINESS.split('### 3.2')[1].split('### 3.3')[0],re.M)==SPEC_E03['cases']
             and re.findall(r'^\| (2\.\d+) \|',READINESS.split('## 4.')[1].split('## 5.')[0],re.M)==SPEC_E03['cases'],''))

_m265=READINESS.split('#### 2.6.5')[1].split('#### 2.6.6')[0] if '#### 2.6.5' in READINESS else ''
_imm265={}
for _row in re.findall(r'^\| ([0-9., ]+?)(?: \(FX\))? \| (\d+|nenhum)\b',_m265,re.M):
    for _c in [x.strip() for x in _row[0].split(',')]:
        _imm265[_c]=0 if _row[1]=='nenhum' else int(_row[1])
res3.append(('E03 × readiness v1.1 §2.6.5: IMMEDIATE por caso = matriz de eventos (e portanto sondas por caso)',
             _imm265==SPEC_E03['imm_per_case'], str(_imm265)))

# --------------------------------------------------------------------------
# Testes negativos do VERIFICADOR: cada mutação insegura TEM de reprovar a
# regra indicada (e o arquivo real continua passando — controle positivo)
# --------------------------------------------------------------------------
negv=[]; posv=[]
def must_fail(label, mutated, rule, rules=e03_rules, spec=SPEC_E03):
    r=rules(mutated,spec) if spec is not None else rules(mutated)
    failed=[n for n,ok,_ in r if not ok]
    negv.append((f'VERIFICADOR rejeita: {label} [{rule}]', any(rule+':' in n for n in failed) and mutated!=(E03F if spec is SPEC_E03 else E03PF), str(failed[:3])))
def sub1(t,a,b,count=1):
    assert a in t, a
    return t.replace(a,b,count)
_seg27=E03F[E03F.index("v_case := '2.7'"):]
must_fail('COMMIT no corpo', sub1(E03F,'    SELECT id INTO v_game','    COMMIT;\n    SELECT id INTO v_game'), 'E03-2')
must_fail('SQL dinâmico (EXECUTE)', sub1(E03F,'    SELECT id INTO v_game',"    EXECUTE 'SELECT 1';\n    SELECT id INTO v_game"), 'E03-2')
must_fail('SET LOCAL lock_timeout adicional, fora da posição canônica', sub1(E03F,'    SELECT id INTO v_game',"    SET LOCAL lock_timeout = '5s';\n    SELECT id INTO v_game"), 'E03-2')
must_fail('set_config', sub1(E03F,'    SELECT id INTO v_game',"    SELECT set_config('x','y',true) INTO v_msg;\n    SELECT id INTO v_game"), 'E03-2')
must_fail('CREATE TEMP TABLE', sub1(E03F,'    SELECT id INTO v_game','    CREATE TEMP TABLE x (a int);\n    SELECT id INTO v_game'), 'E03-2')
must_fail('SET ROLE', sub1(E03F,'    SELECT id INTO v_game','    SET ROLE authenticated;\n    SELECT id INTO v_game'), 'E03-2')
must_fail('UPDATE sem filtro de id (linha pré-existente)', sub1(E03F,'SET traits_signature = NULL WHERE id = v_p AND code = v_code_p;','SET traits_signature = NULL WHERE code = v_code_p;'), 'E03-3')
must_fail('UPDATE em tabela fora da allowlist', sub1(E03F,'UPDATE public.card_edition_context_profile SET name','UPDATE public.card_variant SET name'), 'E03-3')
must_fail('UPDATE de coluna não prevista (is_active)', sub1(E03F,"SET traits_signature = NULL WHERE","SET is_active = false WHERE"), 'E03-3')
must_fail('DELETE sem trait_id', sub1(E03F,'WHERE profile_id = v_p AND trait_id = v_t1;','WHERE profile_id = v_p;'), 'E03-4')
must_fail('DELETE em profile', sub1(E03F,'DELETE FROM public.card_edition_context_profile_trait WHERE profile_id = v_p AND trait_id = v_t1;','DELETE FROM public.card_edition_context_profile WHERE id = v_p;'), 'E03-4')
must_fail('SET CONSTRAINTS ALL', sub1(E03F,IMM_S,'SET CONSTRAINTS ALL IMMEDIATE;'), 'E03-5')
must_fail('SET CONSTRAINTS de um só trigger', sub1(E03F,DEF_S,'SET CONSTRAINTS public.trg_cecp_seal DEFERRED;'), 'E03-5')
must_fail('DEFERRED removido depois de IMMEDIATE (caminho normal)', sub1(E03F,"        -- P4 (3): DEFERRED\n        "+DEF_S,"        -- P4 (3): DEFERRED"), 'E03-6')
must_fail('DEFERRED removido do handler do negativo', E03F.replace("                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;\n            "+DEF_S,"                                    v_tab = TABLE_NAME, v_msg = MESSAGE_TEXT;",1), 'E03-6')
must_fail('INSERT de trait sem marcador no name', sub1(E03F,"'H2830 fixture 2.1 T1 ' || v_marker","'H2830 fixture 2.1 T1'"), 'E03-7')
must_fail('code de profile sem marcador', sub1(E03F,"v_code_p := v_marker || '_P';","v_code_p := 'FIXED_P';"), 'E03-7')
must_fail('INSERT em tabela fora do escopo', sub1(E03F,'    SELECT id INTO v_game',"    INSERT INTO public.card_variant (id) VALUES (NULL);\n    SELECT id INTO v_game"), 'E03-7')
must_fail('id de fixture atribuído de linha real (SELECT … INTO v_p)', sub1(E03F,'    SELECT id INTO v_game','    SELECT id INTO v_game FROM public.game LIMIT 1;\n    SELECT id INTO v_p FROM public.card_edition_context_profile LIMIT 1;\n    SELECT id INTO v_game'), 'E03-7')
must_fail('negativo aceitando qualquer SQLSTATE (sem v_state)', sub1(E03F,"v_state IS NULL OR v_msg IS NULL OR v_state <> 'P0001' OR NOT starts_with(v_msg, 'EDITION_CONTEXT_TRAIT_INACTIVE:')","NOT starts_with(v_msg, 'EDITION_CONTEXT_TRAIT_INACTIVE:')"), 'E03-8')
must_fail('negativo com token abreviado (novo código)', sub1(E03F,"'EDITION_CONTEXT_TRAIT_INACTIVE:'","'TRAIT_INACTIVE:'"), 'E03-8')
must_fail('23505 sem conferir a tabela', sub1(E03F," OR v_tab IS DISTINCT FROM 'card_edition_context_profile_trait'",""), 'E03-8')
must_fail('23505 com constraint trocada', sub1(E03F,"v_con IS DISTINCT FROM 'pk_cecpt'","v_con IS DISTINCT FROM 'uq_cecp_game_code'"), 'E03-8')
must_fail('negativo sem IF NOT v_got', E03F.replace("        IF NOT v_got THEN","        IF false THEN",1), 'E03-8')
must_fail('token inexistente na 2206', sub1(E03F,"'EDITION_CONTEXT_SIGNATURE_MISMATCH:'","'EDITION_CONTEXT_SIGNATURE_MISMATCHX:'"), 'E03-9')
must_fail('LIKE sobre v_msg', sub1(E03F,"NOT starts_with(v_msg, 'EDITION_CONTEXT_TRAIT_INACTIVE:')","v_msg NOT LIKE 'EDITION_CONTEXT_TRAIT_INACTIVE:%'"), 'E03-10')
must_fail('caso 2.6 incluído', sub1(E03F,"v_case := '2.7';","v_case := '2.6';"), 'E03-11')
must_fail('ordem de casos trocada em c_expected', sub1(E03F,"ARRAY['2.1','2.2'","ARRAY['2.2','2.1'"), 'E03-11')
must_fail('sinal novo (H283X)', sub1(E03F,"ERRCODE = 'H283S'","ERRCODE = 'H283X'"), 'E03-12')
must_fail('H283S fora da sonda', sub1(E03F,'    SELECT id INTO v_game',"    RAISE EXCEPTION USING ERRCODE = 'H283S', MESSAGE = 'x';\n    SELECT id INTO v_game"), 'E03-12')
must_fail('H283P duplicado', sub1(E03F,'    SELECT id INTO v_game',"    RAISE EXCEPTION USING ERRCODE = 'H283P', MESSAGE = 'x';\n    SELECT id INTO v_game"), 'E03-12')
must_fail('gate de contagem de sondas removido', sub1(E03F,'IF v_qn <> 11 THEN','IF false THEN'), 'E03-12')
_i27=E03F.index("v_case := '2.7'"); _j=E03F.index('    v_step := NULL;\n',_i27)
must_fail('reset de v_step removido de um caso (2.7)', E03F[:_j]+E03F[_j+len('    v_step := NULL;\n'):], 'E03-13')
must_fail('ROW_COUNT não conferido em 2.14', sub1(E03F,'GET DIAGNOSTICS v_n = ROW_COUNT;','v_n := 1;'), 'E03-14')
_p1=E03F.index('-- SONDA DE MODO'); _p2=E03F.index('v_q := NULL;\n',E03F.index('não descartada',_p1))+len('v_q := NULL;\n')
must_fail('sonda removida de um caso (2.1)', E03F[:_p1]+E03F[_p2:], 'E03-15')
_n27=_seg27.index('-- etapa 11')
must_fail('escrita entre DEFERRED e a sonda', sub1(E03F,"        -- P4 (3): DEFERRED\n        "+DEF_S,"        -- P4 (3): DEFERRED\n        "+DEF_S+"\n        UPDATE public.card_edition_context_profile SET name = 'x' || v_marker WHERE id = v_p AND code = v_code_p;"), 'E03-15')
_i22=E03F.index("v_case := '2.2'"); _a=E03F.index('        -- SONDA DE MODO',_i22)
_b=E03F.index('        v_q := NULL;\n',E03F.index('não descartada',_a))+len('        v_q := NULL;\n')
_blk=E03F[_a:_b]
must_fail('sonda removida do caso 2.2 (IMMEDIATE sem sonda)', E03F[:_a]+E03F[_b:], 'E03-15')
_h=E03F.index('EXCEPTION WHEN OTHERS THEN',_i22); _hd=E03F.index('DEFERRED;\n',_h)+len('DEFERRED;\n')
_in=E03F[:_hd]+'\n'.join(('    '+l) if l else l for l in _blk.split('\n'))+E03F[_hd:_a]+E03F[_b:]
must_fail('sonda movida para DENTRO do handler do negativo 2.2 (máscara pelo WHEN OTHERS)', _in, 'E03-15')
must_fail('handler da sentinela sem comparação exata', E03F.replace("IF v_msg IS DISTINCT FROM v_qtag THEN","IF false THEN",1), 'E03-17')
must_fail('WHEN OTHERS antes do handler H283S (máscara)', E03F.replace("        EXCEPTION\n            WHEN SQLSTATE 'H283S' THEN","        EXCEPTION\n            WHEN OTHERS THEN NULL;\n            WHEN SQLSTATE 'H283S' THEN",1), 'E03-17')
must_fail('sonda sem repassar H283F', E03F.replace("            WHEN SQLSTATE 'H283F' THEN RAISE;\n            WHEN OTHERS THEN\n                GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;\n                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(\n                    'H2830_FAIL: envelope=%s caso=%s sonda","            WHEN OTHERS THEN\n                GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;\n                RAISE EXCEPTION USING ERRCODE = 'H283F', MESSAGE = format(\n                    'H2830_FAIL: envelope=%s caso=%s sonda",1), 'E03-17')
must_fail('sonda que não termina em H283S (commit implícito da fixture)', E03F.replace("            RAISE EXCEPTION USING ERRCODE = 'H283S', MESSAGE = v_qtag;\n","",1), 'E03-17')
must_fail('pós-checagem de ausência da sonda removida', E03F.replace("        SELECT count(*) INTO v_n FROM public.card_edition_context_profile WHERE id = v_q;\n","",1), 'E03-17')
must_fail('v_q reutilizado fora da sonda', sub1(E03F,'    SELECT id INTO v_game','    SELECT id INTO v_game FROM public.game LIMIT 1;\n    v_p := v_q;\n    SELECT id INTO v_game'), 'E03-18')
must_fail('aceite do 2.7 sem v_step', sub1(E03F,"v_tab IS DISTINCT FROM 'card_edition_context_profile' OR v_step IS DISTINCT FROM 'IMMEDIATE'","v_tab IS DISTINCT FROM 'card_edition_context_profile'"), 'E03-19')
must_fail("v_step 'IMMEDIATE' fora de posição no 2.2", E03F.replace("                v_step := 'IMMEDIATE';\n","",1).replace("            v_step := 'IMMEDIATE';\n","",1), 'E03-19')
must_fail('BEGIN sem END', sub1(E03F,'    SELECT id INTO v_game','    BEGIN\n    SELECT id INTO v_game'), 'E03-16')
# --- DP-4 = A: preâmbulo P8 (E03-20) e rejeição de variantes inseguras ---
LT_SET_L="    SET LOCAL lock_timeout = '5s';\n"
LT_IF_L="    IF current_setting('lock_timeout') IS DISTINCT FROM '5s' THEN\n"
_lt_a=E03F.index(LT_SET_L); _lt_b=E03F.index('    END IF;\n',_lt_a)+len('    END IF;\n')
LT_BLOCK=E03F[_lt_a:_lt_b]
E03_NOLT=E03F[:_lt_a]+E03F[_lt_b:]
_ins21=E03F.index('RETURNING id INTO v_t1;\n',E03F.index("v_case := '2.1'"))+len('RETURNING id INTO v_t1;\n')
must_fail('P8: preâmbulo removido (sem SET LOCAL e sem asserção)', E03_NOLT, 'E03-20')
must_fail('P8: asserção removida (SET LOCAL mantido)', E03F[:_lt_a]+LT_SET_L+E03F[_lt_b:], 'E03-20')
must_fail('P8: asserção neutralizada (IF false)', sub1(E03F,LT_IF_L,"    IF false THEN\n"), 'E03-20')
must_fail("P8: SET LOCAL com outro valor ('10s')", sub1(E03F,LT_SET_L,"    SET LOCAL lock_timeout = '10s';\n"), 'E03-20')
must_fail("P8: asserção com outro valor ('0')", sub1(E03F,LT_IF_L,"    IF current_setting('lock_timeout') IS DISTINCT FROM '0' THEN\n"), 'E03-20')
must_fail('P8: asserção com <> no lugar de IS DISTINCT FROM', sub1(E03F,LT_IF_L,"    IF current_setting('lock_timeout') <> '5s' THEN\n"), 'E03-20')
must_fail('P8: asserção sem H283F (H283C)', E03F[:_lt_a]+LT_BLOCK.replace("'H283F'","'H283C'")+E03F[_lt_b:], 'E03-20')
must_fail('P8: SET LOCAL deslocado para depois da primeira escrita (2.1)', E03_NOLT[:E03_NOLT.index('RETURNING id INTO v_t1;\n',E03_NOLT.index("v_case := '2.1'"))+len('RETURNING id INTO v_t1;\n')]+LT_BLOCK+E03_NOLT[E03_NOLT.index('RETURNING id INTO v_t1;\n',E03_NOLT.index("v_case := '2.1'"))+len('RETURNING id INTO v_t1;\n'):], 'E03-20')
must_fail('P8: SET LOCAL deslocado para depois da leitura de preflight', sub1(E03_NOLT,'    SELECT id INTO v_game FROM public.game',LT_BLOCK+'    SELECT id INTO v_game FROM public.game'), 'E03-20')
must_fail('P8: SET LOCAL deslocado para depois da primeira escrita (2.1) — E03-2', E03_NOLT[:E03_NOLT.index('RETURNING id INTO v_t1;\n',E03_NOLT.index("v_case := '2.1'"))+len('RETURNING id INTO v_t1;\n')]+LT_BLOCK+E03_NOLT[E03_NOLT.index('RETURNING id INTO v_t1;\n',E03_NOLT.index("v_case := '2.1'"))+len('RETURNING id INTO v_t1;\n'):], 'E03-2')
must_fail('P8: preâmbulo duplicado', E03F[:_lt_b]+LT_BLOCK+E03F[_lt_b:], 'E03-20')
must_fail('P8: preâmbulo duplicado — E03-2', E03F[:_lt_b]+LT_BLOCK+E03F[_lt_b:], 'E03-2')
must_fail('P8: SET LOCAL statement_timeout adicional', sub1(E03F,'    SELECT id INTO v_game',"    SET LOCAL statement_timeout = '0';\n    SELECT id INTO v_game"), 'E03-2')
must_fail('P8: SET de sessão (sem LOCAL) no lugar do SET LOCAL', sub1(E03F,LT_SET_L,"    SET lock_timeout = '5s';\n"), 'E03-20')
must_fail('P8: SET de sessão (sem LOCAL) — E03-5', sub1(E03F,LT_SET_L,"    SET lock_timeout = '5s';\n"), 'E03-5')
must_fail('P8: SET SESSION lock_timeout', sub1(E03F,LT_SET_L,"    SET SESSION lock_timeout = '5s';\n"), 'E03-2')
must_fail('P8: set_config no lugar do SET LOCAL', sub1(E03F,LT_SET_L,"    SELECT set_config('lock_timeout', '5s', true) INTO v_msg;\n"), 'E03-2')
must_fail('P8: set_config no lugar do SET LOCAL — E03-20', sub1(E03F,LT_SET_L,"    SELECT set_config('lock_timeout', '5s', true) INTO v_msg;\n"), 'E03-20')
must_fail('P8: ALTER ROLE … SET lock_timeout', sub1(E03F,'    SELECT id INTO v_game',"    ALTER ROLE postgres SET lock_timeout = '5s';\n    SELECT id INTO v_game"), 'E03-2')
must_fail('P8: SET LOCAL dentro de um caso (subtransação)', sub1(E03F,"        SELECT COALESCE(max(display_order), 0) INTO v_ord_t","        SET LOCAL lock_timeout = '5s';\n        SELECT COALESCE(max(display_order), 0) INTO v_ord_t"), 'E03-2')
must_fail('P8: SET CONSTRAINTS alterado para ALL junto do preâmbulo', sub1(E03F,LT_SET_L,LT_SET_L+"    SET CONSTRAINTS ALL DEFERRED;\n"), 'E03-5')
must_fail('P8 no E03T: SET LOCAL canônico inserido (DP-4 = B só E03T)', sub1(E03TF,"    SELECT count(*) INTO v_n FROM public.game WHERE code = 'POKEMON';","    SET LOCAL lock_timeout = '5s';\n    SELECT count(*) INTO v_n FROM public.game WHERE code = 'POKEMON';"), 'E03-2', e03_rules, SPEC_E03T)
must_fail('P8 no E03T: SET LOCAL canônico inserido — E03-20', sub1(E03TF,"    SELECT count(*) INTO v_n FROM public.game WHERE code = 'POKEMON';","    SET LOCAL lock_timeout = '5s';\n    SELECT count(*) INTO v_n FROM public.game WHERE code = 'POKEMON';"), 'E03-20', e03_rules, SPEC_E03T)
# E03P
must_fail('E03P: gate flexibilizado (>= 4)', E03PF.replace('AND t.attrs = e.attrs) = 4','AND t.attrs = e.attrs) >= 4',1), 'P-3', e03p_rules, None)
must_fail('E03P: gate esvaziado (OR true)', E03PF.replace('NOT EXISTS (SELECT 1 FROM nn_seq)','NOT EXISTS (SELECT 1 FROM nn_seq) OR true',1), 'P-3', e03p_rules, None)
must_fail('E03P: g_deferrable_only_seal removido', re.sub(r'\n        \(NOT EXISTS \(SELECT 1 FROM con\n.*?AS g_deferrable_only_seal,','',E03PF,flags=re.S), 'P-2', e03p_rules, None)
must_fail('E03P: pino divergente da 2206', E03PF.replace('6077409ac2b5de7f788076e3b4b3f0c0','6077409ac2b5de7f788076e3b4b3f0c1',1), 'P-5', e03p_rules, None)
must_fail('E03P: token trocado', E03PF.replace("'EDITION_CONTEXT_TRAIT_INACTIVE:'","'EDITION_CONTEXT_TRAIT_DISABLED:'",1), 'P-6', e03p_rules, None)
must_fail('E03P: tgtype errado', E03PF.replace("'card_edition_context_profile_trait', 7,","'card_edition_context_profile_trait', 23,",1), 'P-7', e03p_rules, None)
must_fail('E03P: SET no SELECT', E03PF.replace('WITH\ntbl(name)',"SET LOCAL x = 1;\nWITH\ntbl(name)",1), 'P-1', e03p_rules, None)
must_fail('E03P: gate_pass sem tratar NULL', E03PF.replace('WHERE v IS NULL','WHERE false',1), 'P-4', e03p_rules, None)
must_fail('E03P: constraint exigida removida', E03PF.replace("           ('ck_cecp_code_format',         'card_edition_context_profile',       'c')","           ('ck_cecp_code_format_x',       'card_edition_context_profile',       'c')",1), 'P-8', e03p_rules, None)
# controles positivos do verificador
posv.append(('VERIFICADOR positivo: E03 real passa todas as regras', all(ok for _,ok,_ in e03_rules(E03F,SPEC_E03)), ''))
posv.append(('VERIFICADOR positivo: E03T real passa todas as regras', all(ok for _,ok,_ in e03_rules(E03TF,SPEC_E03T)), ''))
posv.append(('VERIFICADOR positivo: E03P real passa todas as regras', all(ok for _,ok,_ in e03p_rules(E03PF)), ''))
posv.append(('VERIFICADOR positivo: whitespace/comentário irrelevante não reprova (E03 reindentado)', all(ok for _,ok,_ in e03_rules(E03F.replace('\n    -- ======','\n\n    -- ======'),SPEC_E03)), ''))
posv.append(('VERIFICADOR positivo: P8 com comentário e linhas em branco a mais no preâmbulo não reprova', all(ok for _,ok,_ in e03_rules(E03F.replace(LT_SET_L,'\n    -- comentário\n'+LT_SET_L+'\n',1),SPEC_E03)), ''))
posv.append(('VERIFICADOR positivo: lt_split reconhece o preâmbulo do E03 real e não reconhece o do E03T', lt_split(code(E03F).split('$h2830_e03$')[1])[0] and not lt_split(code(E03TF).split('$h2830_e03t$')[1])[0], ''))

for title,lst in [('E03-PERFIL',res3),('E03-VERIFICADOR-NEG',negv),('E03-VERIFICADOR-POS',posv)]:
    bad3=[r for r in lst if not r[1]]
    for n,ok,d in lst: print(('PASS ' if ok else 'FAIL ')+'['+title+'] '+n+(' '+d if d and not ok else ''))
    print(f'{title} TOTAL {len(lst)} PASS {len(lst)-len(bad3)} FAIL {len(bad3)}')
