#!/usr/bin/env python3
"""Generate full Baseball Savvy StatScout ASC locale readout + apply fastlane metadata."""
from __future__ import annotations

import importlib.util
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"
ASTRO = Path("/tmp/aso_en_pop_baseball_full.json")
if not ASTRO.exists():
    ASTRO = Path("/tmp/aso_en_keyword_pop_checkpoint.json")

_apply = Path(__file__).parent / "aso-apply-locale-optimizations.py"
_spec = importlib.util.spec_from_file_location("aso_apply", _apply)
_mod = importlib.util.module_from_spec(_spec)
assert _spec.loader
_spec.loader.exec_module(_mod)
BASE_KW: dict[str, str] = _mod.KEYWORDS

LOCALE_TO_STORE = {
    "ar-SA": "sa", "bn-BD": "in", "ca": "es", "cs": "cz", "da": "dk",
    "de-DE": "de", "el": "gr", "en-AU": "au", "en-CA": "ca", "en-GB": "gb",
    "en-US": "us", "es-ES": "es", "es-MX": "mx", "fi": "fi", "fr-CA": "ca",
    "fr-FR": "fr", "gu-IN": "in", "he": "il", "hi": "in", "hr": "hr",
    "hu": "hu", "id": "id", "it": "it", "ja": "jp", "kn-IN": "in", "ko": "kr",
    "ml-IN": "in", "mr-IN": "in", "ms": "my", "nl-NL": "nl", "no": "no",
    "or-IN": "in", "pa-IN": "in", "pl": "pl", "pt-BR": "br", "pt-PT": "pt",
    "ro": "ro", "ru": "ru", "sk": "sk", "sl-SI": "si", "sv": "se",
    "ta-IN": "in", "te-IN": "in", "th": "th", "tr": "tr", "uk": "ua",
    "ur-PK": "sa", "vi": "vn", "zh-Hans": "cn", "zh-Hant": "tw",
}
ASTRO_STORE_FALLBACK = {"si": "hr"}

# aso-plan US pool (no era/leaderboard; percentile/analytics cluster)
EN_US_KW = (
    "savant,xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,"
    "metrics,percentile,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,comparison"
)

EN_CANDIDATES = [
    "statcast", "savant", "xwoba", "oaa", "wrc", "wrcplus", "barrel", "exit",
    "velocity", "hitting", "pitching", "fielding", "metrics", "percentile",
    "analytics", "hardhit", "launch", "xslg", "xba", "whiff", "sabermetrics",
    "comparison", "ranking", "fantasy", "dfs",
]

NAMES: dict[str, str] = {
    "en-US": "Baseball Savvy StatScout",
    "en-AU": "Baseball Savvy StatScout",
    "en-CA": "Baseball Savvy StatScout",
    "en-GB": "Baseball Savvy StatScout",
    "de-DE": "Statcast Perzentile · MLB Scout",
    "fr-FR": "Statcast MLB · Stats Savant",
    "fr-CA": "Statcast MLB · Stats Savant",
    "es-ES": "Statcast MLB · Percentiles Savant",
    "es-MX": "Statcast MLB · Percentiles Savant",
    "ca": "Statcast MLB · Percentils Savant",
    "it": "Statcast MLB · Percentili Savant",
    "pt-BR": "Statcast MLB · Percentis Savant",
    "pt-PT": "Statcast MLB · Percentis Savant",
    "nl-NL": "MLB Statcast · Percentiel Scout",
    "pl": "Statcast MLB · Percentyle Scout",
    "sv": "MLB Statcast · Percentil Scout",
    "da": "MLB Statcast · Percentil Scout",
    "no": "MLB Statcast · Percentil Scout",
    "fi": "MLB Statcast · Prosentti Scout",
    "cs": "MLB Statcast · Percentil Scout",
    "sk": "MLB Statcast · Percentil Scout",
    "hu": "MLB Statcast · Százalék Scout",
    "ro": "Statcast MLB · Percentile Scout",
    "hr": "MLB Statcast · Postotak Scout",
    "el": "MLB Statcast · Ποσοστό Scout",
    "tr": "MLB Statcast · Yüzdelik Scout",
    "ru": "MLB Statcast · Процентили Scout",
    "uk": "MLB Statcast · Відсотки Scout",
    "ja": "MLBスタットキャスト百分位スカウト分析アプリ用",
    "ko": "MLB 스탯캐스트 백분위 스카우트 분석 앱용",
    "zh-Hans": "MLB棒球Statcast百分位球探数据分析应用",
    "zh-Hant": "MLB棒球Statcast百分位球探數據分析應用",
    "ar-SA": "ستاتكاست MLB · نسب مئوية",
    "he": "סטטקאסט MLB · אחוזונים סקאוט",
    "hi": "MLB स्टैटकास्ट प्रतिशत स्काउट ऐप",
    "bn-BD": "MLB স্ট্যাটকাস্ট শতাংশ স্কাউট",
    "th": "สถิติ MLB Statcast เปอร์เซ็นไทล์",
    "vi": "MLB Statcast · Phần trăm Scout",
    "id": "Statcast MLB · Persentil Scout",
    "ms": "Statcast MLB · Peratus Scout",
    "gu-IN": "MLB સ્ટેટકાસ્ટ ટકાવારી સ્કાઉટ",
    "kn-IN": "MLB ಸ್ಟ್ಯಾಟ್‌ಕಾಸ್ಟ್ ಶೇಕಡಾ ಸ್ಕೌಟ್",
    "ml-IN": "MLB സ്റ്റാറ്റ്‌കാസ്റ്റ് ശതമാനം",
    "mr-IN": "MLB स्टॅटकास्ट टक्केवारी स्काउट",
    "or-IN": "MLB ଷ୍ଟାଟକାସ୍ଟ ଶତାଂଶ ସ୍କାଉଟ୍",
    "pa-IN": "MLB ਸਟੈਟਕਾਸਟ ਪ੍ਰਤੀਸ਼ਤ ਸਕਾਊਟ",
    "ta-IN": "MLB ஸ்டாட்காஸ்ட் சதவீத ஸ்கவுட்",
    "te-IN": "MLB స్టాట్‌కాస్ట్ శాతం స్కౌట్",
    "ur-PK": "MLB اسٹیٹ کاسٹ فیصد اسکاؤٹ",
    "sl-SI": "MLB Statcast · Percentil Scout",
}

SUBTITLES: dict[str, str] = {
    "en-US": "MLB Statcast Percentile Ranks",
    "en-AU": "MLB Statcast Percentile Ranks",
    "en-CA": "MLB Statcast Percentile Ranks",
    "en-GB": "MLB Statcast Percentile Ranks",
    "de-DE": "MLB Statcast Perzentil-Ränge",
    "fr-FR": "Classements percentiles Statcast",
    "fr-CA": "Classements percentiles Statcast",
    "es-ES": "Rangos percentiles MLB Statcast",
    "es-MX": "Rangos percentiles MLB Statcast",
    "ca": "Rangs percentils MLB Statcast",
    "it": "Classifiche percentili Statcast",
    "pt-BR": "Rankings percentis MLB Statcast",
    "pt-PT": "Rankings percentis MLB Statcast",
    "nl-NL": "MLB Statcast percentielranglijst",
    "pl": "Rankingi percentyli MLB Statcast",
    "sv": "MLB Statcast percentilrankning",
    "da": "MLB Statcast percentilrangering",
    "no": "MLB Statcast percentilrangering",
    "fi": "MLB Statcast prosenttijärjestys",
    "cs": "Percentilové žebříčky Statcast",
    "sk": "Percentilové rebríčky Statcast",
    "hu": "MLB Statcast százalékos rang",
    "ro": "Clasamente percentile MLB Statcast",
    "hr": "Percentilni rangovi MLB Statcast",
    "el": "Κατάταξη ποσοστιαίων Statcast",
    "tr": "MLB Statcast yüzdelik sıralama",
    "ru": "Процентильные ранги MLB Statcast",
    "uk": "Процентильні ранги MLB Statcast",
    "ja": "MLBスタットキャスト百分位順位と分析データ表示",
    "ko": "MLB 스탯캐스트 백분위 순위 및 분석 데이터",
    "zh-Hans": "MLB Statcast百分位排名与棒球数据分析",
    "zh-Hant": "MLB Statcast百分位排名與棒球數據分析",
    "ar-SA": "ترتيب النسب المئوية MLB Statcast",
    "he": "דירוג אחוזונים MLB Statcast",
    "hi": "MLB Statcast प्रतिशत रैंकिंग डेटा",
    "bn-BD": "MLB Statcast শতাংশ র‍্যাঙ্কিং ডেটা",
    "th": "อันดับเปอร์เซ็นไทล์ MLB Statcast",
    "vi": "Xếp hạng phần trăm MLB Statcast",
    "id": "Peringkat persentil MLB Statcast",
    "ms": "Kedudukan peratus MLB Statcast",
    "gu-IN": "MLB Statcast ટકાવારી રેન્ક ડેટા",
    "kn-IN": "MLB Statcast ಶೇಕಡಾ ರ್ಯಾಂಕ್ ಡೇಟಾ",
    "ml-IN": "MLB Statcast ശതമാന റാങ്ക് ഡാറ്റ",
    "mr-IN": "MLB Statcast टक्केवारी रँकिंग डेटा",
    "or-IN": "MLB Statcast ଶତାଂଶ ର୍ୟାଙ୍କ ଡାଟା",
    "pa-IN": "MLB Statcast ਪ੍ਰਤੀਸ਼ਤ ਰੈਂਕ ਡੇਟਾ",
    "ta-IN": "MLB Statcast சதவீத தரவரிசை தரவு",
    "te-IN": "MLB Statcast శాతం ర్యాంక్ డేటా",
    "ur-PK": "MLB Statcast فیصد درجہ بندی ڈیٹا",
    "sl-SI": "Percentilni rangi MLB Statcast",
}

EXTRA_KW: dict[str, str] = {
    "de-DE": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,vergleich,metriken",
    "es-ES": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,comparación,ranking",
    "es-MX": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,comparación,ranking",
    "nl-NL": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,vergelijking,ranglijst",
    "hr": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,usporedba,rang",
    "ms": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,perbandingan,kedudukan",
    "bn-BD": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,র‍্যাঙ্কিং,তুলনা",
    "kn-IN": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,ಶ್ರೇಯಾಂಕ,ಹೋಲಿಕೆ",
    "mr-IN": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,रँकिंग,तुलना",
    "te-IN": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,ర్యాంకింగ్,పోలిక",
    "ur-PK": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,درجہ,موازنہ",
    "fr-FR": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,comparaison,classement",
    "fr-CA": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,comparaison,classement",
    "it": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,confronto,classifica",
    "id": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,perbandingan,peringkat",
    "sl-SI": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,primerjava,lestvica",
    "no": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,sammenligning,ranking",
    "ko": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,비교,순위,타격,투구,수비",
    "zh-Hans": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,对比,排名,打击,投球,守备",
    "zh-Hant": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,對比,排名,打擊,投球,守備",
    "ar-SA": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,مقارنة,تصنيف,ضرب,رمي",
    "gu-IN": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,સરખામણી,રેન્કિંગ",
    "hu": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,összehasonlítás,rangsor",
    "cs": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,porovnání,žebříček",
    "sk": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,porovnanie,rebríček",
    "ro": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,comparare,clasament",
    "ta-IN": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,ஒப்பீடு,தரவரிசை",
    "or-IN": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,ତୁଳନା,ର୍ୟାଙ୍କିଂ",
    "pa-IN": "xwoba,oaa,wrc,wrcplus,barrel,exit,velocity,hitting,pitching,fielding,metrics,analytics,hardhit,launch,xslg,xba,whiff,sabermetrics,ਤੁਲਨਾ,ਰੈਂਕਿੰਗ",
}

EXTRA_NATIVE: dict[str, list[str]] = {
    "ja": ["打撃", "投球", "守備", "比較", "分析", "ランキング", "メトリクス"],
    "ko": ["타격", "투구", "수비", "비교", "분석", "메트릭"],
    "zh-Hans": ["打击", "投球", "守备", "对比", "分析", "指标"],
    "zh-Hant": ["打擊", "投球", "守備", "對比", "分析", "指標"],
    "th": ["ตี", "ขว้าง", "รับ", "เปรียบเทียบ", "วิเคราะห์"],
    "tr": ["vuruş", "atış", "savunma", "karşılaştırma", "analitik"],
    "hi": ["बल्लेबाजी", "गेंदबाजी", "तुलना", "रैंकिंग"],
    "fi": ["lyönti", "syöttö", "vertailu", "tilastot"],
    "pt-BR": ["rebatida", "arremesso", "campo", "comparação"],
    "pt-PT": ["rebatida", "arremesso", "campo", "comparação"],
    "ca": ["batuda", "llançament", "comparació", "rànquing"],
    "pl": ["odbicie", "rzut", "porównanie", "ranking"],
    "ru": ["отбивание", "подача", "сравнение", "рейтинг"],
    "uk": ["відбивання", "подача", "порівняння", "рейтинг"],
}


def load_astro() -> dict:
    raw = json.loads(ASTRO.read_text())
    if "baseball" in raw:
        return raw["baseball"]
    return raw


def astro_pop(astro: dict, store: str, term: str) -> int | None:
    meta = astro.get(store, {}).get(term.lower()) or astro.get(store, {}).get(term)
    if not meta or meta.get("skipped"):
        return None
    p = meta.get("pop")
    return int(p) if isinstance(p, (int, float)) else None


def indexed(name: str, subtitle: str) -> set[str]:
    out: set[str] = set()
    for w in re.findall(r"[a-z0-9']+", f"{name} {subtitle}".lower()):
        if len(w) >= 2:
            out.add(w)
    for c in re.findall(r"[\u0600-\u06ff\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af\u0900-\u097f]+", name + subtitle):
        if len(c) >= 2:
            out.add(c)
    return out


def pack_keywords(tokens: list[str], limit: int = 100) -> str:
    out, n, seen = [], 0, set()
    for t in tokens:
        key = t.lower() if t.isascii() else t
        if key in seen:
            continue
        add = len(t) + (1 if out else 0)
        if n + add > limit:
            continue
        out.append(t)
        seen.add(key)
        n += add
    return ",".join(out)


def build_keywords(locale: str, name: str, subtitle: str, native: list[str], astro: dict, store: str) -> tuple[str, list[str]]:
    idx = indexed(name, subtitle)
    astro_store = ASTRO_STORE_FALLBACK.get(store, store)
    tokens: list[str] = []
    en_kept: list[str] = []

    for t in native:
        tl = t.lower() if t.isascii() else t
        if tl in idx or t in name or t in subtitle:
            continue
        tokens.append(t)
    existing = {t.lower() for t in tokens}

    if not locale.startswith("en-"):
        ranked = []
        for term in EN_CANDIDATES:
            p = astro_pop(astro, astro_store, term)
            if p is not None and p >= 6:
                ranked.append((p, term))
        ranked.sort(reverse=True)
        for p, term in ranked:
            if term.lower() not in existing and term.lower() not in idx:
                tokens.append(term)
                en_kept.append(f"{term}({p})")
                existing.add(term.lower())

    for t in EXTRA_NATIVE.get(locale, []):
        tl = t.lower() if t.isascii() else t
        if tl not in idx and tl not in existing:
            tokens.append(t)
            existing.add(tl)

    kw = pack_keywords(tokens, 100)
    if len(kw) < 94:
        for term in EN_CANDIDATES:
            p = astro_pop(astro, astro_store, term)
            if p is None or p < 6 or term.lower() in existing or term.lower() in idx:
                continue
            trial = pack_keywords(tokens + [term], 100)
            if len(trial) > len(kw):
                tokens.append(term)
                existing.add(term.lower())
                tag = f"{term}({p})"
                if tag not in en_kept:
                    en_kept.append(tag)
                kw = trial
            if len(kw) >= 94:
                break
    return kw, en_kept


def trim_field(s: str, limit: int) -> str:
    return s[:limit] if len(s) > limit else s


def keyword_pool(locale: str) -> str:
    if locale.startswith("en-"):
        return EN_US_KW
    return EXTRA_KW.get(locale) or BASE_KW.get(locale) or BASE_KW.get("en-US", "")


def all_locales() -> dict[str, dict[str, str]]:
    locs: dict[str, dict[str, str]] = {}
    for loc in sorted(LOCALE_TO_STORE):
        locs[loc] = {
            "name": NAMES[loc],
            "subtitle": SUBTITLES.get(loc, SUBTITLES["en-US"]),
            "native_kw": keyword_pool(loc),
        }
    return locs


def main() -> None:
    astro = load_astro()
    locales = all_locales()
    report: dict = {}
    issues: list[str] = []

    for locale, spec in locales.items():
        store = LOCALE_TO_STORE[locale]
        name = trim_field(spec["name"], 30)
        subtitle = trim_field(spec["subtitle"], 30)
        native = [t.strip() for t in spec["native_kw"].split(",") if t.strip()]
        kw, en_kept = build_keywords(locale, name, subtitle, native, astro, store)
        overlaps = [t for t in kw.split(",") if t.lower() in indexed(name, subtitle)]
        entry = {
            "store": store,
            "title": name,
            "subtitle": subtitle,
            "keywords": kw,
            "title_len": len(name),
            "subtitle_len": len(subtitle),
            "keywords_len": len(kw),
            "keyword_overlaps": overlaps,
            "astro_en_kept": en_kept,
            "astro_proof": (
                [f"EN loanwords Astro pop≥6: {', '.join(en_kept)}"] if en_kept
                else ["Native/transliterated keywords only; no EN loanwords met pop≥6 in this store."]
            ),
            "rationale": (
                f"{'StatScout brand in title (en-*).' if locale.startswith('en-') else 'Localized title; no English brand paste.'} "
                f"MLB Statcast percentile ranks positioning; keywords deduped vs title+subtitle, packed {len(kw)}/100."
            ),
            "ok": len(name) >= 24 and len(subtitle) >= 24 and len(kw) >= 94 and not overlaps,
        }
        if len(name) < 24:
            issues.append(f"{locale} title {len(name)}<24")
        if len(subtitle) < 24:
            issues.append(f"{locale} subtitle {len(subtitle)}<24")
        if len(kw) < 94:
            issues.append(f"{locale} keywords {len(kw)}<94")
        if overlaps:
            issues.append(f"{locale} kw overlaps: {overlaps}")
        report[locale] = entry

        d = META / locale
        d.mkdir(parents=True, exist_ok=True)
        (d / "name.txt").write_text(name + "\n", encoding="utf-8")
        (d / "subtitle.txt").write_text(subtitle + "\n", encoding="utf-8")
        (d / "keywords.txt").write_text(kw + "\n", encoding="utf-8")

    out_json = ROOT / "scripts" / "aso-baseball-locale-readout.json"
    out_md = ROOT / "scripts" / "aso-baseball-locale-readout.md"
    out_json.write_text(json.dumps({"locales": report, "issues": issues}, ensure_ascii=False, indent=2))

    lines = [
        "# Baseball Savvy StatScout — full locale readout (proposed ASC metadata)\n",
        "Policy: StatScout brand in **title** for en-* only · Statcast percentile ranks · EN loanwords if Astro pop≥6\n",
    ]
    for loc, e in report.items():
        lines.append(f"## {loc} (store: `{e['store']}`)\n")
        lines.append(f"**Title** ({e['title_len']}/30): {e['title']}\n")
        lines.append(f"**Subtitle** ({e['subtitle_len']}/30): {e['subtitle']}\n")
        lines.append(f"**Keywords** ({e['keywords_len']}/100): {e['keywords']}\n")
        if e["astro_en_kept"]:
            lines.append(f"**Astro EN:** {', '.join(e['astro_en_kept'])}\n")
        lines.append(f"**Why:** {e['rationale']}\n")
        lines.append(f"**Astro proof:** {' '.join(e['astro_proof'])}\n")
    if issues:
        lines.append("\n## Warnings\n")
        for i in issues:
            lines.append(f"- {i}\n")
    out_md.write_text("".join(lines))

    print(f"Wrote {out_json}")
    print(f"Wrote {out_md}")
    print(f"Locales: {len(report)}, warnings: {len(issues)}, ok: {sum(1 for e in report.values() if e['ok'])}")


if __name__ == "__main__":
    main()
