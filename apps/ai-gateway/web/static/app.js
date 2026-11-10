// azpl console : coûts (cost-api) et assistant (chat-api). Aucune bibliothèque, aucun innerHTML
// alimenté par des données : tout le contenu passe par textContent.

const LIVE_EVERY_MS = 30_000;
const BILLED_EVERY_MS = 300_000;
// Tant que le coût facturé n'a jamais été chargé (pod tout juste démarré, Cost Management qui
// limite le débit), on redemande souvent au lieu d'attendre 5 minutes.
const BILLED_RETRY_MS = 30_000;
const $ = (id) => document.getElementById(id);

const eur = (value, small = false) => {
  if (value === null || value === undefined) return "–";
  // Petits montants (0,0068 €/h) en 4 décimales ; zéro et montants usuels en 2.
  const digits = value !== 0 && (small || Math.abs(value) < 0.1) ? 4 : 2;
  return new Intl.NumberFormat("fr-FR", {
    style: "currency", currency: "EUR", minimumFractionDigits: digits, maximumFractionDigits: digits,
  }).format(value);
};
const int = (value) => new Intl.NumberFormat("fr-FR").format(value);
const dayLabel = (iso, opts = { day: "numeric", month: "short" }) =>
  new Intl.DateTimeFormat("fr-FR", opts).format(new Date(`${iso}T00:00:00`));
const seriesColor = (index) =>
  getComputedStyle(document.documentElement).getPropertyValue(`--s${(index % 4) + 1}`).trim();

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === "class") node.className = value;
    else if (key === "style") Object.assign(node.style, value);
    else node.setAttribute(key, value);
  }
  for (const child of children) node.append(child instanceof Node ? child : document.createTextNode(child ?? ""));
  return node;
}

function setFigure(id, text) {
  const node = $(id);
  if (node.textContent !== text) {
    node.textContent = text;
    node.classList.remove("flash");
    void node.offsetWidth; // relance l'animation
    node.classList.add("flash");
  }
}

// ---------- Session et rafraîchissement ----------

let sessionExpired = false;
const freshness = { live: null, stale: false };

async function getJson(url) {
  // La Gateway (OIDC Entra) redirige vers la connexion quand la session expire.
  const response = await fetch(url, { redirect: "manual", headers: { Accept: "application/json" } });
  if (response.type === "opaqueredirect" || response.status === 401) {
    sessionExpired = true;
    throw new Error("session");
  }
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

function renderFreshness() {
  const label = $("refresh-label");
  if (sessionExpired) {
    label.textContent = "Session expirée, rechargez la page";
    label.dataset.stale = "true";
    return;
  }
  if (!freshness.live) return;
  const seconds = Math.max(0, Math.round((Date.now() - freshness.live) / 1000));
  const ago = seconds < 60 ? `${seconds} s` : `${Math.round(seconds / 60)} min`;
  label.textContent = freshness.stale ? `Données en cache, il y a ${ago}` : `Actualisé il y a ${ago}`;
  label.dataset.stale = String(freshness.stale);
}

// ---------- Coût en direct ----------

async function loadLive() {
  try {
    const data = await getJson("/api/cost/live");
    setFigure("kpi-hourly", eur(data.hourly, true));
    setFigure("kpi-monthly", eur(data.monthly));
    $("kpi-hourly-hint").textContent = `${eur(data.daily)} par jour à ce rythme`;

    const status = $("cluster-status");
    status.dataset.state = data.cluster_running ? "up" : "down";
    status.lastElementChild.textContent = data.cluster_running ? "Cluster démarré" : "Cluster arrêté";

    const body = $("live-table").tBodies[0];
    const rows = data.items.map((item) =>
      el("tr", {},
        el("td", {}, item.name),
        el("td", {}, el("span", { class: "tag" }, item.category)),
        el("td", { class: "muted" }, item.detail),
        el("td", { class: "muted" }, item.subscription ?? ""),
        el("td", { class: "num" }, item.hourly === null ? "à l'usage" : eur(item.hourly, true)),
      ));
    body.replaceChildren(...(rows.length ? rows : [el("tr", { class: "empty-row" }, el("td", { colspan: "5" }, "Rien ne tourne."))]));
    $("live-meta").textContent = `${data.items.length} ressources facturées à l'heure`;
    $("usage-note").textContent = `Facturés à l'usage, non inclus : ${data.usage_based.join(", ")}.`;

    freshness.live = Date.now();
    freshness.stale = data.stale;
  } catch (error) {
    freshness.stale = true;
  }
  renderFreshness();
}

// ---------- Coût facturé ----------

let billed = null;

async function loadBilled() {
  try {
    billed = await getJson("/api/cost/billed");
  } catch {
    if (!billed && !sessionExpired) $("kpi-mtd-hint").textContent = "En attente de Cost Management…";
    setTimeout(loadBilled, billed ? BILLED_EVERY_MS : BILLED_RETRY_MS);
    return;
  }
  setTimeout(loadBilled, BILLED_EVERY_MS);
  setFigure("kpi-mtd", eur(billed.month_to_date));
  $("kpi-mtd-hint").textContent = billed.data_through
    ? `Données jusqu'au ${dayLabel(billed.data_through, { day: "numeric", month: "long" })}`
    : "Pas encore de données ce mois";

  const names = billed.subscriptions.map((s) => s.name);
  $("chart-legend").replaceChildren(...names.map((name, i) =>
    el("li", {}, el("i", { style: { background: seriesColor(i) } }), name)));

  fillShareTable("subs-table", billed.subscriptions, (row, i) =>
    el("td", {}, el("i", { class: "swatch", style: { background: seriesColor(i) } }), row.name));
  fillShareTable("services-table", billed.services, (row) => el("td", {}, row.name));
  drawChart();
}

function fillShareTable(id, rows, firstCell) {
  const max = Math.max(...rows.map((r) => r.month_to_date), 0);
  const body = $(id).tBodies[0];
  if (!rows.length) {
    body.replaceChildren(el("tr", { class: "empty-row" }, el("td", { colspan: "3" }, "Aucun coût ce mois.")));
    return;
  }
  body.replaceChildren(...rows.map((row, i) =>
    el("tr", {},
      firstCell(row, i),
      el("td", { class: "num" }, eur(row.month_to_date)),
      el("td", { class: "bar-col" }, el("div", { class: "share" },
        el("span", { style: { width: `${max ? (row.month_to_date / max) * 100 : 0}%` } }))),
    )));
}

// ---------- Graphique : barres empilées par subscription, SVG à la main ----------

const SVG = "http://www.w3.org/2000/svg";
const svg = (tag, attrs = {}) => {
  const node = document.createElementNS(SVG, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  return node;
};

function niceMax(value) {
  if (value <= 0) return 1;
  const magnitude = 10 ** Math.floor(Math.log10(value));
  return [1, 2, 2.5, 5, 10].map((m) => m * magnitude).find((m) => m >= value);
}

function drawChart() {
  if (!billed) return;
  const box = $("chart");
  const width = box.clientWidth;
  const height = box.clientHeight;
  const margin = { top: 8, right: 0, bottom: 22, left: 52 };
  const names = billed.subscriptions.map((s) => s.name);
  const days = billed.daily;
  const totals = days.map((d) => names.reduce((sum, n) => sum + (d.by_subscription[n] || 0), 0));
  const yMax = niceMax(Math.max(...totals));
  const plotW = width - margin.left - margin.right;
  const plotH = height - margin.top - margin.bottom;
  const step = plotW / days.length;
  const barW = Math.max(2, step * 0.62);
  const y = (v) => margin.top + plotH - (v / yMax) * plotH;

  const root = svg("svg", { viewBox: `0 0 ${width} ${height}`, preserveAspectRatio: "none" });
  for (let i = 0; i <= 4; i += 1) {
    const value = (yMax / 4) * i;
    root.append(svg("line", { class: "grid", x1: margin.left, x2: width, y1: y(value), y2: y(value) }));
    const label = svg("text", { class: "axis", x: margin.left - 8, y: y(value) + 4, "text-anchor": "end" });
    label.textContent = value === 0 ? eur(0) : eur(value, yMax < 0.4);
    root.append(label);
  }

  days.forEach((day, i) => {
    const group = svg("g", { class: "day", tabindex: "0" });
    const x = margin.left + i * step + (step - barW) / 2;
    let base = 0;
    names.forEach((name, s) => {
      const value = day.by_subscription[name] || 0;
      if (value <= 0) return;
      group.append(svg("rect", {
        x, width: barW, y: y(base + value), height: Math.max(1, y(base) - y(base + value)), fill: seriesColor(s),
      }));
      base += value;
    });
    group.append(svg("rect", { class: "hit", x: margin.left + i * step, width: step, y: margin.top, height: plotH }));
    group.addEventListener("mouseenter", (event) => showTooltip(event, day, names, totals[i]));
    group.addEventListener("focus", (event) => showTooltip(event, day, names, totals[i]));
    group.addEventListener("mousemove", moveTooltip);
    group.addEventListener("mouseleave", hideTooltip);
    group.addEventListener("blur", hideTooltip);
    root.append(group);

    // Une date toutes les 5 barres (10 sur mobile) ; la dernière seulement si elle a la place.
    const every = width < 560 ? 10 : 5;
    if (i % every === 0 || (i === days.length - 1 && i % every >= every / 2)) {
      const label = svg("text", { class: "axis", x: margin.left + i * step + step / 2, y: height - 4, "text-anchor": "middle" });
      label.textContent = dayLabel(day.date);
      root.append(label);
    }
  });
  box.replaceChildren(root);
}

function showTooltip(event, day, names, total) {
  const tip = $("tooltip");
  tip.replaceChildren(
    el("div", { class: "tt-head" }, dayLabel(day.date, { weekday: "short", day: "numeric", month: "long" })),
    ...names.filter((n) => day.by_subscription[n] > 0).map((n) =>
      el("div", { class: "tt-row" }, el("span", {}, n), el("span", {}, eur(day.by_subscription[n])))),
    el("div", { class: "tt-row" }, el("b", {}, "Total"), el("b", {}, eur(total))),
  );
  tip.hidden = false;
  moveTooltip(event);
}
function moveTooltip(event) {
  const tip = $("tooltip");
  const rect = event.target.getBoundingClientRect?.() ?? { left: 0, top: 0 };
  const x = event.clientX ?? rect.left;
  const yPos = event.clientY ?? rect.top;
  tip.style.left = `${Math.min(x + 14, window.innerWidth - tip.offsetWidth - 8)}px`;
  tip.style.top = `${yPos + 14}px`;
}
function hideTooltip() { $("tooltip").hidden = true; }

new ResizeObserver(() => drawChart()).observe($("chart"));

// ---------- Assistant ----------

const history = [];
const session = { input: 0, output: 0, cost: 0 };

function updateSessionKpi() {
  setFigure("kpi-tokens", int(session.input + session.output));
  $("kpi-tokens-hint").textContent = `${int(session.input)} entrée · ${int(session.output)} sortie · ${eur(session.cost, true)}`;
}

function addTurn(role, text) {
  const list = $("transcript");
  list.querySelector(".empty")?.remove();
  const textNode = el("div", { class: "turn-text" }, text);
  const meta = el("div", { class: "turn-meta" });
  const turn = el("li", { class: `turn ${role}-turn` },
    el("div", { class: "turn-role" }, role === "user" ? "Vous" : $("model-name").textContent),
    textNode, meta);
  list.append(turn);
  list.scrollTop = list.scrollHeight;
  return { turn, textNode, meta };
}

function metaItems(meta, items) {
  meta.replaceChildren(...items.map(([label, value, cls]) =>
    el("span", cls ? { class: cls } : {}, `${label} `, el("b", {}, value))));
}

function parseEvents(buffer) {
  const events = [];
  let index;
  while ((index = buffer.indexOf("\n\n")) >= 0) {
    const block = buffer.slice(0, index);
    buffer = buffer.slice(index + 2);
    let name = "message";
    let data = "";
    for (const line of block.split("\n")) {
      if (line.startsWith("event: ")) name = line.slice(7);
      else if (line.startsWith("data: ")) data += line.slice(6);
    }
    if (data) events.push([name, JSON.parse(data)]);
  }
  return [events, buffer];
}

async function send(prompt) {
  history.push({ role: "user", content: prompt });
  addTurn("user", prompt);
  const { turn, textNode, meta } = addTurn("assistant", "");
  const cursor = el("span", { class: "cursor" });
  textNode.append(cursor);
  metaItems(meta, [["sortie ≈", "0", "pending"]]);
  let answer = "";
  const started = performance.now();

  try {
    const response = await fetch("/api/chat", {
      method: "POST", redirect: "manual",
      headers: { "Content-Type": "application/json", Accept: "text/event-stream" },
      body: JSON.stringify({ messages: history }),
    });
    if (response.type === "opaqueredirect") throw new Error("Session expirée, rechargez la page.");
    if (response.status === 429) throw new Error("Trop de requêtes, réessayez dans un instant.");
    if (!response.ok) throw new Error(`Requête refusée (${response.status}).`);

    const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
    let buffer = "";
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      let events;
      [events, buffer] = parseEvents(buffer + value);
      for (const [name, data] of events) {
        if (name === "meta") {
          $("model-name").textContent = data.deployment;
          turn.querySelector(".turn-role").textContent = data.deployment;
        } else if (name === "delta") {
          answer += data.text;
          cursor.before(data.text);
          metaItems(meta, [["sortie ≈", int(data.output_estimate), "pending"]]);
          $("transcript").scrollTop = $("transcript").scrollHeight;
        } else if (name === "usage") {
          const seconds = ((performance.now() - started) / 1000).toFixed(1);
          metaItems(meta, [
            ["entrée", int(data.input)],
            ...(data.cached_input ? [["cache", int(data.cached_input)]] : []),
            ["sortie", int(data.output)],
            ["coût", data.cost === null ? "n/d" : eur(data.cost, true)],
            ["durée", `${seconds} s`],
          ]);
          session.input += data.input;
          session.output += data.output;
          session.cost += data.cost ?? 0;
          updateSessionKpi();
        } else if (name === "error") {
          throw new Error(data.detail ? `${data.message} : ${data.detail}` : data.message);
        }
      }
    }
    history.push({ role: "assistant", content: answer });
  } catch (error) {
    turn.classList.add("error");
    textNode.textContent = answer ? `${answer}\n\n${error.message}` : error.message;
    history.pop(); // la question sans réponse ne part pas dans l'historique suivant
  } finally {
    cursor.remove();
  }
}

$("composer").addEventListener("submit", async (event) => {
  event.preventDefault();
  const input = $("prompt");
  const prompt = input.value.trim();
  if (!prompt) return;
  input.value = "";
  $("send").disabled = true;
  try {
    await send(prompt);
  } finally {
    $("send").disabled = false;
    input.focus();
  }
});
$("prompt").addEventListener("keydown", (event) => {
  if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) $("composer").requestSubmit();
});
$("reset").addEventListener("click", () => {
  history.length = 0;
  $("transcript").replaceChildren(el("li", { class: "empty" }, "Conversation effacée."));
});

// ---------- Démarrage ----------

getJson("/api/chat/stats").then((stats) => { $("model-name").textContent = stats.deployment; }).catch(() => {});
loadLive();
loadBilled();
setInterval(loadLive, LIVE_EVERY_MS);
setInterval(renderFreshness, 1000);
