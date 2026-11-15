// Panespace site: the tiling demo, the latest release, and the header hairline.
(() => {
  "use strict";

  // Header: hairline once the page scrolls.
  const nav = document.querySelector("[data-nav]");
  const onScroll = () => nav && nav.toggleAttribute("data-scrolled", window.scrollY > 4);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // Latest release: point every download at the current zip and show its version.
  fetch("https://api.github.com/repos/panelab/panespace/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
    .then((r) => (r.ok ? r.json() : null))
    .then((rel) => {
      if (!rel || !rel.tag_name) return;
      const version = rel.tag_name.replace(/^v/, "");
      const zip = (rel.assets || []).find((a) => /^Panespace-.*\.zip$/.test(a.name));
      if (zip) {
        document.querySelectorAll("[data-download]").forEach((a) => (a.href = zip.browser_download_url));
        document.querySelectorAll("[data-zip-name]").forEach((el) => (el.textContent = zip.name));
      }
      document.querySelectorAll("[data-version]").forEach((el) => (el.textContent = "Version " + version));
      const link = document.querySelector("[data-release-link]");
      if (link && rel.html_url) link.href = rel.html_url;
      const text = document.querySelector("[data-release-text]");
      if (text && !text.textContent.includes(version)) text.textContent = "Version " + version + " is out";
    })
    .catch(() => {});

  // GitHub stars in the header (left as "Star" if the API doesn't answer).
  fetch("https://api.github.com/repos/panelab/panespace", { headers: { Accept: "application/vnd.github+json" } })
    .then((r) => (r.ok ? r.json() : null))
    .then((repo) => {
      const n = repo && repo.stargazers_count;
      if (typeof n !== "number" || n < 1) return;
      const el = document.querySelector("[data-stars]");
      if (el) el.textContent = new Intl.NumberFormat("en", { notation: "compact" }).format(n);
    })
    .catch(() => {});

  // ---- Demo ---------------------------------------------------------------------------------
  const demo = document.querySelector("[data-demo]");
  if (!demo) return;
  const strip = demo.querySelector("[data-strip]");
  const indicator = demo.querySelectorAll("[data-ws]");
  const frontApp = demo.querySelector("[data-front-app]");
  const announce = demo.querySelector("[data-announce]");
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");

  const KINDS = {
    term: {
      app: "Terminal", title: "zsh: ~/panespace",
      body: `<p><span class="t-acc">~/panespace</span> <span class="t-dim">main</span></p><p>$ panespace msg workspace 2</p><p class="t-grn">[{"success": true}]</p><p><span class="t-acc">~/panespace</span> <span class="t-dim">main</span></p><p>$ panespace msg layout tabbed</p><p class="t-grn">[{"success": true}]</p><p><span class="t-acc">~/panespace</span> <span class="t-dim">main</span></p><p>$ panespace check-config</p><p class="t-dim">~/.config/panespace/config:</p><p class="t-dim">68 bindings in 2 mode(s), 3 rules</p><p>$ <span class="t-dim">▍</span></p>`,
    },
    editor: {
      app: "Editor", title: "LayoutEngine.swift",
      body: `<p><span class="t-acc">func</span> <span class="t-blu">frames</span>(for ws: Workspace,</p><p>            on m: Monitor) -> [ID: CGRect] {</p><p>    <span class="t-acc">var</span> out: [ID: CGRect] = [:]</p><p>    <span class="t-acc">let</span> area = m.visibleFrame</p><p>        .insetBy(dx: gaps.outer,</p><p>                 dy: gaps.outer)</p><p>    place(ws.root, in: area, &amp;out)</p><p>    <span class="t-acc">if let</span> fs = ws.fullscreen {</p><p>        out[fs.id] = area</p><p>    }</p><p>    <span class="t-acc">return</span> out</p><p>}</p>`,
    },
    docs: {
      app: "Browser", title: "Configuration: Panespace",
      body: `<div class="win-body doc"><h4>Configuration</h4><p>Panespace writes a commented default config to <code>~/.config/panespace/config</code> on first run.</p><p>Edit it from the menu bar, then reload with <b>$mod+Shift+C</b>.</p><h5>Gaps</h5><p><code>gaps inner 8</code> puts 8 points between windows. <code>smart_gaps on</code> drops them when a workspace has one window.</p></div>`,
      raw: true,
    },
    files: {
      app: "Finder", title: "panespace",
      body: `<div class="win-body files"><p><span>Sources</span><span>Folder</span></p><p><span>Tests</span><span>Folder</span></p><p><span>site</span><span>Folder</span></p><p><span>Makefile</span><span>Document</span></p><p><span>Package.swift</span><span>Swift file</span></p><p><span>README.md</span><span>Markdown</span></p></div>`,
      raw: true,
    },
    notes: {
      app: "Notes", title: "Release checklist",
      body: `<div class="win-body doc"><h4>Release checklist</h4><p>Bump CFBundleVersion in both plists</p><p>Merge to main, wait for CI</p><p>Tag v0.3.0 and push the tag</p><p class="t-dim">Check the appcast after the release job</p></div>`,
      raw: true,
    },
    tests: {
      app: "Terminal", title: "zsh: make test",
      body: `<p>$ make test</p><p class="t-dim">Building for debugging...</p><p class="t-dim">Test Suite 'All tests' started</p><p>Executed <span class="t-yel">104</span> tests, with</p><p><span class="t-grn">0 failures</span> in 15.2 seconds</p><p>$ <span class="t-dim">▍</span></p>`,
    },
  };
  const ORDER = ["term", "editor", "docs", "files", "notes", "tests"];
  const MAX = 6;

  let nextId = 1;
  const mk = (kind) => ({ id: nextId++, kind, el: null });
  const state = {
    ws: [
      { wins: [mk("term"), mk("editor"), mk("docs")], focus: 0, zoom: false },
      { wins: [mk("notes"), mk("files")], focus: 0, zoom: false },
      { wins: [], focus: 0, zoom: false },
    ],
    current: 0,
    spawn: 0,
  };

  // The ws containers, one per workspace, side by side in the strip.
  const wsEls = state.ws.map((_, i) => {
    const el = document.createElement("div");
    el.className = "ws";
    el.dataset.index = String(i);
    strip.appendChild(el);
    return el;
  });

  let size = { w: 0, h: 0 };
  const GAP = () => (size.w < 520 ? 6 : 8);

  // Dwindle, like auto_split: the first window takes half of the space along its longer side, the rest share the other half.
  function layout(rect, n) {
    if (n === 0) return [];
    if (n === 1) return [rect];
    const g = GAP();
    if (rect.w >= rect.h) {
      const w = Math.round((rect.w - g) / 2);
      return [{ x: rect.x, y: rect.y, w, h: rect.h }, ...layout({ x: rect.x + w + g, y: rect.y, w: rect.w - w - g, h: rect.h }, n - 1)];
    }
    const h = Math.round((rect.h - g) / 2);
    return [{ x: rect.x, y: rect.y, w: rect.w, h }, ...layout({ x: rect.x, y: rect.y + h + g, w: rect.w, h: rect.h - h - g }, n - 1)];
  }

  function frames(ws) {
    const g = GAP();
    const area = { x: g, y: g, w: size.w - 2 * g, h: size.h - 2 * g };
    if (ws.zoom && ws.wins[ws.focus]) return ws.wins.map((_, i) => (i === ws.focus ? area : null));
    return layout(area, ws.wins.length);
  }

  function makeWin(w) {
    const k = KINDS[w.kind];
    const el = document.createElement("div");
    el.className = "win";
    el.innerHTML =
      `<div class="win-bar"><span class="lights"><i></i><i></i><i></i></span><span class="win-title">${k.title}</span></div>` +
      (k.raw ? k.body : `<div class="win-body">${k.body}</div>`);
    return el;
  }

  function render(entering) {
    state.ws.forEach((ws, i) => {
      const host = wsEls[i];
      const rects = frames(ws);
      ws.wins.forEach((w, j) => {
        if (!w.el) {
          w.el = makeWin(w);
          host.appendChild(w.el);
        }
        const r = rects[j];
        const el = w.el;
        el.classList.toggle("focused", j === ws.focus && i === state.current);
        if (!r) {
          el.style.opacity = "0";
          el.style.pointerEvents = "none";
          return;
        }
        el.style.opacity = "";
        el.style.width = r.w + "px";
        el.style.height = r.h + "px";
        const t = `translate(${r.x}px, ${r.y}px)`;
        if (entering === w && !reduced.matches) {
          el.style.transition = "none";
          el.style.transform = t + " scale(0.96)";
          el.classList.add("entering");
          el.getBoundingClientRect();
          el.style.transition = "";
        }
        el.style.transform = t;
        el.classList.remove("entering");
      });
      let empty = host.querySelector(".ws-empty");
      if (!ws.wins.length && !empty) {
        empty = document.createElement("div");
        empty.className = "ws-empty";
        empty.innerHTML = `<span>Workspace ${i + 1} is empty</span><span>Press <kbd>⏎</kbd> to open a window</span>`;
        host.appendChild(empty);
      } else if (ws.wins.length && empty) {
        empty.remove();
      }
    });
    strip.style.transform = `translateX(${-100 * state.current}%)`;
    indicator.forEach((el, i) => {
      el.classList.toggle("on", i === state.current);
      el.classList.toggle("empty", !state.ws[i].wins.length && i !== state.current);
    });
    const cur = state.ws[state.current];
    const f = cur.wins[cur.focus];
    if (frontApp) frontApp.textContent = f ? KINDS[f.kind].app : "Finder";
  }

  function say(text) {
    if (announce) announce.textContent = text;
  }

  const cur = () => state.ws[state.current];

  const commands = {
    new() {
      const ws = cur();
      if (ws.wins.length >= MAX) return say("This demo keeps it to six windows per workspace");
      const w = mk(ORDER[(state.spawn++ + 3) % ORDER.length]);
      const at = ws.wins.length ? ws.focus + 1 : 0;
      ws.wins.splice(at, 0, w);
      ws.focus = at;
      ws.zoom = false;
      render(w);
      say(`Opened ${KINDS[w.kind].app}. ${ws.wins.length} windows.`);
    },
    close() {
      const ws = cur();
      const w = ws.wins[ws.focus];
      if (!w) return;
      ws.wins.splice(ws.focus, 1);
      ws.focus = Math.max(0, Math.min(ws.focus, ws.wins.length - 1));
      ws.zoom = false;
      const el = w.el;
      el.style.opacity = "0";
      el.style.transform += " scale(0.96)";
      setTimeout(() => el.remove(), reduced.matches ? 0 : 180);
      render();
      say(`Closed ${KINDS[w.kind].app}. ${ws.wins.length} windows left.`);
    },
    zoom() {
      const ws = cur();
      if (!ws.wins.length) return;
      ws.zoom = !ws.zoom;
      render();
      say(ws.zoom ? "Zoomed" : "Back in its tile");
    },
    workspace(i) {
      if (i < 0 || i >= state.ws.length || i === state.current) return;
      state.current = i;
      render();
      say(`Workspace ${i + 1}, ${cur().wins.length} windows`);
    },
    focus(dir) {
      const ws = cur();
      if (ws.wins.length < 2 || ws.zoom) return;
      const rects = frames(ws);
      const from = rects[ws.focus];
      const cx = from.x + from.w / 2, cy = from.y + from.h / 2;
      let best = -1, bestScore = Infinity;
      rects.forEach((r, i) => {
        if (i === ws.focus || !r) return;
        const x = r.x + r.w / 2, y = r.y + r.h / 2;
        const dx = x - cx, dy = y - cy;
        const ok =
          (dir === "left" && r.x + r.w <= from.x + 1) || (dir === "right" && r.x >= from.x + from.w - 1) ||
          (dir === "up" && r.y + r.h <= from.y + 1) || (dir === "down" && r.y >= from.y + from.h - 1);
        if (!ok) return;
        const along = dir === "left" || dir === "right" ? Math.abs(dx) : Math.abs(dy);
        const across = dir === "left" || dir === "right" ? Math.abs(dy) : Math.abs(dx);
        const score = along + across * 2;
        if (score < bestScore) { bestScore = score; best = i; }
      });
      if (best < 0) return;
      ws.focus = best;
      render();
      say(`Focused ${KINDS[ws.wins[best].kind].app}`);
    },
    focusNext() {
      const ws = cur();
      if (ws.wins.length < 2 || ws.zoom) return;
      ws.focus = (ws.focus + 1) % ws.wins.length;
      render();
      say(`Focused ${KINDS[ws.wins[ws.focus].kind].app}`);
    },
  };

  const KEYMAP = {
    Enter: () => commands.new(), n: () => commands.new(),
    h: () => commands.focus("left"), ArrowLeft: () => commands.focus("left"),
    l: () => commands.focus("right"), ArrowRight: () => commands.focus("right"),
    k: () => commands.focus("up"), ArrowUp: () => commands.focus("up"),
    j: () => commands.focus("down"), ArrowDown: () => commands.focus("down"),
    1: () => commands.workspace(0), 2: () => commands.workspace(1), 3: () => commands.workspace(2),
    f: () => commands.zoom(), q: () => commands.close(), x: () => commands.close(), Backspace: () => commands.close(),
  };

  demo.addEventListener("keydown", (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const fn = KEYMAP[e.key] || KEYMAP[e.key.toLowerCase()];
    if (!fn) return;
    e.preventDefault();
    fn();
  });

  // Clicking a window focuses it, like the real thing.
  strip.addEventListener("pointerdown", (e) => {
    const winEl = e.target.closest(".win");
    const ws = cur();
    const i = ws.wins.findIndex((w) => w.el === winEl);
    if (i >= 0 && i !== ws.focus && !ws.zoom) { ws.focus = i; render(); }
  });

  document.querySelectorAll("[data-cmd]").forEach((b) =>
    b.addEventListener("click", () => {
      const c = b.dataset.cmd;
      if (c === "new") commands.new();
      else if (c === "close") commands.close();
      else if (c === "zoom") commands.zoom();
      else if (c === "focus-next") commands.focusNext();
      else if (c === "ws-next") commands.workspace((state.current + 1) % state.ws.length);
    }),
  );

  const measure = () => {
    const r = strip.getBoundingClientRect();
    size = { w: r.width, h: r.height };
    // No glide on resize: only user actions move windows.
    demo.querySelectorAll(".win").forEach((el) => (el.style.transition = "none"));
    render();
    requestAnimationFrame(() => demo.querySelectorAll(".win").forEach((el) => (el.style.transition = "")));
  };
  new ResizeObserver(measure).observe(strip);
  measure();
})();
