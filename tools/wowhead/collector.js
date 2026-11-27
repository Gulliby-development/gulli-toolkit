// Weekly Wowhead collector, run in a browser tab on www.wowhead.com (Wowhead refuses servers).
// The scheduled run loads this file from the repository (raw.githubusercontent.com allows it), starts
// gulliWH(<the [url, kind, id] list of `weekly.py tasks`>) without await,
// polls gulliWHState() and reads the result back with gulliWHPart(). Each page keeps only what
// weekly.py merge needs, so the results stay small (localStorage holds a few MB).
// Page text is untrusted: it is only cut and parsed as JSON, never run.
(() => {
  const PAUSE = 4000, STORE = "gulliWH", KEEP = 12, BODY = 1000;
  const load = () => { try { return JSON.parse(localStorage.getItem(STORE) || "{}"); } catch (e) { return {}; } };
  const save = (s) => localStorage.setItem(STORE, JSON.stringify(s));
  // The JSON array that starts at the first "[" after `from`, brackets matched outside strings.
  const arrayAt = (t, from) => {
    let i = t.indexOf("[", from), depth = 0, q = null;
    if (i < 0) return null;
    for (let j = i; j < t.length; j++) {
      const c = t[j];
      if (q) { if (c === "\\") j++; else if (c === q) q = null; }
      else if (c === '"' || c === "'") q = c;
      else if (c === "[") depth++;
      else if (c === "]" && --depth === 0) return t.slice(i, j + 1);
    }
    return null;
  };
  const listview = (t, id) => {
    const at = t.indexOf("id: '" + id + "'");
    if (at < 0) return null;
    const d = t.indexOf("data:", at);
    if (d < 0 || d - at > 3000) return null;
    try { return JSON.parse(arrayAt(t, d)); } catch (e) { return null; }
  };
  const blocked = (t) => /Human Verification|challenge-platform|cf-chl-/i.test(t) && !/lv_comments0|g_npcs|setupScalingRewards/.test(t);
  const plain = (h) => { const d = document.createElement("div"); d.innerHTML = h.replace(/<(script|style|table)[^>]*>[^]*?<\/\1>/gi, "").replace(/<br\s*\/?>/gi, "\n"); return d.textContent.trim(); };
  // A quest page as { own, name, objective, description, xp, comments }: own is false when Wowhead
  // sent another page (an unknown quest goes to the quest list), xp the experience at the quest's level.
  const quest = (t, id) => {
    const own = new RegExp('rel="canonical"[^>]*/quest=' + id + "(?!\\d)").test(t);
    const doc = new DOMParser().parseFromString(t, "text/html");
    const text = doc.querySelector(".text");
    const inner = text ? text.innerHTML : "";
    const m = inner.match(/<h1[^>]*>([^]*?)<\/h1>([^]*?)(?=<table|<script|<h2|$)/);
    const d = inner.match(/<h2[^>]*>\s*Description\s*<\/h2>([^]*?)(?=<h2|$)/i);
    let xp = null;
    const sx = t.match(/setupScalingRewards\((\{.*?\})\);<\/script>/);
    if (sx) { try { const lv = (JSON.parse(sx[1]).xp || {}).levels || {}; const k = Object.keys(lv).map(Number); xp = k.length ? lv[Math.max(...k)] : 0; } catch (e) { xp = null; } }
    else if (own) xp = 0;
    const at = t.search(/\blv_comments0\s*=\s*\[/);
    let list = [];
    try { list = at >= 0 ? JSON.parse(arrayAt(t, at) || "[]") : []; } catch (e) { list = null; }
    if (list) list = list.filter((c) => c && typeof c === "object").sort((a, b) => (b.rating || 0) - (a.rating || 0)).slice(0, KEEP)
      .map((c) => ({ user: c.user || "", date: String(c.date || "").slice(0, 10), rating: c.rating || 0, body: String(c.body || "").slice(0, BODY) }));
    return { own, name: m ? plain(m[1]) : "", objective: m ? plain(m[2]) : "", description: d ? plain(d[1]) : "", xp, comments: list };
  };
  const npc = (t) => {
    const g = t.match(/"classification"\s*:\s*(\d+)/);
    const disp = t.match(/data-mv-display-id="?(\d+)/) || t.match(/displayId\s*=\s*(\d+)/);
    const name = (t.match(/<title>([^<]*?) - NPC/) || [])[1] || "";
    const abilities = (listview(t, "abilities") || []).map((a) => [a.id, a.name]);
    const drops = (listview(t, "drops") || []).map((d) => ({
      id: d.id, name: d.name, quality: d.quality, class: d.classs, subclass: d.subclass,
      slot: d.slot, ilvl: d.level, count: d.count, outof: d.outof,
    }));
    if (!name && !disp) return null;
    return { name, classification: g ? +g[1] : null, displayId: disp ? +disp[1] : 0, abilities, drops };
  };
  window.gulliWH = async (tasks) => {
    const s = load();
    s.state = { total: tasks.length, done: 0, failed: 0, stopped: "", started: Date.now() };
    save(s);
    for (let task of tasks) {
      if (Array.isArray(task)) {
        const url = task[0].replace(/^~/, "https://www.wowhead.com");   // weekly.py tasks writes ~ for the site
        task = { key: url, url, kind: task[1], id: task[2] };
      }
      if (s.pages && s.pages[task.key]) { s.state.done++; continue; }
      let t = "";
      try { t = await fetch(task.url, { credentials: "include" }).then((r) => r.text()); }
      catch (e) { s.state.failed++; save(s); await new Promise((r) => setTimeout(r, PAUSE)); continue; }
      if (blocked(t)) { s.state.stopped = "verification at " + task.url; save(s); return s.state; }
      const got = task.kind === "npc" ? npc(t) : quest(t, task.id);
      (s.pages = s.pages || {})[task.key] = got;
      s.state.done++;
      save(s);
      await new Promise((r) => setTimeout(r, PAUSE));
    }
    s.state.finished = Date.now();
    save(s);
    return s.state;
  };
  // Started without await, so the javascript call returns at once; poll state with gulliWHState().
  window.gulliWHState = () => load().state;
  window.gulliWHPart = (from, size) => { const all = JSON.stringify(load().pages || {}); return { length: all.length, part: all.slice(from, from + size) }; };
  window.gulliWHClear = () => localStorage.removeItem(STORE);
})();
