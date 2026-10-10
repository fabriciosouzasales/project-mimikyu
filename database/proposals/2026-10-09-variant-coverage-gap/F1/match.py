# F1 — prova de correspondência (Set + número normalizado) entre as cartas sem variante e o snapshot.
# Uso: python3 match.py  (somente leitura, sem rede)
import json,re,collections
from ours_live_20261009 import O  # números das cartas sem variante, lidos do LIVE em 2026-10-09
import os
S=os.path.join(os.path.dirname(__file__),'../../../seeds/sources/pokemontcg-snapshot-2026-10-09/sets/')
def norm(x): return re.sub(r'(?<![0-9])0+(?=[0-9])','',x.upper())
MAP={k:k.lower().replace('.','') for k in O}; MAP['CEL25CC']='cel25c'
tot=collections.Counter(); rows=[]
for code,nums in O.items():
    d=json.load(open(S+MAP[code]+'.json'))
    idx=collections.defaultdict(list)
    for c in d['cards']: idx[norm(c['number'])].append(c)
    m=amb=orph=nokey=0; keys=collections.Counter(); orl=[]
    for n in nums:
        k=norm(n); hits=idx.get(k,[])
        if len(hits)==1:
            m+=1
            if not hits[0]['tcgplayer_price_keys']: nokey+=1
            keys[tuple(hits[0]['tcgplayer_price_keys'])]+=1
        elif len(hits)>1: amb+=1
        else: orph+=1; orl.append(n)
    rows.append((code,len(nums),m,nokey,amb,orph,orl[:6]))
    tot.update(ours=len(nums),matched=m,nokey=nokey,amb=amb,orph=orph)
    tot.update({'v_'+'+'.join(k):v for k,v in keys.items()})
for r in rows: print(*r)
print(dict(tot))
