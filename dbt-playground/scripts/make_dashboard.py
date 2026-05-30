#!/usr/bin/env python3
"""마트 → 인터랙티브 ECharts 대시보드(dashboard.html). 의존성: duckdb(파이썬) + ECharts(CDN)."""
import json
from pathlib import Path
import duckdb

ROOT = Path(__file__).resolve().parents[1]
con = duckdb.connect(str(ROOT / "playground.duckdb"))


def q(sql):
    return con.execute(sql).fetchall()


# ── 데이터 조회 ─────────────────────────────────────────────────────────
# 보안: lang별 naive/wolfi HIGH+CRIT
sec_rows = q("select lang, variant, high_crit_vulns from main_security.mart_image_security")
langs = ["go", "python", "java"]
sec = {
    "langs": langs,
    "naive": [next((r[2] for r in sec_rows if r[0] == l and r[1] == "naive"), 0) for l in langs],
    "wolfi": [next((r[2] for r in sec_rows if r[0] == l and r[1] == "wolfi"), 0) for l in langs],
}

# F1: 시즌별 상위 6명 포인트 라인
seasons = [r[0] for r in q("select distinct season from main_f1.stg_driver_standings order by season")]
top6 = [r[0] for r in q("select driver_name from main_f1.mart_driver_career order by career_points desc limit 6")]
f1_series = []
for name in top6:
    pts = {s: p for s, p in q(
        f"select season, points from main_f1.stg_driver_standings where driver_name = '{name}'")}
    f1_series.append({"name": name, "data": [pts.get(s) for s in seasons]})
f1 = {"seasons": seasons, "series": f1_series}

# Pokemon: 800마리 산점도 [attack, defense, total, name, type1]
poke = [[a, d, t, n, ty] for n, a, d, t, ty in q(
    "select name, attack, defense, total, type1 from main_pokemon.stg_pokemon")]

# 택시: 시간대별 운행
taxi = [t for _, t in q("select pickup_hour, trips from main_public.mart_taxi_by_hour order by pickup_hour")]

data_js = (
    f"const SEC={json.dumps(sec)};\n"
    f"const F1={json.dumps(f1)};\n"
    f"const POKE={json.dumps(poke)};\n"
    f"const TAXI={json.dumps(taxi)};\n"
)

# ── ECharts 옵션 (정적 JS) ──────────────────────────────────────────────
chart_js = r"""
const AX = {axisLabel:{color:'#9aa7b4'}, axisLine:{lineStyle:{color:'#2d3543'}},
            splitLine:{lineStyle:{color:'#1c2330'}}};
const mk = id => echarts.init(document.getElementById(id), null, {renderer:'canvas'});

// 🛡️ 보안 그룹 바
mk('sec').setOption({
  backgroundColor:'transparent',
  tooltip:{trigger:'axis', axisPointer:{type:'shadow'}},
  legend:{data:['naive','wolfi'], textStyle:{color:'#cdd6df'}, top:0},
  grid:{left:44,right:16,top:36,bottom:28},
  xAxis:{type:'category', data:SEC.langs, ...AX},
  yAxis:{type:'value', ...AX},
  series:[
    {name:'naive', type:'bar', data:SEC.naive, itemStyle:{color:'#ff6b6b', borderRadius:[5,5,0,0]},
     label:{show:true, position:'top', color:'#ff9b9b'}},
    {name:'wolfi', type:'bar', data:SEC.wolfi, itemStyle:{color:'#3fb950', borderRadius:[5,5,0,0]},
     label:{show:true, position:'top', color:'#7ee787'}}
  ]
});

// 🏎️ F1 시즌별 포인트 라인
mk('f1').setOption({
  backgroundColor:'transparent',
  tooltip:{trigger:'axis'},
  legend:{textStyle:{color:'#cdd6df'}, top:0, type:'scroll', width:'90%'},
  grid:{left:44,right:16,top:54,bottom:28},
  xAxis:{type:'category', data:F1.seasons, boundaryGap:false, ...AX},
  yAxis:{type:'value', ...AX},
  series:F1.series.map(s=>({name:s.name, type:'line', smooth:true, connectNulls:true,
    data:s.data, symbolSize:6, lineStyle:{width:2.5},
    emphasis:{focus:'series'}}))
});

// ⚡ Pokemon 산점도 (공격 vs 방어, 색=종족값)
const totals = POKE.map(p=>p[2]);
mk('poke').setOption({
  backgroundColor:'transparent',
  tooltip:{formatter:p=>`<b>${p.data[3]}</b><br>${p.data[4]}<br>ATK ${p.data[0]} · DEF ${p.data[1]}<br>종족값 ${p.data[2]}`},
  visualMap:{min:Math.min(...totals), max:Math.max(...totals), dimension:2, calculable:true,
    orient:'horizontal', left:'center', bottom:0, itemHeight:80,
    inRange:{color:['#37c8ab','#e3b341','#ff6b6b']}, textStyle:{color:'#9aa7b4'}},
  grid:{left:44,right:16,top:14,bottom:54},
  xAxis:{name:'Attack', nameTextStyle:{color:'#9aa7b4'}, ...AX},
  yAxis:{name:'Defense', nameTextStyle:{color:'#9aa7b4'}, ...AX},
  series:[{type:'scatter', data:POKE, symbolSize:d=>Math.max(5, d[2]/45),
    itemStyle:{opacity:0.75}}]
});

// 🚕 택시 24시간 시계 (polar bar)
mk('taxi').setOption({
  backgroundColor:'transparent',
  tooltip:{formatter:p=>`${p.name}시<br>${p.value.toLocaleString()} 운행`},
  polar:{radius:['18%','78%']},
  angleAxis:{type:'category', data:[...Array(24).keys()], startAngle:90,
    axisLabel:{color:'#9aa7b4'}, axisLine:{lineStyle:{color:'#2d3543'}}},
  radiusAxis:{axisLabel:{color:'#5d6b7a'}, splitLine:{lineStyle:{color:'#1c2330'}}},
  series:[{type:'bar', data:TAXI, coordinateSystem:'polar',
    itemStyle:{color:new echarts.graphic.LinearGradient(0,0,0,1,[
      {offset:0,color:'#37c8ab'},{offset:1,color:'#1c5c52'}]), borderRadius:3}}]
});

window.addEventListener('resize',()=>document.querySelectorAll('.chart').forEach(
  el=>echarts.getInstanceByDom(el)?.resize()));
"""

page = (
    '<!DOCTYPE html><html lang="ko"><head><meta charset="UTF-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1.0">'
    "<title>dbt 놀이터 대시보드</title>"
    '<script src="https://cdn.jsdelivr.net/npm/echarts@5.5.0/dist/echarts.min.js"></script>'
    "<style>"
    "body{margin:0;background:#0d1117;color:#e6edf3;"
    'font-family:-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif}'
    ".wrap{max-width:1180px;margin:0 auto;padding:40px 24px 80px}"
    "h1{font-size:28px;margin:0 0 4px}.sub{color:#9aa7b4;margin:0 0 28px}"
    ".grid{display:grid;grid-template-columns:1fr 1fr;gap:18px}"
    "@media(max-width:860px){.grid{grid-template-columns:1fr}}"
    ".card{background:#161b22;border:1px solid #2d3543;border-radius:14px;padding:18px 18px 8px}"
    ".card h3{margin:0 0 4px;font-size:16px}.card h3 span{color:#9aa7b4;font-weight:400;font-size:13px}"
    ".chart{width:100%;height:320px}"
    "</style></head><body><div class='wrap'>"
    "<h1>dbt 놀이터 대시보드</h1>"
    "<p class='sub'>6개 도메인 마트 · 인터랙티브(호버·줌·범례 클릭). 같은 dbt 모델, 살아있는 차트.</p>"
    "<div class='grid'>"
    "<div class='card'><h3>🛡️ 이미지 HIGH/CRITICAL <span>naive vs wolfi</span></h3><div id='sec' class='chart'></div></div>"
    "<div class='card'><h3>🏎️ F1 시즌별 포인트 <span>상위 6인 · 범례 클릭으로 토글</span></h3><div id='f1' class='chart'></div></div>"
    "<div class='card'><h3>⚡ Pokemon 800마리 <span>공격 vs 방어 · 색=종족값 · 호버로 이름</span></h3><div id='poke' class='chart'></div></div>"
    "<div class='card'><h3>🚕 NYC 택시 24시간 시계 <span>운행량</span></h3><div id='taxi' class='chart'></div></div>"
    "</div>"
    f"<script>{data_js}{chart_js}</script>"
    "</div></body></html>"
)

(ROOT / "dashboard.html").write_text(page)
print("wrote", ROOT / "dashboard.html")
