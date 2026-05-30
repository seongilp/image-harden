#!/usr/bin/env python3
"""마트들을 쿼리해 SVG 차트 대시보드(dashboard.html) 생성. 의존성: duckdb(파이썬)."""
import html
from pathlib import Path
import duckdb

ROOT = Path(__file__).resolve().parents[1]
con = duckdb.connect(str(ROOT / "playground.duckdb"))


def q(sql):
    return con.execute(sql).fetchall()


def esc(s):
    return html.escape(str(s))


# ── SVG 가로 막대 차트 ──────────────────────────────────────────────────
def hbar(rows, unit="", colors=None, w=520, label_w=150):
    rh, gap, pad = 30, 8, 10
    maxv = max((v for _, v in rows), default=1) or 1
    bar_w = w - label_w - 70
    h = pad * 2 + len(rows) * (rh + gap)
    out = [f'<svg viewBox="0 0 {w} {h}" width="100%" style="max-width:{w}px">']
    for i, (label, val) in enumerate(rows):
        y = pad + i * (rh + gap)
        bw = max(2, bar_w * val / maxv)
        col = colors[i] if colors else "#7c5cff"
        out.append(f'<text x="{label_w-8}" y="{y+rh/2+5}" text-anchor="end" '
                   f'fill="#cdd6df" font-size="13">{esc(label)}</text>')
        out.append(f'<rect x="{label_w}" y="{y}" width="{bw:.1f}" height="{rh}" rx="5" fill="{col}"/>')
        out.append(f'<text x="{label_w+bw+8:.1f}" y="{y+rh/2+5}" fill="#e6edf3" '
                   f'font-size="13" font-weight="700">{val:g}{unit}</text>')
    out.append('</svg>')
    return "\n".join(out)


# ── SVG 세로 막대(시간대) ───────────────────────────────────────────────
def columns(rows, w=560, h=200, color="#37c8ab"):
    pad_b, pad_t, pad_l = 26, 12, 8
    maxv = max((v for _, v in rows), default=1) or 1
    cw = (w - pad_l) / len(rows)
    out = [f'<svg viewBox="0 0 {w} {h}" width="100%" style="max-width:{w}px">']
    for i, (label, val) in enumerate(rows):
        bh = (h - pad_b - pad_t) * val / maxv
        x = pad_l + i * cw
        y = h - pad_b - bh
        out.append(f'<rect x="{x+1:.1f}" y="{y:.1f}" width="{cw-2:.1f}" height="{bh:.1f}" rx="2" fill="{color}"/>')
        if i % 3 == 0:
            out.append(f'<text x="{x+cw/2:.1f}" y="{h-10}" text-anchor="middle" '
                       f'fill="#9aa7b4" font-size="11">{esc(label)}</text>')
    out.append('</svg>')
    return "\n".join(out)


# ── 데이터 조회 ─────────────────────────────────────────────────────────
sec = q("select lang||' · '||variant, high_crit_vulns from main_security.mart_image_security order by lang, variant")
sec_colors = ["#ff6b6b" if "naive" in r[0] else "#3fb950" for r in sec]

f1 = q("select driver_name, career_points from main_f1.mart_driver_career limit 8")
poke = q("select type1, avg_total from main_pokemon.mart_type_strength limit 10")
taxi = q("select pickup_hour, trips from main_public.mart_taxi_by_hour order by pickup_hour")

charts = f"""
<div class="grid">
  <div class="card"><h3>🛡️ 이미지 HIGH/CRITICAL 취약점 <span>naive vs wolfi</span></h3>
    {hbar([(r[0], r[1]) for r in sec], colors=sec_colors)}
    <p class="cap">빨강=naive · 초록=wolfi. wolfi는 전부 0.</p></div>

  <div class="card"><h3>🏎️ F1 통산 포인트 TOP 8 <span>2010~2024</span></h3>
    {hbar([(r[0], round(r[1])) for r in f1], colors=["#37c8ab"]*8)}</div>

  <div class="card"><h3>⚡ Pokemon 주 타입별 평균 종족값 TOP 10</h3>
    {hbar([(r[0], r[1]) for r in poke], colors=["#e3b341"]*10)}</div>

  <div class="card"><h3>🚕 NYC 택시 시간대별 운행 수 <span>0~23시</span></h3>
    {columns([(r[0], r[1]) for r in taxi])}
    <p class="cap">오후(12~18시)에 운행 집중.</p></div>
</div>
"""

page = f"""<!DOCTYPE html><html lang="ko"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>dbt 놀이터 대시보드</title>
<style>
  body{{margin:0;background:#0d1117;color:#e6edf3;
    font-family:-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif;}}
  .wrap{{max-width:1180px;margin:0 auto;padding:40px 24px 80px}}
  h1{{font-size:28px;margin:0 0 4px}} .sub{{color:#9aa7b4;margin:0 0 28px}}
  .grid{{display:grid;grid-template-columns:1fr 1fr;gap:18px}}
  @media(max-width:860px){{.grid{{grid-template-columns:1fr}}}}
  .card{{background:#161b22;border:1px solid #2d3543;border-radius:14px;padding:20px}}
  .card h3{{margin:0 0 14px;font-size:16px}} .card h3 span{{color:#9aa7b4;font-weight:400;font-size:13px}}
  .cap{{color:#9aa7b4;font-size:12px;margin:10px 0 0}}
</style></head><body><div class="wrap">
<h1>dbt 놀이터 대시보드</h1>
<p class="sub">6개 도메인 마트를 차트로. 같은 dbt 모델, 표 대신 그림.</p>
{charts}
</div></body></html>"""

(ROOT / "dashboard.html").write_text(page)
print("wrote", ROOT / "dashboard.html")
