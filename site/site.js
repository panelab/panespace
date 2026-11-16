// Panespace site: header hairline, latest release, star count, and the tiling demo.
(() => {
  "use strict";

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
      if (zip) document.querySelectorAll("[data-download]").forEach((a) => (a.href = zip.browser_download_url));
      document.querySelectorAll("[data-version]").forEach((el) => (el.textContent = "Public beta " + version));
    })
    .catch(() => {});

  fetch("https://api.github.com/repos/panelab/panespace", { headers: { Accept: "application/vnd.github+json" } })
    .then((r) => (r.ok ? r.json() : null))
    .then((repo) => {
      const n = repo && repo.stargazers_count;
      const el = document.querySelector("[data-stars]");
      if (typeof n === "number" && n > 0 && el) el.textContent = new Intl.NumberFormat("en", { notation: "compact" }).format(n) + (n === 1 ? " star" : " stars");
    })
    .catch(() => {});

  // ---- Demo ---------------------------------------------------------------------------------
  const demo = document.querySelector("[data-demo]");
  if (!demo) return;
  const screen = demo.querySelector("[data-screen]");
  const indicator = [...demo.querySelectorAll("[data-ws-indicator] span")];
  const frontApp = demo.querySelector("[data-front-app]");
  const announce = demo.querySelector("[data-announce]");
  const keycast = demo.querySelector("[data-keycast]");
  const keycastKeys = demo.querySelector("[data-keycast-keys]");
  const keycastLabel = demo.querySelector("[data-keycast-label]");
  const playBtn = document.querySelector("[data-play]");
  const playLabel = document.querySelector("[data-play-label]");
  const hint = document.querySelector("[data-hint]");
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");

  const svg = {
    folder: '<svg class="folder" viewBox="0 0 16 16"><path d="M1.75 4.25a1 1 0 0 1 1-1h3.1l1.4 1.5h6a1 1 0 0 1 1 1v6.5a1 1 0 0 1-1 1H2.75a1 1 0 0 1-1-1Z" fill="currentColor"/></svg>',
    file: '<svg class="file" viewBox="0 0 16 16"><path d="M4 1.75h5.25L12.5 5v9.25H4Z" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/><path d="M9 1.75V5.3h3.5" fill="none" stroke="currentColor" stroke-width="1.2"/></svg>',
    clock: '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="5.5" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M8 5v3.2l2 1.3" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>',
    apps: '<svg viewBox="0 0 16 16"><path d="M3 3h4v4H3zM9 3h4v4H9zM3 9h4v4H3zM9 9h4v4H9z" fill="none" stroke="currentColor" stroke-width="1.3"/></svg>',
    desk: '<svg viewBox="0 0 16 16"><rect x="2" y="3" width="12" height="8.5" rx="1" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M6 13.5h4" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>',
    down: '<svg viewBox="0 0 16 16"><circle cx="8" cy="8" r="5.5" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M8 5v5.5M5.75 8.5 8 10.75l2.25-2.25" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    back: '<svg viewBox="0 0 16 16"><path d="M10 3 5 8l5 5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    fwd: '<svg viewBox="0 0 16 16"><path d="m6 3 5 5-5 5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    lock: '<svg viewBox="0 0 16 16"><rect x="3.5" y="7" width="9" height="6.5" rx="1.25" fill="currentColor"/><path d="M5.5 7V5.25a2.5 2.5 0 0 1 5 0V7" fill="none" stroke="currentColor" stroke-width="1.4"/></svg>',
  };
  const bar = (title) => `<div class="bar"><span class="lights"><i></i><i></i><i></i></span><span class="title">${title}</span></div>`;
  const code = (lines) =>
    `<div class="code">${lines.map((l, i) => `<span class="ln">${i + 1}</span><span>${l || " "}</span>`).join("")}</div>`;

  const KINDS = {
    term: {
      app: "Terminal",
      html: () =>
        bar("panespace · zsh") +
        `<div class="body"><span class="c-grn">~/panespace</span> <span class="c-dim">main</span>
$ panespace msg workspace 2
<span class="c-dim">[{"success": true}]</span>
<span class="c-grn">~/panespace</span> <span class="c-dim">main</span>
$ panespace msg layout tabbed
<span class="c-dim">[{"success": true}]</span>
<span class="c-grn">~/panespace</span> <span class="c-dim">main</span>
$ <span class="c-cur"></span></div>`,
    },
    editor: {
      app: "Xcode",
      html: () =>
        bar("panespace · LayoutEngine.swift") +
        `<div class="tabs"><span class="on">LayoutEngine.swift</span><span>Workspace.swift</span><span>Config.swift</span></div>` +
        `<div class="body">${code([
          `<span class="s-kw">func</span> <span class="s-fn">frames</span>(<span class="s-kw">for</span> ws: <span class="s-ty">Workspace</span>) -> [<span class="s-ty">ID</span>: <span class="s-ty">CGRect</span>] {`,
          `    <span class="s-kw">var</span> out: [<span class="s-ty">ID</span>: <span class="s-ty">CGRect</span>] = [:]`,
          `    <span class="s-kw">let</span> area = monitor.visibleFrame`,
          `        .<span class="s-fn">insetBy</span>(dx: gaps.outer, dy: gaps.outer)`,
          ``,
          `    <span class="s-com">// Dwindle: split along the longer side.</span>`,
          `    <span class="s-fn">place</span>(ws.root, in: area, &amp;out)`,
          `    <span class="s-kw">if let</span> fs = ws.fullscreen {`,
          `        out[fs.id] = area`,
          `    }`,
          `    <span class="s-kw">return</span> out`,
          `}`,
        ])}</div>`,
    },
    web: {
      app: "Safari",
      html: () =>
        `<div class="bar"><span class="lights"><i></i><i></i><i></i></span><span class="nav-btns">${svg.back}${svg.fwd}</span><span class="url">${svg.lock}<span>github.com/panelab/panespace</span></span></div>` +
        `<div class="body"><div class="page"><div class="row"><span class="pill">Swift</span><span class="pill">macOS 13+</span></div><h4>Panespace</h4><p>A tiling window manager for macOS in the spirit of i3. Windows tile as they open, and your i3 config mostly just works.</p><div class="pre">git clone https://github.com/panelab/panespace
cd panespace &amp;&amp; make install</div><p>On first launch, allow Accessibility when macOS asks.</p></div></div>`,
    },
    finder: {
      app: "Finder",
      html: () => {
        const rows = [
          ["folder", "Sources", "Today", "Folder"],
          ["folder", "Tests", "Today", "Folder"],
          ["folder", "site", "Yesterday", "Folder"],
          ["file", "Makefile", "Yesterday", "Text"],
          ["file", "Package.swift", "12 Nov", "Swift"],
          ["file", "README.md", "12 Nov", "Markdown"],
        ];
        return (
          bar("panespace") +
          `<div class="body split-win"><div class="side"><h5>Favourites</h5><p>${svg.clock}Recents</p><p>${svg.apps}Applications</p><p>${svg.desk}Desktop</p><p class="on">${svg.folder}panespace</p><p>${svg.down}Downloads</p></div>` +
          `<div class="main rows"><p class="head"><span>Name</span><span class="meta2 date2">Modified</span><span class="meta2">Kind</span></p>` +
          rows.map(([ic, n, d, k]) => `<p><span class="name">${svg[ic]}${n}</span><span class="meta2 date2">${d}</span><span class="meta2">${k}</span></p>`).join("") +
          `</div></div>`
        );
      },
    },
    notes: {
      app: "Notes",
      html: () =>
        bar("Notes") +
        `<div class="body split-win"><div class="side notes-side"><p class="on">Release checklist<small>Today</small></p><p>Interview notes<small>Friday</small></p><p>Config ideas<small>10 Nov</small></p></div>` +
        `<div class="main note"><span class="date">16 November 2026 at 09:30</span><h4>Release checklist</h4>` +
        `<p><span class="box done"></span><span class="done-t">Bump the build number</span></p>` +
        `<p><span class="box done"></span><span class="done-t">Merge to main, wait for CI</span></p>` +
        `<p><span class="box"></span>Tag v0.3.0 and push the tag</p>` +
        `<p><span class="box"></span>Check the appcast</p></div></div>`,
    },
    tests: {
      app: "Terminal",
      html: () =>
        bar("panespace · make test") +
        `<div class="body">$ make test
<span class="c-dim">Building for debugging...</span>
<span class="c-dim">Test Suite 'All tests' started</span>
Test Suite 'All tests' <span class="c-grn">passed</span>
$ <span class="c-cur"></span></div>`,
    },
  };
  const SPAWN = ["finder", "notes", "tests", "web", "editor", "term"];
  const MAX = 5;

  let nextId = 1;
  let spawnIndex = 0;
  const mk = (kind) => ({ id: nextId++, kind, el: null });
  const freshState = () => ({
    ws: [
      { wins: [mk("term"), mk("editor"), mk("web")], focus: 0, zoom: false },
      { wins: [mk("notes"), mk("finder")], focus: 0, zoom: false },
      { wins: [], focus: 0, zoom: false },
    ],
    current: 0,
  });
  let state = freshState();

  const wsEls = state.ws.map((_, i) => {
    const el = document.createElement("div");
    el.className = "ws";
    el.hidden = i !== 0;
    screen.appendChild(el);
    return el;
  });

  let size = { w: 0, h: 0 };
  const GAP = () => (size.w < 520 ? 6 : 10);

  // Dwindle, like auto_split: the first window takes half the space along the longer side.
  function layout(rect, n) {
    if (n === 0) return [];
    if (n === 1) return [rect];
    const g = GAP();
    if (rect.w >= rect.h * 0.9) {
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
    const el = document.createElement("div");
    el.className = "win k-" + w.kind;
    el.innerHTML = KINDS[w.kind].html();
    return el;
  }

  const cur = () => state.ws[state.current];
  const say = (text) => (announce.textContent = text);

  function render(entering) {
    state.ws.forEach((ws, i) => {
      const host = wsEls[i];
      // Workspaces switch instantly, like the app: no slide.
      host.hidden = i !== state.current;
      const rects = frames(ws);
      ws.wins.forEach((w, j) => {
        if (!w.el) {
          w.el = makeWin(w);
          host.appendChild(w.el);
        }
        const r = rects[j];
        const el = w.el;
        el.classList.toggle("focused", j === ws.focus);
        el.style.zIndex = j === ws.focus ? "2" : "1";
        if (!r) {
          el.style.opacity = "0";
          return;
        }
        el.style.opacity = "";
        el.style.width = r.w + "px";
        el.style.height = r.h + "px";
        const t = `translate(${r.x}px, ${r.y}px)`;
        if (entering === w && !reduced.matches) {
          el.style.transition = "none";
          el.style.transform = t + " scale(0.96)";
          el.style.opacity = "0";
          el.getBoundingClientRect();
          el.style.transition = "";
          el.style.opacity = "";
        }
        el.style.transform = t;
      });
      let empty = host.querySelector(".ws-empty");
      if (!ws.wins.length && !empty) {
        empty = document.createElement("div");
        empty.className = "ws-empty";
        empty.innerHTML = `<b>Workspace ${i + 1} is empty</b><span>Press Return to open a window</span>`;
        host.appendChild(empty);
      } else if (ws.wins.length && empty) {
        empty.remove();
      }
    });
    indicator.forEach((el, i) => {
      el.classList.toggle("on", i === state.current);
      el.classList.toggle("empty", !state.ws[i].wins.length && i !== state.current);
    });
    const ws = cur();
    const f = ws.wins[ws.focus];
    frontApp.textContent = f ? KINDS[f.kind].app : "Finder";
  }

  // The keys behind each command, shown at the bottom of the screen. $mod is ⌃⌥ by default.
  const G = (n) => `<kbd><span class="g g-${n}"></span></kbd>`;
  const MOD = G("ctrl") + G("opt");
  const KEY = (s) => `<kbd>${s}</kbd>`;
  let castTimer = 0;
  function cast(keys, label) {
    keycastKeys.innerHTML = keys;
    keycastLabel.textContent = label;
    keycast.classList.add("show");
    clearTimeout(castTimer);
    castTimer = setTimeout(() => keycast.classList.remove("show"), 1300);
  }

  const DIRS = { left: "H", down: "J", up: "K", right: "L" };

  // The neighbour in a direction, judged by window centres.
  function neighbour(dir) {
    const ws = cur();
    if (ws.wins.length < 2 || ws.zoom) return -1;
    const rects = frames(ws);
    const from = rects[ws.focus];
    const cx = from.x + from.w / 2, cy = from.y + from.h / 2;
    let best = -1, bestScore = Infinity;
    rects.forEach((r, i) => {
      if (i === ws.focus || !r) return;
      const ok =
        (dir === "left" && r.x + r.w <= from.x + 1) || (dir === "right" && r.x >= from.x + from.w - 1) ||
        (dir === "up" && r.y + r.h <= from.y + 1) || (dir === "down" && r.y >= from.y + from.h - 1);
      if (!ok) return;
      const dx = Math.abs(r.x + r.w / 2 - cx), dy = Math.abs(r.y + r.h / 2 - cy);
      const score = dir === "left" || dir === "right" ? dx + dy * 2 : dy + dx * 2;
      if (score < bestScore) { bestScore = score; best = i; }
    });
    return best;
  }

  const commands = {
    new() {
      const ws = cur();
      if (ws.wins.length >= MAX) return say("The demo keeps it to five windows per workspace");
      const w = mk(SPAWN[spawnIndex++ % SPAWN.length]);
      const at = ws.wins.length ? ws.focus + 1 : 0;
      ws.wins.splice(at, 0, w);
      ws.focus = at;
      ws.zoom = false;
      render(w);
      cast(MOD + G("ret"), "New window");
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
      setTimeout(() => el.remove(), reduced.matches ? 0 : 160);
      render();
      cast(MOD + G("shift") + KEY("Q"), "Close window");
      say(`Closed ${KINDS[w.kind].app}. ${ws.wins.length} windows left.`);
    },
    zoom() {
      const ws = cur();
      if (!ws.wins.length) return;
      ws.zoom = !ws.zoom;
      render();
      cast(MOD + KEY("F"), ws.zoom ? "Full screen" : "Back to its tile");
      say(ws.zoom ? "Full screen" : "Back in its tile");
    },
    workspace(i) {
      if (i < 0 || i >= state.ws.length || i === state.current) return;
      state.current = i;
      render();
      cast(MOD + KEY(String(i + 1)), `Workspace ${i + 1}`);
      say(`Workspace ${i + 1}, ${cur().wins.length} windows`);
    },
    focus(dir) {
      const ws = cur();
      const i = neighbour(dir);
      if (i < 0) return;
      ws.focus = i;
      render();
      cast(MOD + KEY(DIRS[dir]), `Focus ${dir}`);
      say(`Focused ${KINDS[ws.wins[i].kind].app}`);
    },
    move(dir) {
      const ws = cur();
      const i = neighbour(dir);
      if (i < 0) return;
      [ws.wins[ws.focus], ws.wins[i]] = [ws.wins[i], ws.wins[ws.focus]];
      ws.focus = i;
      render();
      cast(MOD + G("shift") + KEY(DIRS[dir]), `Move ${dir}`);
      say(`Moved ${KINDS[ws.wins[i].kind].app} ${dir}`);
    },
    focusNext() {
      const ws = cur();
      if (ws.wins.length < 2 || ws.zoom) return;
      ws.focus = (ws.focus + 1) % ws.wins.length;
      render();
      cast(MOD + KEY("L"), "Focus next");
      say(`Focused ${KINDS[ws.wins[ws.focus].kind].app}`);
    },
  };

  // ---- The tour: plays until the visitor takes over --------------------------------------------
  const TOUR = [
    () => commands.focus("right"),
    () => commands.focus("down"),
    () => commands.new(),
    () => commands.move("left"),
    () => commands.zoom(),
    () => commands.zoom(),
    () => commands.workspace(1),
    () => commands.new(),
    () => commands.workspace(0),
    () => commands.close(),
    () => commands.focus("left"),
  ];
  let step = 0;
  let tourTimer = 0;
  let playing = false;
  let visible = false;
  let userPaused = reduced.matches;

  function reset() {
    state.ws.forEach((ws) => ws.wins.forEach((w) => w.el && w.el.remove()));
    wsEls.forEach((el) => el.replaceChildren());
    nextId = 1;
    spawnIndex = 0;
    state = freshState();
    render();
  }

  function tick() {
    if (step >= TOUR.length) {
      step = 0;
      reset();
    } else {
      TOUR[step++]();
    }
    tourTimer = setTimeout(tick, 1600);
  }

  function syncTour() {
    const shouldPlay = !userPaused && visible && !document.hidden;
    if (shouldPlay === playing) return;
    playing = shouldPlay;
    clearTimeout(tourTimer);
    if (playing) tourTimer = setTimeout(tick, 800);
  }

  const HINT_TOUR = "Playing a short tour. Click the desktop to drive it.";
  const HINT_YOU = "Your turn: click the desktop, then use the keys.";
  function setPaused(paused) {
    userPaused = paused;
    playBtn.setAttribute("aria-pressed", String(paused));
    playLabel.textContent = paused ? "Play tour" : "Pause tour";
    playBtn.querySelector("[data-icon-pause]").hidden = paused;
    playBtn.querySelector("[data-icon-play]").hidden = !paused;
    hint.textContent = paused ? HINT_YOU : HINT_TOUR;
    syncTour();
  }

  playBtn.addEventListener("click", () => setPaused(!userPaused));
  new IntersectionObserver((entries) => {
    visible = entries[entries.length - 1].isIntersecting;
    syncTour();
  }, { threshold: 0.35 }).observe(demo);
  document.addEventListener("visibilitychange", syncTour);

  // Any input from the visitor stops the tour until they press Play.
  const takeOver = () => { if (!userPaused) setPaused(true); };

  const KEYMAP = {
    Enter: () => commands.new(), n: () => commands.new(),
    h: () => commands.focus("left"), ArrowLeft: () => commands.focus("left"),
    l: () => commands.focus("right"), ArrowRight: () => commands.focus("right"),
    k: () => commands.focus("up"), ArrowUp: () => commands.focus("up"),
    j: () => commands.focus("down"), ArrowDown: () => commands.focus("down"),
    H: () => commands.move("left"), L: () => commands.move("right"),
    K: () => commands.move("up"), J: () => commands.move("down"),
    1: () => commands.workspace(0), 2: () => commands.workspace(1), 3: () => commands.workspace(2),
    f: () => commands.zoom(), F: () => commands.zoom(), q: () => commands.close(), Q: () => commands.close(),
  };
  const SHIFT_ARROWS = { ArrowLeft: "H", ArrowRight: "L", ArrowUp: "K", ArrowDown: "J" };

  demo.addEventListener("keydown", (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const key = e.shiftKey && SHIFT_ARROWS[e.key] ? SHIFT_ARROWS[e.key] : e.key;
    const fn = KEYMAP[key];
    if (!fn) return;
    e.preventDefault();
    takeOver();
    fn();
  });

  // Clicking a window focuses it, like the real thing.
  screen.addEventListener("pointerdown", (e) => {
    takeOver();
    const winEl = e.target.closest(".win");
    const ws = cur();
    const i = ws.wins.findIndex((w) => w.el === winEl);
    if (i >= 0 && i !== ws.focus && !ws.zoom) {
      ws.focus = i;
      render();
    }
  });
  demo.addEventListener("pointerdown", () => demo.focus({ preventScroll: true }));

  document.querySelectorAll("[data-cmd]").forEach((b) =>
    b.addEventListener("click", () => {
      takeOver();
      const c = b.dataset.cmd;
      if (c === "new") commands.new();
      else if (c === "close") commands.close();
      else if (c === "zoom") commands.zoom();
      else if (c === "focus-next") commands.focusNext();
      else if (c === "ws-next") commands.workspace((state.current + 1) % state.ws.length);
    }),
  );

  const measure = () => {
    const r = screen.getBoundingClientRect();
    if (!r.width) return;
    size = { w: r.width, h: r.height };
    // No glide on resize: only commands move windows.
    demo.querySelectorAll(".win").forEach((el) => (el.style.transition = "none"));
    render();
    requestAnimationFrame(() => demo.querySelectorAll(".win").forEach((el) => (el.style.transition = "")));
  };
  new ResizeObserver(measure).observe(screen);
  measure();
  setPaused(userPaused);
})();
