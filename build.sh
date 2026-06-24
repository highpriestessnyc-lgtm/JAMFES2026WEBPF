#!/bin/bash
# =============================================
# JAMFes2026 WEBパンフ 自動ビルドスクリプト
# 使い方: bash build.sh JAMFES2026WEBPF.pdf
# =============================================

set -e

PDF="${1:-JAMFES2026WEBPF.pdf}"
OUT_DIR="jamfes_web"
IMG_DIR="$OUT_DIR/pages"

# --- チェック ---
if [ ! -f "$PDF" ]; then
  echo "❌ PDFが見つかりません: $PDF"
  echo "   使い方: bash build.sh JAMFES2026WEBPF.pdf"
  exit 1
fi

echo "✅ PDF確認: $PDF"

# --- 依存チェック ---
if ! command -v pdftoppm &>/dev/null; then
  echo "📦 poppler-utils をインストール中..."
  if [[ "$OSTYPE" == "darwin"* ]]; then
    brew install poppler
  else
    sudo apt-get install -y poppler-utils
  fi
fi

# --- ディレクトリ作成 ---
mkdir -p "$IMG_DIR"
echo "📁 出力先: $OUT_DIR/"

# --- PDF → JPEG変換 ---
echo "🖼  ページ画像を変換中..."
pdftoppm -jpeg -r 150 -jpegopt quality=88 "$PDF" "$IMG_DIR/p"

# ページ数カウント
TOTAL=$(ls "$IMG_DIR"/p-*.jpg 2>/dev/null | wc -l)
if [ "$TOTAL" -eq 0 ]; then
  # pdftoppmのファイル名形式が違う場合
  TOTAL=$(ls "$IMG_DIR"/p*.jpg 2>/dev/null | wc -l)
fi

echo "📄 合計 $TOTAL ページ変換完了"

# ファイル名を連番に正規化 (p-01.jpg → p01.jpg)
cd "$IMG_DIR"
for f in p-*.jpg; do
  [ -f "$f" ] || continue
  num="${f#p-}"
  mv "$f" "p$num"
done
cd - > /dev/null

# --- HTML生成 ---
echo "🔨 HTML生成中..."

# ページ画像リストをJS配列として生成
PAGES_JS=""
for f in $(ls "$IMG_DIR"/p*.jpg | sort); do
  fname=$(basename "$f")
  PAGES_JS+="  'pages/$fname',\n"
done

cat > "$OUT_DIR/index.html" << HTMLEOF
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<title>JAMFes2026 — デジタルパンフレット</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    background: #111;
    display: flex;
    flex-direction: column;
    align-items: center;
    min-height: 100vh;
    font-family: 'Helvetica Neue', Arial, sans-serif;
    overflow-x: hidden;
    user-select: none;
  }

  header {
    width: 100%;
    background: #0a0a0a;
    border-bottom: 1px solid rgba(255,230,0,0.25);
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 16px;
    position: sticky;
    top: 0;
    z-index: 100;
    gap: 10px;
    flex-wrap: wrap;
  }

  .logo {
    font-size: 0.95rem;
    font-weight: 700;
    color: #FFE600;
    letter-spacing: 0.06em;
    white-space: nowrap;
  }

  .controls {
    display: flex;
    align-items: center;
    gap: 6px;
    flex-wrap: wrap;
  }

  .btn {
    background: rgba(255,255,255,0.07);
    border: 1px solid rgba(255,255,255,0.15);
    color: #fff;
    padding: 6px 14px;
    border-radius: 4px;
    font-size: 0.8rem;
    cursor: pointer;
    transition: all 0.15s;
    white-space: nowrap;
  }
  .btn:hover { background: rgba(255,230,0,0.15); border-color: #FFE600; color: #FFE600; }
  .btn:active { transform: scale(0.95); }
  .btn:disabled { opacity: 0.25; cursor: default; pointer-events: none; }

  .page-input {
    width: 46px;
    background: rgba(255,255,255,0.07);
    border: 1px solid rgba(255,255,255,0.2);
    color: #fff;
    text-align: center;
    padding: 5px 4px;
    border-radius: 4px;
    font-size: 0.8rem;
  }

  .page-total {
    color: rgba(255,255,255,0.4);
    font-size: 0.8rem;
    white-space: nowrap;
  }

  /* ===== VIEWER ===== */
  #viewer {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px 16px 70px;
    width: 100%;
    min-height: calc(100vh - 50px - 58px);
  }

  /* ===== FLIP STAGE ===== */
  .flip-stage {
    perspective: 1800px;
    position: relative;
  }

  .flip-card {
    position: relative;
    transform-style: preserve-3d;
    transition: none;
  }

  .flip-card.flip-next {
    animation: flipNext 0.42s cubic-bezier(0.45, 0, 0.2, 1) forwards;
  }

  .flip-card.flip-prev {
    animation: flipPrev 0.42s cubic-bezier(0.45, 0, 0.2, 1) forwards;
  }

  @keyframes flipNext {
    0%   { transform: rotateY(0deg);   }
    45%  { transform: rotateY(-92deg); }
    100% { transform: rotateY(0deg);   }
  }

  @keyframes flipPrev {
    0%   { transform: rotateY(0deg);  }
    45%  { transform: rotateY(92deg); }
    100% { transform: rotateY(0deg);  }
  }

  /* ===== PAGE IMAGE ===== */
  #page-img {
    display: block;
    max-width: 100%;
    max-height: calc(100vh - 50px - 58px - 40px);
    width: auto;
    height: auto;
    border-radius: 3px;
    box-shadow:
      0 0 0 1px rgba(255,255,255,0.07),
      6px 6px 30px rgba(0,0,0,0.7),
      -2px 2px 12px rgba(0,0,0,0.4);
  }

  /* Mid-flip darkening overlay */
  .flip-shade {
    position: absolute;
    inset: 0;
    border-radius: 3px;
    background: linear-gradient(105deg,
      rgba(0,0,0,0) 20%,
      rgba(20,12,0,0.65) 50%,
      rgba(0,0,0,0) 80%
    );
    pointer-events: none;
    opacity: 0;
    transition: opacity 0.05s;
  }

  .flip-shade.show { opacity: 1; }

  /* Book spine shadow */
  .spine {
    position: absolute;
    top: 2%;
    bottom: 2%;
    left: 50%;
    transform: translateX(-50%);
    width: 4px;
    background: linear-gradient(to right,
      rgba(0,0,0,0.4),
      rgba(255,255,255,0.06) 40%,
      rgba(0,0,0,0.3)
    );
    pointer-events: none;
    display: none;
  }

  /* ===== THUMBNAIL BAR ===== */
  #thumbbar {
    position: fixed;
    bottom: 0; left: 0; right: 0;
    height: 58px;
    background: rgba(8,8,8,0.97);
    border-top: 1px solid rgba(255,255,255,0.07);
    display: flex;
    align-items: center;
    gap: 3px;
    padding: 6px 10px;
    overflow-x: auto;
    scrollbar-width: none;
    z-index: 50;
  }
  #thumbbar::-webkit-scrollbar { display: none; }

  .thumb {
    flex-shrink: 0;
    width: 30px;
    height: 42px;
    border: 1.5px solid rgba(255,255,255,0.08);
    border-radius: 2px;
    cursor: pointer;
    overflow: hidden;
    transition: border-color 0.15s, transform 0.15s;
    position: relative;
  }
  .thumb img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }
  .thumb:hover { border-color: rgba(255,230,0,0.5); transform: scale(1.12); }
  .thumb.active { border-color: #FFE600; box-shadow: 0 0 0 1px #FFE600; }

  .thumb-num {
    position: absolute;
    bottom: 1px;
    right: 2px;
    font-size: 0.4rem;
    color: rgba(255,255,255,0.5);
    line-height: 1;
    text-shadow: 0 0 3px #000;
  }

  /* ===== SWIPE HINT ===== */
  .swipe-hint {
    position: fixed;
    bottom: 66px;
    left: 50%;
    transform: translateX(-50%);
    color: rgba(255,255,255,0.18);
    font-size: 0.68rem;
    letter-spacing: 0.15em;
    white-space: nowrap;
    pointer-events: none;
    animation: hintFade 4s 1.5s ease both;
  }

  @keyframes hintFade {
    0%,100% { opacity: 0; }
    25%,75%  { opacity: 1; }
  }

  /* ===== LOADING ===== */
  #loading {
    position: fixed;
    inset: 0;
    background: #0f0f0f;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 18px;
    z-index: 999;
    transition: opacity 0.4s;
  }

  #loading.hide { opacity: 0; pointer-events: none; }

  .ld-title { color: #FFE600; font-size: 1.5rem; font-weight: 700; letter-spacing: 0.1em; }
  .ld-sub { color: rgba(255,255,255,0.35); font-size: 0.75rem; letter-spacing: 0.1em; }

  .ld-bar-wrap {
    width: 200px; height: 2px;
    background: rgba(255,255,255,0.08);
    border-radius: 1px; overflow: hidden;
  }

  .ld-bar {
    height: 100%;
    background: #FFE600;
    width: 0%;
    border-radius: 1px;
    transition: width 0.2s;
  }

  @media (max-width: 500px) {
    .logo { font-size: 0.8rem; }
    .btn { padding: 5px 10px; font-size: 0.75rem; }
  }
</style>
</head>
<body>

<div id="loading">
  <div class="ld-title">JAMFes 2026</div>
  <div class="ld-bar-wrap"><div class="ld-bar" id="ld-bar"></div></div>
  <div class="ld-sub" id="ld-sub">パンフレットを準備中...</div>
</div>

<header>
  <div class="logo">📋 JAMFes2026 デジタルパンフレット</div>
  <div class="controls">
    <button class="btn" id="btn-first" onclick="gotoPage(1)">|◀</button>
    <button class="btn" id="btn-prev"  onclick="gotoPage(cur-1)">◀ 前</button>
    <input  class="page-input" id="pg-input" type="number" min="1" value="1"
            onchange="gotoPage(parseInt(this.value))">
    <span class="page-total">/ <span id="pg-total">—</span></span>
    <button class="btn" id="btn-next"  onclick="gotoPage(cur+1)">次 ▶</button>
    <button class="btn" id="btn-last"  onclick="gotoPage(PAGES.length)">▶|</button>
    <button class="btn" onclick="toggleFS()">⛶</button>
  </div>
</header>

<div id="viewer">
  <div class="flip-stage" id="stage">
    <div class="flip-card" id="flip-card">
      <img id="page-img" src="" alt="page">
      <div class="flip-shade" id="shade"></div>
    </div>
    <div class="spine"></div>
  </div>
</div>

<div id="thumbbar"></div>
<div class="swipe-hint">← スワイプ or キーボード ← → でページ移動 →</div>

<script>
const PAGES = [
$(echo -e "$PAGES_JS")];

let cur = 1;
let busy = false;

const img     = document.getElementById('page-img');
const card    = document.getElementById('flip-card');
const shade   = document.getElementById('shade');
const pgInput = document.getElementById('pg-input');
const pgTotal = document.getElementById('pg-total');
const ldBar   = document.getElementById('ld-bar');
const ldSub   = document.getElementById('ld-sub');
const loading = document.getElementById('loading');
const thumbbar= document.getElementById('thumbbar');

pgTotal.textContent = PAGES.length;

// ===== PRELOAD =====
let loaded = 0;
const imgs = PAGES.map((src, i) => {
  const im = new Image();
  im.onload = () => {
    loaded++;
    const pct = Math.round(loaded / PAGES.length * 100);
    ldBar.style.width = pct + '%';
    ldSub.textContent = \`読み込み中... \${pct}%\`;
    if (loaded === PAGES.length) {
      setTimeout(() => {
        loading.classList.add('hide');
        setTimeout(() => loading.style.display = 'none', 400);
      }, 200);
    }
    if (i < 5) buildThumb(i); // build first 5 thumbs early
  };
  im.src = src;
  return im;
});

// ===== THUMBNAILS =====
function buildThumb(i) {
  if (thumbbar.querySelector(\`[data-i="\${i}"]\`)) return;
  const div = document.createElement('div');
  div.className = 'thumb' + (i === 0 ? ' active' : '');
  div.dataset.i = i;
  const ti = new Image();
  ti.src = PAGES[i];
  div.appendChild(ti);
  const num = document.createElement('div');
  num.className = 'thumb-num';
  num.textContent = i + 1;
  div.appendChild(num);
  div.onclick = () => gotoPage(i + 1);
  thumbbar.appendChild(div);
}

// Build remaining thumbs lazily
setTimeout(() => {
  for (let i = 5; i < PAGES.length; i++) buildThumb(i);
}, 800);

// ===== GOTO PAGE =====
function gotoPage(n, forceDir) {
  if (busy) return;
  n = Math.max(1, Math.min(PAGES.length, n));
  if (n === cur && !forceDir) return;

  const dir = n > cur ? 'next' : 'prev';
  busy = true;

  // Start flip
  card.classList.add('flip-' + dir);
  shade.classList.add('show');

  // Swap image at mid-flip (~halfway)
  setTimeout(() => {
    img.src = PAGES[n - 1];
    shade.classList.remove('show');
  }, 200);

  // End flip
  setTimeout(() => {
    card.classList.remove('flip-next', 'flip-prev');
    cur = n;
    pgInput.value = n;
    document.getElementById('btn-prev').disabled  = n <= 1;
    document.getElementById('btn-first').disabled = n <= 1;
    document.getElementById('btn-next').disabled  = n >= PAGES.length;
    document.getElementById('btn-last').disabled  = n >= PAGES.length;

    // thumb highlight
    document.querySelectorAll('.thumb').forEach(t => {
      t.classList.toggle('active', parseInt(t.dataset.i) === n - 1);
    });
    const at = thumbbar.querySelector(\`.thumb[data-i="\${n-1}"]\`);
    if (at) at.scrollIntoView({ inline: 'center', behavior: 'smooth' });

    busy = false;
  }, 430);
}

// ===== INIT =====
img.src = PAGES[0];
document.getElementById('btn-prev').disabled  = true;
document.getElementById('btn-first').disabled = true;

// ===== KEYBOARD =====
document.addEventListener('keydown', e => {
  if (e.key === 'ArrowRight' || e.key === 'ArrowDown')  gotoPage(cur + 1);
  if (e.key === 'ArrowLeft'  || e.key === 'ArrowUp')    gotoPage(cur - 1);
  if (e.key === 'Home') gotoPage(1);
  if (e.key === 'End')  gotoPage(PAGES.length);
});

// ===== TOUCH SWIPE =====
let tx = 0;
document.addEventListener('touchstart', e => { tx = e.touches[0].clientX; }, { passive: true });
document.addEventListener('touchend',   e => {
  const dx = e.changedTouches[0].clientX - tx;
  if (Math.abs(dx) > 45) gotoPage(cur + (dx < 0 ? 1 : -1));
}, { passive: true });

// ===== MOUSE CLICK ZONES =====
document.getElementById('viewer').addEventListener('click', e => {
  const x = e.clientX / window.innerWidth;
  if (x < 0.35) gotoPage(cur - 1);
  else if (x > 0.65) gotoPage(cur + 1);
});

// ===== FULLSCREEN =====
function toggleFS() {
  if (!document.fullscreenElement) document.documentElement.requestFullscreen();
  else document.exitFullscreen();
}
</script>
</body>
</html>
HTMLEOF

echo ""
echo "✅ 完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 出力フォルダ: $OUT_DIR/"
echo "   ├── index.html"
echo "   └── pages/ ($TOTAL枚の画像)"
echo ""
echo "🚀 ローカル確認:"
echo "   cd $OUT_DIR && python3 -m http.server 8080"
echo "   → ブラウザで http://localhost:8080 を開く"
echo ""
echo "🌐 デプロイ:"
echo "   GitHub Pages → $OUT_DIR フォルダをリポジトリにpush"
echo "   Vercel       → $OUT_DIR フォルダをドラッグ&ドロップ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
