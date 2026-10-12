"use strict";
const $ = (id) => document.getElementById(id);
const state = {
  token: sessionStorage.getItem("openwalla_api_token") || "",
  data: null,
  settings: null,
  busy: false,
  offset: 0,
  flowRequest: 0,
};
const esc = (value) =>
  String(value ?? "").replace(
    /[&<>'"]/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[
        c
      ],
  );
const number = (value) => new Intl.NumberFormat().format(Number(value || 0));
const bytes = (value) => {
  let n = Number(value || 0),
    i = 0;
  const u = ["B", "KB", "MB", "GB"];
  while (n >= 1024 && i < 3) {
    n /= 1024;
    i++;
  }
  return `${n.toFixed(i ? 1 : 0)} ${u[i]}`;
};
const badge = (up) =>
  `<span class="badge ${up ? "up" : "down"}">${up ? "Connected" : "Offline"}</span>`;
const icons = () => lucide.createIcons();
let successTimer;
function message(id, text) {
  $(id).textContent = text;
  $(id).hidden = !text;
  if (id === "success") {
    clearTimeout(successTimer);
    if (text)
      successTimer = setTimeout(() => ($("success").hidden = true), 6000);
  }
}

$("netify-hours").innerHTML = $("hours").innerHTML;

// Field definitions keep validation and presentation consistent across the pages.
const fields = {
  netify_host: ["Router / Netify host", "text", 1, 253],
  netify_port: ["Stream port", "number", 1, 65535],
  router_lan_ip: [
    "Router LAN IP",
    "text",
    0,
    253,
    "Router web traffic is excluded from storage.",
  ],
  reconnect_seconds: ["Reconnect interval (seconds)", "number", 1, 300],
  excluded_protocols: [
    "Excluded protocols",
    "text",
    0,
    6500,
    "Comma-separated protocol names.",
  ],
  tunnel_host: ["Gateway host", "text", 1, 253],
  tunnel_http_port: ["LuCI forward port", "number", 1, 65535],
  tunnel_ssh_port: ["SSH forward port", "number", 1, 65535],
  ui_username: ["Username", "text", 1, 128],
  ui_password: [
    "New password",
    "password",
    0,
    1024,
    "Leave blank to keep the current password.",
  ],
  password_confirmation: ["Confirm new password", "password", 0, 1024],
  session_hours: ["Session lifetime (hours)", "number", 1, 720],
  auth_max_failures: ["Failed attempt limit", "number", 2, 100],
  auth_window_seconds: ["Tracking window (seconds)", "number", 30, 86400],
  auth_ban_seconds: ["Ban duration (seconds)", "number", 30, 604800],
  api_token: [
    "New API token",
    "password",
    0,
    1024,
    "Leave blank to keep the current token.",
  ],
};
function field(name) {
  const [label, type, min, max, note] = fields[name];
  return `<label>${label}<input name="${name}" type="${type}" ${type === "number" ? `min="${min}" max="${max}" required` : `maxlength="${max}" ${min ? "required" : ""}`} autocomplete="${type === "password" ? "new-password" : name === "ui_username" ? "username" : "off"}">${note ? `<span class="field-note">${note}</span>` : ""}</label>`;
}
const toggle = (name, label) =>
  `<label class="toggle-row full"><span>${label}</span><input name="${name}" type="checkbox" ${name === "login_enabled" ? 'role="switch"' : ""}></label>`;
const save = (label) =>
  `<div class="form-actions"><button class="primary" type="submit"><i data-lucide="save"></i>${label}</button></div>`;
function settingSection(title, note, content) {
  return `<section class="settings-section"><div><h2>${title}</h2><p class="muted small">${note}</p></div><div class="field-grid">${content}</div></section>`;
}
$("netify-form").innerHTML =
  `<div class="field-grid">${["netify_host", "netify_port", "router_lan_ip", "reconnect_seconds", "excluded_protocols"].map(field).join("")}</div>${save("Save stream settings")}`;
$("tunnel-form").innerHTML =
  `<div class="field-grid">${["tunnel_host", "tunnel_http_port", "tunnel_ssh_port"].map(field).join("")}</div>${save("Save gateway settings")}`;
$("settings-form").innerHTML =
  settingSection(
    "Data retention",
    "Expired flows are pruned daily at midnight, in the server's timezone.",
    '<label>Keep flows for<select name="retention_hours" id="retention">' +
      [
        [24, "1 day"],
        [48, "2 days"],
        [72, "3 days"],
        [96, "4 days"],
        [120, "5 days"],
        [168, "7 days"],
        [720, "30 days"],
      ]
        .map(([v, l]) => `<option value="${v}">${l}</option>`)
        .join("") +
      "</select></label>",
  ) +
  settingSection(
    "Dashboard login",
    "Protect access to the web interface.",
    toggle("login_enabled", "Require a username and password") +
      ["ui_username", "ui_password", "password_confirmation", "session_hours"]
        .map(field)
        .join(""),
  ) +
  settingSection(
    "Login protection",
    "Temporary IP bans persist in the data volume.",
    ["auth_max_failures", "auth_window_seconds", "auth_ban_seconds"]
      .map(field)
      .join(""),
  ) +
  settingSection(
    "App API access",
    "Use the same bearer token in the Openwalla mobile app.",
    field("api_token") +
      '<span class="field-note full" id="api-token-state"></span>' +
      toggle("clear_api_token", "Remove the current API token"),
  ) +
  save("Save settings");

async function api(path, options = {}) {
  const response = await fetch(`/api/v1/${path}`, {
    ...options,
    cache: "no-store",
    headers: {
      ...(state.token ? { Authorization: `Bearer ${state.token}` } : {}),
      ...options.headers,
    },
  });
  if (response.status === 401) {
    if (!$("token-dialog").open) $("token-dialog").showModal();
    throw new Error(
      "Authentication required. Sign in or enter your API token.",
    );
  }
  if (!response.ok) {
    const result = await response.json().catch(() => ({}));
    const detail = Array.isArray(result.detail)
      ? result.detail
          .map((item) => `${item.loc.at(-1)}: ${item.msg}`)
          .join("; ")
      : result.detail;
    throw new Error(detail || `Request failed (${response.status})`);
  }
  return response.json();
}
function navigate(path, push = true) {
  const page =
    {
      "/": "dashboard",
      "/netify": "netify",
      "/tunnel": "tunnel",
      "/settings": "settings",
    }[path] || "dashboard";
  if (push && location.pathname !== path) history.pushState({}, "", path);
  document
    .querySelectorAll("[data-view]")
    .forEach((el) => (el.hidden = el.dataset.view !== page));
  document.querySelectorAll("nav [data-page]").forEach((el) => {
    el.classList.toggle("active", el.dataset.page === page);
    if (el.dataset.page === page) el.setAttribute("aria-current", "page");
    else el.removeAttribute("aria-current");
  });
  const title =
    page === "netify" ? "Netify" : page[0].toUpperCase() + page.slice(1);
  $("breadcrumb").textContent = title;
  document.title = `${title} | Openwalla Server`;
  if (page === "netify") loadFlows();
}
document.addEventListener("click", (event) => {
  const link = event.target.closest("a[data-page]");
  if (
    link &&
    !event.metaKey &&
    !event.ctrlKey &&
    !event.shiftKey &&
    event.button === 0
  ) {
    event.preventDefault();
    navigate(link.getAttribute("href"));
    window.scrollTo(0, 0);
  }
});
window.addEventListener("popstate", () => navigate(location.pathname, false));
function connection(name, target, up, icon) {
  return `<div class="connection"><span class="connection-icon"><i data-lucide="${icon}"></i></span><div class="connection-detail"><div class="connection-name">${esc(name)}</div><div class="connection-target">${esc(target)}</div></div>${badge(up)}</div>`;
}
function render() {
  const { collector: c, tunnel: t, flows: f, security: s } = state.data;
  $("server-dot").className = "status-dot up";
  $("server-label").textContent = "Server online";
  $("collector-value").textContent = c.connected ? "Connected" : "Offline";
  $("collector-value").className =
    `metric-value ${c.connected ? "teal" : "rose"}`;
  $("collector-note").textContent = `${c.host}:${c.port}`;
  $("tunnel-value").textContent = t.connected ? "Connected" : "Offline";
  $("tunnel-note").textContent =
    `${Number(t.luci.available) + Number(t.ssh.available)} of 2 services reachable`;
  $("flow-count").textContent = number(f.flow_count);
  $("device-count").textContent = number(f.device_count);
  $("flow-note").textContent =
    `Last ${f.hours} hours · ${state.data.retention_hours}h retention`;
  $("database-size").textContent = `${bytes(f.database_bytes)} on disk`;
  const tunnelConnections =
    connection(
      "Router web interface",
      `${t.host}:${t.luci.port}`,
      t.luci.available,
      "globe",
    ) +
    connection(
      "Router SSH",
      `${t.host}:${t.ssh.port}`,
      t.ssh.available,
      "terminal",
    );
  $("connections").innerHTML =
    connection(
      "Netify stream",
      `${c.host}:${c.port}`,
      c.connected,
      "activity",
    ) + tunnelConnections;
  $("tunnel-connections").innerHTML = tunnelConnections;
  for (const [id, up] of [
    ["netify-badge", c.connected],
    ["tunnel-badge", t.connected],
  ]) {
    $(id).className = `badge ${up ? "up" : "down"}`;
    $(id).textContent = up ? "Connected" : "Offline";
  }
  for (const key of ["received", "stored", "discarded"])
    $(key).textContent = number(c[key]);
  $("last-event").textContent = c.last_event_at
    ? new Date(c.last_event_at * 1000).toLocaleString()
    : "No events yet";
  message("collector-error", c.last_error || "");
  const apps = f.top_applications || [],
    max = Math.max(1, ...apps.map((a) => a.count));
  $("applications-note").textContent = `${number(f.flow_count)} flows`;
  $("applications").innerHTML = apps.length
    ? apps
        .map(
          (a) =>
            `<div class="app-row"><span class="app-name">${esc(a.name)}</span><span class="app-count">${number(a.count)}</span><div class="bar"><span style="width:${Math.max(2, (a.count / max) * 100)}%"></span></div></div>`,
        )
        .join("")
    : '<div class="empty">No application data yet</div>';
  $("security").innerHTML = [
    ["Dashboard login", s.enabled ? "Protected" : "Not enabled"],
    [
      "Failed attempt limit",
      `${s.max_failures} / ${Math.round(s.window_seconds / 60)} min`,
    ],
    ["Session lifetime", `${s.session_hours} hours`],
    ["Banned addresses", number((s.banned || []).length)],
  ]
    .map(
      ([label, value]) =>
        `<div><span>${esc(label)}</span><strong>${esc(value)}</strong></div>`,
    )
    .join("");
  $("bans").innerHTML = s.banned?.length
    ? s.banned
        .map(
          (b) =>
            `<div class="ban-row"><code>${esc(b.address)}</code><span class="muted small">${Math.ceil(b.remaining_seconds / 60)} minutes remaining</span></div>`,
        )
        .join("")
    : '<div class="empty">No banned addresses</div>';
  $("logout-form").hidden = !s.enabled;
  icons();
}
async function loadDashboard() {
  if (state.busy) return;
  state.busy = true;
  $("refresh").disabled = true;
  try {
    state.data = await api(`dashboard?hours=${$("hours").value}`);
    message("error", "");
    render();
    $("last-updated").textContent =
      `Updated ${new Date().toLocaleTimeString()}`;
    if (!state.settings) await loadSettings();
    if (location.pathname === "/netify") await loadFlows();
  } catch (error) {
    message("error", error.message);
    $("server-dot").className = "status-dot down";
    $("server-label").textContent = "Server unavailable";
  } finally {
    state.busy = false;
    $("refresh").disabled = false;
  }
}
async function loadSettings() {
  state.settings = await api("settings");
  populateSettings();
}
function populateSettings() {
  document.querySelectorAll(".settings-form [name]").forEach((input) => {
    if (input.name === "password_confirmation") {
      input.value = "";
      return;
    }
    const value = state.settings[input.name];
    if (input.type === "checkbox") input.checked = Boolean(value);
    else if (input.type === "password") input.value = "";
    else {
      if (
        input.name === "retention_hours" &&
        !Array.from(input.options).some((o) => o.value === String(value))
      )
        input.add(new Option(`${value} hours`, value));
      input.value = Array.isArray(value) ? value.join(", ") : (value ?? "");
    }
  });
  $("api-token-state").textContent = state.settings.api_token_configured
    ? "An API token is configured."
    : "No API token configured.";
}
document.querySelectorAll(".settings-form").forEach((form) =>
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!state.settings) return;
    message("error", "");
    message("success", "");
    if (
      form.id === "settings-form" &&
      form.elements.ui_password.value !==
        form.elements.password_confirmation.value
    ) {
      message("error", "The new passwords do not match.");
      return;
    }
    const payload = { ...state.settings };
    delete payload.api_token_configured;
    form.querySelectorAll("[name]").forEach((input) => {
      if (input.name === "password_confirmation") return;
      payload[input.name] =
        input.type === "checkbox"
          ? input.checked
          : input.type === "number" || input.name === "retention_hours"
            ? Number(input.value)
            : input.name === "excluded_protocols"
              ? input.value
                  .split(",")
                  .map((v) => v.trim())
                  .filter(Boolean)
              : input.value;
    });
    if (payload.api_token && payload.clear_api_token) {
      message(
        "error",
        "Enter a new API token or remove the current one, not both.",
      );
      return;
    }
    const reducesProtection =
      (state.settings.login_enabled && !payload.login_enabled) ||
      (state.settings.api_token_configured && payload.clear_api_token);
    if (
      reducesProtection &&
      !confirm(
        "Apply these access settings? Disabling login or removing a token can allow unauthenticated access.",
      )
    )
      return;
    document
      .querySelectorAll(".settings-form button")
      .forEach((b) => (b.disabled = true));
    try {
      const result = await api("settings", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (payload.clear_api_token) {
        state.token = "";
        sessionStorage.removeItem("openwalla_api_token");
      } else if (payload.api_token) {
        state.token = payload.api_token;
        sessionStorage.setItem("openwalla_api_token", state.token);
      }
      state.settings = result.settings;
      populateSettings();
      if (result.login_required) {
        location.assign("/login");
        return;
      }
      message("success", "Settings saved. Changes are active.");
      await loadDashboard();
    } catch (error) {
      message("error", error.message);
    } finally {
      document
        .querySelectorAll(".settings-form button")
        .forEach((b) => (b.disabled = false));
    }
  }),
);
async function loadFlows() {
  const request = ++state.flowRequest;
  try {
    const query = new URLSearchParams({
      hours: $("hours").value,
      search: $("flow-search").value.trim(),
    });
    const [result, count] = await Promise.all([
      api(`flows?${query}&limit=40&offset=${state.offset}&normalized=true`),
      api(`flows/count?${query}`),
    ]);
    if (request !== state.flowRequest) return;
    const rows = result.items;
    $("flows-total").textContent = `${number(count.count)} matching records`;
    $("flow-range").textContent = count.count
      ? `${number(state.offset + 1)}–${number(Math.min(state.offset + rows.length, count.count))} of ${number(count.count)}`
      : "0 records";
    $("previous").disabled = state.offset === 0;
    $("next").disabled = state.offset + 40 >= count.count;
    $("flow-table").innerHTML = rows.length
      ? `<table><thead><tr><th>Time</th><th>Device</th><th>Destination</th><th>Application</th><th>Protocol</th><th>Port</th><th>Risk</th></tr></thead><tbody>${rows.map((f) => `<tr><td class="muted">${esc(new Date(f.timeinsert * 1000).toLocaleTimeString())}</td><td><div>${esc(f.local_ip || "Unknown")}</div><div class="muted small">${esc(f.local_mac)}</div></td><td class="destination" title="${esc(f.fqdn || f.dest_ip)}">${esc(f.fqdn || f.dest_ip || "Unknown")}</td><td>${esc(f.detected_app_name || "Unknown")}</td><td>${esc(f.detected_protocol_name || "Unknown")}</td><td>${esc(f.dest_port || "—")}</td><td>${number(f.ndpi_risk_score)}</td></tr>`).join("")}</tbody></table>`
      : '<div class="empty">No matching flows in this time range</div>';
  } catch (error) {
    if (request === state.flowRequest) message("error", error.message);
  }
}
let searchTimer;
$("flow-search").addEventListener("input", () => {
  clearTimeout(searchTimer);
  state.offset = 0;
  searchTimer = setTimeout(loadFlows, 250);
});
$("previous").addEventListener("click", () => {
  state.offset = Math.max(0, state.offset - 40);
  loadFlows();
});
$("next").addEventListener("click", () => {
  state.offset += 40;
  loadFlows();
});
$("refresh").addEventListener("click", loadDashboard);
$("hours").addEventListener("change", () => {
  $("netify-hours").value = $("hours").value;
  state.offset = 0;
  loadDashboard();
});
$("netify-hours").addEventListener("change", () => {
  $("hours").value = $("netify-hours").value;
  state.offset = 0;
  loadDashboard();
});
$("token-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  state.token = $("token-input").value.trim();
  sessionStorage.setItem("openwalla_api_token", state.token);
  $("token-dialog").close();
  await loadDashboard();
});
icons();
navigate(location.pathname, false);
loadDashboard();
setInterval(() => {
  if (!document.hidden) loadDashboard();
}, 10000);
