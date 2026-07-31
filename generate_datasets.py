"""Generator danych syntetycznych COP-24 — Wspólny Obraz Sytuacji.

Dane są w 100% syntetyczne. Seed=42, UTF-8, daty ISO-8601 +02:00.
"""
from __future__ import annotations

import csv, json, math, random
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

SEED = 42
random.seed(SEED)
try:
    import numpy as np
    RNG = np.random.default_rng(SEED)
except Exception:
    RNG = None

DATA_DIR = Path(__file__).resolve().parent / "datasets"
TZ = timezone(timedelta(hours=2))
D0 = datetime(2026, 9, 15, 12, 0, tzinfo=TZ)
START, END = D0 - timedelta(days=3), D0 + timedelta(days=10)

VOIV = [
("02","dolnośląskie",2892000,"Wrocław",51.1079,17.0385),("04","kujawsko-pomorskie",2062000,"Bydgoszcz/Toruń",53.1235,18.0084),
("06","lubelskie",2100000,"Lublin",51.2465,22.5684),("08","lubuskie",1008000,"Gorzów Wlkp./Zielona Góra",52.7368,15.2288),
("10","łódzkie",2448000,"Łódź",51.7592,19.4560),("12","małopolskie",3410000,"Kraków",50.0647,19.9450),
("14","mazowieckie",5420000,"Warszawa",52.2297,21.0122),("16","opolskie",980000,"Opole",50.6751,17.9213),
("18","podkarpackie",2129000,"Rzeszów",50.0412,21.9991),("20","podlaskie",1181000,"Białystok",53.1325,23.1688),
("22","pomorskie",2346000,"Gdańsk",54.3520,18.6466),("24","śląskie",4517000,"Katowice",50.2649,19.0238),
("26","świętokrzyskie",1233000,"Kielce",50.8661,20.6286),("28","warmińsko-mazurskie",1422000,"Olsztyn",53.7784,20.4801),
("30","wielkopolskie",3498000,"Poznań",52.4064,16.9252),("32","zachodniopomorskie",1701000,"Szczecin",53.4285,14.5528)]
POW_N = {"02":30,"04":23,"06":24,"08":14,"10":24,"12":22,"14":42,"16":12,"18":25,"20":17,"22":20,"24":36,"26":14,"28":21,"30":35,"32":21}
GMI_N = {"02":169,"04":144,"06":213,"08":82,"10":177,"12":182,"14":314,"16":71,"18":160,"20":118,"22":123,"24":167,"26":102,"28":116,"30":226,"32":113}
SPEC_P = {"02":["kłodzki","wrocławski","Wrocław"],"16":["nyski","opolski","Opole"],"24":["raciborski","wodzisławski","Gliwice"],"08":["krośnieński","nowosolski"],"32":["gryfiński","Szczecin"]}
SPEC_G = {"kłodzki":["Kłodzko","Bystrzyca Kłodzka","Lądek-Zdrój","Stronie Śląskie"],"nyski":["Nysa","Głuchołazy","Paczków"],"opolski":["Dobrzeń Wielki","Popielów"],"Wrocław":["Wrocław"],"Opole":["Opole"],"raciborski":["Racibórz","Krzyżanowice"],"wodzisławski":["Wodzisław Śląski"],"krośnieński":["Krosno Odrzańskie"],"gryfiński":["Gryfino"]}
HAZ = [("Z01","Epidemia","Minister Zdrowia","MSWiA; MON; wojewodowie"),("Z02","Powódź","Minister Infrastruktury","MSWiA; Klimat; Aktywa Państwowe; Zdrowie; MON"),("Z03","Zakłócenie funkcjonowania systemów i sieci teleinformatycznych","Minister Cyfryzacji","MSWiA; ABW; operatorzy IK"),("Z04","Działania hybrydowe","Minister Spraw Wewnętrznych i Administracji","MON; MSZ; służby specjalne"),("Z05","Susza/upał","Minister Klimatu i Środowiska","Rolnictwo; Zdrowie; Wody Polskie"),("Z06","Epizootia","Minister Rolnictwa i Rozwoju Wsi","Zdrowie; MSWiA; wojewodowie"),("Z07","Zakłócenie w systemie energetycznym","Minister Klimatu i Środowiska","Aktywa Państwowe; URE; PSE; OSD"),("Z08","Silny wiatr","Minister Spraw Wewnętrznych i Administracji","IMGW-PIB; PSP; wojewodowie"),("Z09","Zakłócenie w systemie paliwowym","Minister Aktywów Państwowych","Klimat; Transport; RARS"),("Z10","Pożar wielkopowierzchniowy","Minister Spraw Wewnętrznych i Administracji","PSP; Lasy Państwowe; MON"),("Z11","Epifitoza","Minister Rolnictwa i Rozwoju Wsi","Klimat; wojewodowie"),("Z12","Zakłócenie funkcjonowania systemów i usług telekomunikacyjnych","Minister Cyfryzacji","UKE; operatorzy; MSWiA"),("Z13","Skażenie chemiczne na lądzie","Minister Spraw Wewnętrznych i Administracji","PSP; Zdrowie; Klimat"),("Z14","Zakłócenie w systemie gazowym","Minister Klimatu i Środowiska","GAZ-SYSTEM; URE; MSWiA"),("Z15","Katastrofa morska","Minister Infrastruktury","MSWiA; SAR; MON"),("Z16","Zdarzenie o charakterze terrorystycznym","Minister Spraw Wewnętrznych i Administracji","ABW; Policja; MON"),("Z17","Skażenie promieniotwórcze","Minister Klimatu i Środowiska","PAA; Zdrowie; MSWiA"),("Z18","Zbiorowe zakłócenie porządku publicznego","Minister Spraw Wewnętrznych i Administracji","Policja; wojewodowie"),("Z19","Silny mróz/intensywne opady śniegu","Minister Spraw Wewnętrznych i Administracji","IMGW-PIB; Energia; Zdrowie"),("Z20","Dezinformacja","Minister Cyfryzacji","RCB; NASK; MSWiA; CIR")]
SPO = [("SPO-1","Organizacja posiedzenia Rządowego Zespołu Zarządzania Kryzysowego"),("SPO-2","Uruchomienie dodatkowych środków finansowych"),("SPO-3","Zasady informowania ludności o zagrożeniach – organizacja procesu komunikacji społecznej w sytuacji kryzysowej"),("SPO-4","Tymczasowe przywrócenie kontroli granicznej na granicach RP"),("SPO-5","Wprowadzenie stanu klęski żywiołowej"),("SPO-6","Wprowadzenie stanu wyjątkowego"),("SPO-7","Wprowadzenie stanu wojennego"),("SPO-8","Postępowanie w sytuacji uprowadzenia terrorystycznego obywatela polskiego poza obszarem RP"),("SPO-9","Działania w przypadku masowego napływu cudzoziemców na terytorium RP"),("SPO-10","Współpraca między administracją publiczną a właścicielami infrastruktury krytycznej"),("SPO-11","Organizacja ewakuacji obywateli polskich spoza granic kraju"),("SPO-12","Obieg informacji pomiędzy krajowymi organami i strukturami zarządzania kryzysowego"),("SPO-13","Ostrzeganie i alarmowanie wojsk oraz ludności cywilnej"),("SPO-14","Przekraczanie granic RP przez wojska sojusznicze"),("SPO-15","Organizacja medycznego mostu powietrznego"),("SPO-16","Zwołanie i obsługa posiedzenia Zespołu do spraw Incydentów Krytycznych")]

def iso(dt): return dt.isoformat(timespec="seconds")
def jit(lat, lon, s=.35): return round(lat+random.uniform(-s,s),5), round(lon+random.uniform(-s,s),5)
def csvw(name, rows):
    with (DATA_DIR/name).open("w",encoding="utf-8",newline="") as f:
        w=csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
    return len(rows)
def jsonlw(name, rows):
    c=0
    with (DATA_DIR/name).open("w",encoding="utf-8") as f:
        for r in rows: f.write(json.dumps(r,ensure_ascii=False,separators=(",",":"))+"\n"); c+=1
    return c

def dimensions():
    vo=[dict(voivodeship_code=c,voivodeship_name=n,population=p,wczk_seat=s,lat=lat,lon=lon) for c,n,p,s,lat,lon in VOIV]
    pow=[]
    for vc,vn,vp,seat,vlat,vlon in VOIV:
        names=list(SPEC_P.get(vc,[]))
        while len(names)<POW_N[vc]: names.append(f"{vn.split('-')[0]} powiat {len(names)+1:02d}")
        for i,name in enumerate(names,1):
            lat,lon=jit(vlat,vlon,.75)
            pow.append(dict(powiat_code=f"{vc}{i:02d}",powiat_name=name,voivodeship_code=vc,population=max(22000,int(random.gauss(vp/POW_N[vc],vp/POW_N[vc]*.35))),area_km2=round(random.uniform(250,2600),1),lat=lat,lon=lon))
    gmi=[]
    for vc in POW_N:
        ps=[p for p in pow if p["voivodeship_code"]==vc]
        specials=[(p,g) for p in ps for g in SPEC_G.get(p["powiat_name"],[])]
        rem=GMI_N[vc]-len(specials); per=[rem//len(ps)]*len(ps)
        for i in range(rem%len(ps)): per[i]+=1
        cnt=defaultdict(int)
        def add(p,gname,special=False):
            cnt[p["powiat_code"]]+=1; idx=cnt[p["powiat_code"]]; lat,lon=jit(float(p["lat"]),float(p["lon"]),.18 if special else .22)
            typ="miejska" if gname in ["Wrocław","Opole","Kłodzko","Nysa"] else random.choices(["miejska","wiejska","miejsko-wiejska"],[.18,.58,.24])[0]
            gmi.append(dict(gmina_code=f"{p['powiat_code']}{idx:03d}",gmina_name=gname,powiat_code=p["powiat_code"],gmina_type=typ,population=max(900,int(random.gauss(p["population"]/7,p["population"]/12))),lat=lat,lon=lon))
        for p,g in specials: add(p,g,True)
        for p,n in zip(ps,per):
            for _ in range(n): add(p,f"{p['powiat_name']} gmina {cnt[p['powiat_code']]+1:02d}")
    inst=[dict(institution_id=i,institution_code=c,institution_name=n,level=l,seat=s) for i,c,n,l,s in [("INST-001","RCB","Rządowe Centrum Bezpieczeństwa","krajowy","Warszawa"),("INST-002","KG_PSP","Komenda Główna PSP","krajowy","Warszawa"),("INST-003","POLICJA","Komenda Główna Policji","krajowy","Warszawa"),("INST-004","IMGW","IMGW-PIB","krajowy","Warszawa"),("INST-005","WODY_POLSKIE","PGW Wody Polskie","krajowy","Warszawa"),("INST-006","PSE","Polskie Sieci Elektroenergetyczne","krajowy","Konstancin-Jeziorna"),("INST-007","TELCO","Operatorzy telekomunikacyjni","krajowy","Warszawa"),("INST-008","NFZ","NFZ i szpitale","krajowy","Warszawa"),("INST-009","SG","Straż Graniczna","krajowy","Warszawa"),("INST-010","WOT","Wojska Obrony Terytorialnej","krajowy","Zegrze")]]
    for c,n,_,seat,_,_ in VOIV:
        inst += [dict(institution_id=f"INST-WCZK-{c}",institution_code=f"WCZK_{c}",institution_name=f"Wojewódzkie Centrum Zarządzania Kryzysowego - {n}",level="wojewódzki",seat=seat),dict(institution_id=f"INST-KWPSP-{c}",institution_code=f"KW_PSP_{c}",institution_name=f"Komenda Wojewódzka PSP - {n}",level="wojewódzki",seat=seat)]
    inst += [dict(institution_id=f"INST-PCZK-{p['powiat_code']}",institution_code=f"PCZK_{p['powiat_code']}",institution_name=f"Powiatowe Centrum Zarządzania Kryzysowego - {p['powiat_name']}",level="powiatowy",seat=p["powiat_name"]) for p in pow]
    by={g["gmina_name"]:g for g in gmi}; route=[("Kłodzko","Nysa Kłodzka",0,50.43,16.65),("Bardo","Nysa Kłodzka",5,50.50,16.74),("Nysa","Nysa Kłodzka",12,50.47,17.33),("Opole","Odra",24,50.67,17.92),("Brzeg","Odra",32,50.86,17.47),("Oława","Odra",40,50.95,17.29),("Wrocław","Odra",48,51.11,17.04),("Ścinawa","Odra",60,51.42,16.42),("Głogów","Odra",72,51.66,16.08),("Krosno Odrzańskie","Odra",88,52.05,15.10)]
    gauges=[]
    for i,(n,r,d,lat,lon) in enumerate(route,1):
        g=by.get(n) or random.choice(gmi); gauges.append(dict(gauge_id=f"WG-{i:03d}",gauge_name=n,river=r,gmina_code=g["gmina_code"],warning_level_cm=260+i*8,alarm_level_cm=330+i*10,lat=lat,lon=lon,wave_delay_h=d))
    rivers=["Nysa Kłodzka","Odra","Wisła","Bóbr","Bystrzyca","Kaczawa","Warta","Noteć","San","Bug"]
    for i in range(11,121):
        g=random.choice(gmi); r=random.choice(rivers); warn=random.randint(180,360)
        gauges.append(dict(gauge_id=f"WG-{i:03d}",gauge_name=f"{r} posterunek {i:03d}",river=r,gmina_code=g["gmina_code"],warning_level_cm=warn,alarm_level_cm=warn+random.randint(80,180),lat=g["lat"],lon=g["lon"],wave_delay_h=""))
    counts={"dim_voivodeship.csv":csvw("dim_voivodeship.csv",vo),"dim_powiat.csv":csvw("dim_powiat.csv",pow),"dim_gmina.csv":csvw("dim_gmina.csv",gmi),"dim_hazard.csv":csvw("dim_hazard.csv",[dict(hazard_code=c,hazard_name=n,lead_minister=lm,cooperating_ministers=cm) for c,n,lm,cm in HAZ]),"dim_institution.csv":csvw("dim_institution.csv",inst),"dim_spo.csv":csvw("dim_spo.csv",[dict(spo_code=c,spo_name=n) for c,n in SPO]),"dim_river_gauge.csv":csvw("dim_river_gauge.csv",gauges)}
    return vo,pow,gmi,gauges,counts

def impacted(g,powby):
    p=powby[g["powiat_code"]]
    return p["voivodeship_code"] in {"02","16"} and (p["powiat_name"] in {"kłodzki","nyski","opolski","Wrocław","Opole","wrocławski"} or g["gmina_name"] in {"Kłodzko","Bystrzyca Kłodzka","Lądek-Zdrój","Stronie Śląskie","Nysa","Opole","Wrocław"})

def hydro(gauges):
    prev={}
    for i in range(int((END-START).total_seconds()//300)+1):
        ts=START+timedelta(minutes=5*i)
        for g in gauges:
            alarm=int(g["alarm_level_cm"]); warn=int(g["warning_level_cm"]); base=warn-random.randint(45,90)
            if g["wave_delay_h"]!="":
                h=(ts-(D0+timedelta(hours=float(g["wave_delay_h"])))).total_seconds()/3600
                wave=(alarm-base+135)*math.exp(-(h/19)**2)+35*math.exp(-(((ts-(D0-timedelta(hours=20))).total_seconds()/3600)/15)**2)
            else:
                h=(ts-D0).total_seconds()/3600; wave=(30*math.exp(-((h-random.uniform(10,90))/35)**2) if g["river"] in {"Odra","Wisła","Warta"} else 0)+random.uniform(0,15)
            level=int(base+wave+8*math.sin(i/26)+random.gauss(0,4)); d=level-prev.get(g["gauge_id"],level); prev[g["gauge_id"]]=level
            yield dict(timestamp=iso(ts),stream="hydro_readings",gauge_id=g["gauge_id"],gmina_code=g["gmina_code"],river=g["river"],level_cm=level,flow_m3s=round(max(20,level*random.uniform(1.7,3.9)),1),trend="rising" if d>2 else "falling" if d<-2 else "stable",warning_level_cm=warn,alarm_level_cm=alarm)

def streams(vo,pow,gmi,gauges):
    counts={}; powby={p["powiat_code"]:p for p in pow}; imp=[g for g in gmi if impacted(g,powby)]; impc={g["gmina_code"] for g in imp}
    counts["hydro_readings.jsonl"]=jsonlw("hydro_readings.jsonl", hydro(gauges))
    def weather():
        t=START
        while t<=END:
            for p in pow:
                h=(t-(D0-timedelta(hours=28))).total_seconds()/3600
                ext=58*math.exp(-(h/21)**2) if p["powiat_name"] in {"kłodzki","nyski"} else 18*math.exp(-(h/26)**2) if p["voivodeship_code"] in {"02","16","24"} else 0
                yield dict(timestamp=iso(t),stream="weather_observations",powiat_code=p["powiat_code"],rain_mm_h=round(max(0,random.gauss(1,.8)+ext),1),temperature_c=round(random.uniform(11,18),1),wind_kmh=round(random.uniform(8,54),1),phenomenon="opad ekstremalny" if ext>30 else "opad" if ext>5 else "brak")
            t+=timedelta(hours=1)
    counts["weather_observations.jsonl"]=jsonlw("weather_observations.jsonl",weather())
    def incidents():
        eid=1; t=START; types=["zalanie budynku","podtopienie drogi","ewakuacja osoby","uszkodzenie wału","powalone drzewo","pomoc medyczna","pożar instalacji"]
        while t<=END:
            mult=9 if D0-timedelta(hours=18)<=t<=D0+timedelta(days=4) else 3 if t>D0+timedelta(days=4) else 1
            for _ in range(random.randint(0,3)+random.randint(0,mult)):
                g=random.choice(imp if random.random()<.72 else gmi); sev=random.choices([1,2,3,4,5],[.20,.30,.28,.17,.05] if g["gmina_code"] in impc else [.55,.30,.12,.03,0])[0]
                yield dict(timestamp=iso(t+timedelta(minutes=random.randint(0,14))),stream="incident_reports",incident_id=f"INC-{eid:06d}",source="112/PSP",hazard_code="Z02",event_type=random.choice(types),gmina_code=g["gmina_code"],priority=sev,injured_count=random.randint(0,sev-1),affected_people=random.randint(sev*2,sev*45),status=random.choice(["new","assigned","in_progress","closed"])); eid+=1
            t+=timedelta(minutes=15)
    counts["incident_reports.jsonl"]=jsonlw("incident_reports.jsonl",incidents())
    def simple_events(kind):
        eid=1; t=START+timedelta(hours=6)
        while t<=END:
            n=random.randint(0,2)+(random.randint(1,6) if D0<=t<=D0+timedelta(days=3) else 0) if kind=="power" else random.randint(0,1)+(random.randint(0,4) if D0+timedelta(hours=4)<=t<=D0+timedelta(days=4) else 0)
            for _ in range(n):
                g=random.choice(imp if random.random()<.76 else gmi)
                if kind=="power": yield dict(timestamp=iso(t+timedelta(minutes=random.randint(0,59))),stream="power_grid_events",event_id=f"PWR-{eid:05d}",station=f"GPZ-{g['gmina_name'][:18]}",gmina_code=g["gmina_code"],customers_offline=random.randint(120,6500) if g["gmina_code"] in impc else random.randint(20,900),eta_restore_min=random.randint(90,1440),cause=random.choice(["zalanie stacji","uszkodzenie linii","prewencyjne wyłączenie","awaria transformatora"]))
                else: yield dict(timestamp=iso(t+timedelta(minutes=random.randint(0,59))),stream="telecom_events",event_id=f"TEL-{eid:05d}",operator=random.choice(["operator_a","operator_b","operator_c"]),gmina_code=g["gmina_code"],base_stations_down=random.randint(1,8),coverage_pct=round(random.uniform(22,88),1),cause=random.choice(["brak zasilania","zalanie obiektu","przeciążenie","uszkodzenie światłowodu"]))
                eid+=1
            t+=timedelta(hours=1)
    counts["power_grid_events.jsonl"]=jsonlw("power_grid_events.jsonl",simple_events("power")); counts["telecom_events.jsonl"]=jsonlw("telecom_events.jsonl",simple_events("telecom"))
    def evac():
        eid=1
        for g in imp+random.sample(gmi,60):
            st=D0-timedelta(hours=18)+timedelta(hours=random.randint(0,96))
            for status,add in [("planned",0),("in_progress",random.randint(3,18)),("completed",random.randint(18,60))]:
                persons=random.randint(40,1800) if g["gmina_code"] in impc else random.randint(5,130)
                yield dict(timestamp=iso(st+timedelta(hours=add)),stream="evacuation_status",event_id=f"EVC-{eid:05d}",gmina_code=g["gmina_code"],status=status,people_count=persons,reception_capacity=persons+random.randint(80,1200),spo_code="SPO-3"); eid+=1
    counts["evacuation_status.jsonl"]=jsonlw("evacuation_status.jsonl",evac())
    def resources():
        eid=1; t=START
        while t<=END:
            for v in vo:
                heavy=v["voivodeship_code"] in {"02","16"}; phase=1 if t<D0 else 3 if t<D0+timedelta(days=4) else 2
                yield dict(timestamp=iso(t),stream="resource_deployment",event_id=f"RES-{eid:05d}",voivodeship_code=v["voivodeship_code"],psp_units=random.randint(20,80)*phase if heavy else random.randint(4,28),wot_soldiers=random.randint(80,650)*phase if heavy else random.randint(0,90),pumps=random.randint(8,80)*phase if heavy else random.randint(0,12),generators=random.randint(5,45)*phase if heavy else random.randint(0,8),helicopters=random.randint(0,4) if heavy and t>=D0 else 0); eid+=1
            t+=timedelta(hours=12)
    counts["resource_deployment.jsonl"]=jsonlw("resource_deployment.jsonl",resources())
    def media():
        eid=1; t=START; topics=["ewakuacja","skażona woda","zamknięte drogi","braki paliwa","pomoc sąsiedzka","fałszywe alerty RCB"]
        while t<=END:
            for _ in range(random.randint(1,5)+(random.randint(4,12) if D0<=t<=D0+timedelta(days=3) else 0)):
                dis=random.random()<(.18 if D0<=t<=D0+timedelta(days=3) else .04)
                yield dict(timestamp=iso(t+timedelta(minutes=random.randint(0,29))),stream="media_signals",signal_id=f"MED-{eid:05d}",topic=random.choice(topics),sentiment=random.choice(["negative","neutral","positive"]),reach=random.randint(500,220000),disinformation_flag=dis,hazard_code="Z20" if dis else "Z02",channel=random.choice(["x","facebook","portal","tv","telegram"])); eid+=1
            t+=timedelta(minutes=30)
    counts["media_signals.jsonl"]=jsonlw("media_signals.jsonl",media())
    ev=[(D0-timedelta(hours=8),"gmina","powiat","Kłodzko","przekroczenie stanów ostrzegawczych i liczne zgłoszenia 112"),(D0-timedelta(hours=4),"powiat","wojewoda","powiat kłodzki","brak wystarczających sił i środków w powiecie"),(D0+timedelta(hours=2),"wojewoda","minister wiodący","dolnośląskie","powódź obejmuje wiele powiatów oraz infrastrukturę krytyczną"),(D0+timedelta(hours=6),"minister wiodący","RZZK","kraj","zaangażowanie kilku ministrów: infrastruktura, energia, cyfryzacja, zdrowie, MSWiA"),(D0+timedelta(hours=8),"RZZK","RZZK","kraj","uruchomienie SPO-1, SPO-2, SPO-3, SPO-10 i monitorowanie SPO-5")]
    counts["escalation_events.jsonl"]=jsonlw("escalation_events.jsonl",(dict(timestamp=iso(ts),stream="escalation_events",event_id=f"ESC-{i:03d}",from_level=a,to_level=b,area=area,hazard_code="Z02",recommended_spo="SPO-1" if b=="RZZK" else "SPO-12",reason=r) for i,(ts,a,b,area,r) in enumerate(ev,1)))
    return counts

def readme(counts):
    desc={"dim_voivodeship.csv":"16 województw","dim_powiat.csv":"powiaty syntetyczne","dim_gmina.csv":"gminy syntetyczne","dim_hazard.csv":"20 zagrożeń KPZK","dim_institution.csv":"instytucje raportujące","dim_spo.csv":"16 SPO","dim_river_gauge.csv":"~120 wodowskazów","hydro_readings.jsonl":"fala Nysa Kłodzka→Odra co 5 min","weather_observations.jsonl":"pogoda per powiat","incident_reports.jsonl":"zgłoszenia 112/PSP","power_grid_events.jsonl":"awarie energetyczne","telecom_events.jsonl":"awarie telekom","evacuation_status.jsonl":"status ewakuacji","resource_deployment.jsonl":"siły i środki","media_signals.jsonl":"sygnały Z20","escalation_events.jsonl":"eskalacje poziomów"}
    lines=["# 📦 Datasety COP-24","","> ⚠️ Dane w 100% syntetyczne, wygenerowane proceduralnie z `seed=42`. Nie są danymi operacyjnymi żadnej instytucji.","","| Plik | Rekordy | Opis |","|---|---:|---|"]
    lines += [f"| `{k}` | {counts[k]} | {desc.get(k,'')} |" for k in sorted(counts)]
    (DATA_DIR/"README.md").write_text("\n".join(lines)+"\n",encoding="utf-8")

def main():
    DATA_DIR.mkdir(exist_ok=True)
    vo,pow,gmi,gauges,counts=dimensions(); counts.update(streams(vo,pow,gmi,gauges)); readme(counts)
    print(json.dumps(counts,ensure_ascii=False,indent=2))

if __name__ == "__main__":
    main()
