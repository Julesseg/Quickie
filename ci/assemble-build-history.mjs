// Maintains the published build-history site in place.
//
// Given the current PR's freshly-built .ipa, this upserts that PR's slot into a
// `builds.json` manifest (one slot per PR, keyed by PR number), prunes to the N
// most-recently-built PRs, copies the .ipa into builds/pr-<n>/, and regenerates
// every HTML page and OTA manifest. It mutates SITE_DIR in place; the caller
// force-pushes the result to the build-history branch and serves it via Pages.
//
// Inputs come from the environment (see release.yml > deploy job):
//   SITE_DIR        directory holding the published site (may be empty on first run)
//   PR_NUMBER       the PR that triggered this build
//   PR_TITLE        the PR title — the human label for the slot
//   COMMIT_SHA      full head SHA (only the first 7 chars are shown)
//   IPA_PATH        path to the freshly-built quickie.ipa
//   PAGES_BASE_URL  e.g. https://julesseg.github.io/Quickie (no trailing slash)
//   REPO_URL        e.g. https://github.com/julesseg/Quickie (no trailing slash)
//   RETENTION       how many PR slots to keep (default 5)

import { promises as fs } from "node:fs";
import path from "node:path";

const env = (name, fallback) => {
  const v = process.env[name];
  if (v === undefined || v === "") {
    if (fallback !== undefined) return fallback;
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
};

const SITE_DIR = env("SITE_DIR");
const PR_NUMBER = Number(env("PR_NUMBER"));
const PR_TITLE = env("PR_TITLE");
const SHORT_SHA = env("COMMIT_SHA").slice(0, 7);
const IPA_PATH = env("IPA_PATH");
const BASE = env("PAGES_BASE_URL").replace(/\/$/, "");
const REPO_URL = env("REPO_URL", "https://github.com/julesseg/Quickie").replace(/\/$/, "");
const RETENTION = Number(env("RETENTION", "5"));
const NOW = new Date();

const BUNDLE_ID = "com.quickie.app";

const escapeHtml = (s) =>
  String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

// Same escaping serves XML text nodes in the plist.
const escapeXml = escapeHtml;

// "2026-06-16 09:11 UTC" — stable, sortable-looking, timezone-explicit.
const formatTime = (iso) => {
  const d = new Date(iso);
  const p = (n) => String(n).padStart(2, "0");
  return (
    `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())} ` +
    `${p(d.getUTCHours())}:${p(d.getUTCMinutes())} UTC`
  );
};

const slotUrl = (pr) => `${BASE}/builds/pr-${pr}`;
const ipaUrl = (pr) => `${slotUrl(pr)}/quickie.ipa`;
const manifestUrl = (pr) => `${slotUrl(pr)}/manifest.plist`;
const installLink = (pr) =>
  `itms-services://?action=download-manifest&amp;url=${manifestUrl(pr)}`;
const prUrl = (pr) => `${REPO_URL}/pull/${pr}`;

// A build's identity for the "have I installed this?" mark: PR number + commit,
// so a fresh build of the same PR reads as new again even though the slot is reused.
const buildId = (slot) => `${slot.pr}-${slot.sha}`;

// Client-side progressive enhancement, embedded in every page. Both features need
// the browser because the page is generated once and served statically:
//   - "have I installed this build?" lives in localStorage (scoped to the
//     julesseg.github.io origin, so it survives every rebuild). Tapping Install
//     marks the build seen; an un-installed build shows a NEW badge, an installed
//     one dims and shows "installed". Tapping a badge toggles it by hand.
//   - the relative "x ago" next to each build time, recomputed against now.
const ENHANCE_SCRIPT = `<script>
(function () {
  var KEY = "quickie-seen-builds";
  var load = function () {
    try { return new Set(JSON.parse(localStorage.getItem(KEY) || "[]")); }
    catch (e) { return new Set(); }
  };
  var save = function (set) {
    try { localStorage.setItem(KEY, JSON.stringify(Array.from(set))); } catch (e) {}
  };
  var seen = load();
  var apply = function (el) {
    var id = el.getAttribute("data-build-id");
    var isSeen = seen.has(id);
    el.classList.toggle("seen", isSeen);
    el.classList.toggle("unseen", !isSeen);
  };
  document.querySelectorAll("[data-build-id]").forEach(function (el) {
    apply(el);
    var id = el.getAttribute("data-build-id");
    var btn = el.querySelector("a.btn");
    if (btn) btn.addEventListener("click", function () { seen.add(id); save(seen); apply(el); });
    el.querySelectorAll(".new-badge, .seen-tag").forEach(function (t) {
      t.addEventListener("click", function (e) {
        e.preventDefault();
        if (seen.has(id)) seen.delete(id); else seen.add(id);
        save(seen); apply(el);
      });
    });
  });
  var ago = function (iso) {
    var s = Math.round((Date.now() - new Date(iso).getTime()) / 1000);
    if (s < 10) return "just now";
    if (s < 60) return s + "s ago";
    var m = Math.round(s / 60);
    if (m < 60) return m + "m ago";
    var h = Math.round(m / 60);
    if (h < 24) return h + "h ago";
    return Math.round(h / 24) + "d ago";
  };
  document.querySelectorAll("[data-time]").forEach(function (el) {
    el.textContent = ago(el.getAttribute("data-time"));
  });
})();
</script>`;

const manifestPlist = (slot) => `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>items</key>
    <array>
        <dict>
            <key>assets</key>
            <array>
                <dict>
                    <key>kind</key>
                    <string>software-package</string>
                    <key>url</key>
                    <string>${ipaUrl(slot.pr)}</string>
                </dict>
            </array>
            <key>metadata</key>
            <dict>
                <key>bundle-identifier</key>
                <string>${BUNDLE_ID}</string>
                <key>bundle-version</key>
                <string>${escapeXml(slot.sha)}</string>
                <key>kind</key>
                <string>software</string>
                <key>title</key>
                <string>${escapeXml(slot.title)}</string>
            </dict>
        </dict>
    </array>
</dict>
</plist>
`;

const pageHead = (title) => `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)}</title>
  <style>
    body { font-family: -apple-system, sans-serif; max-width: 520px; margin: 48px auto; padding: 0 24px; color: #1c1c1e; }
    h1 { font-size: 1.5rem; margin-bottom: 4px; }
    .sub { color: #666; margin: 0 0 32px; font-size: 0.95rem; }
    a.btn { display: inline-block; background: #007AFF; color: #fff; text-decoration: none;
            padding: 12px 28px; border-radius: 12px; font-size: 1.05rem; font-weight: 600; }
    ul.builds { list-style: none; padding: 0; margin: 0; }
    li.build { border: 1px solid #e2e2e6; border-radius: 14px; padding: 16px 18px; margin-bottom: 14px; }
    li.build.latest { border-color: #007AFF; }
    .title { font-weight: 600; font-size: 1.05rem; margin-bottom: 2px; }
    .meta { color: #888; font-size: 0.82rem; margin-bottom: 12px; }
    .badge { display: inline-block; background: #007AFF; color: #fff; font-size: 0.7rem;
             font-weight: 600; padding: 2px 8px; border-radius: 999px; margin-left: 8px; vertical-align: middle; }
    .hint { color: #999; font-size: 0.8rem; margin-top: 32px; text-align: center; }
    a.back { display: inline-block; color: #007AFF; text-decoration: none; font-size: 0.95rem;
             font-weight: 600; margin-bottom: 24px; }
    a.back:hover { text-decoration: underline; }
    a.pr-link { color: #007AFF; text-decoration: none; font-size: 0.85rem; font-weight: 600; }
    a.pr-link:hover { text-decoration: underline; }
    .slot-pr { margin-top: 18px; }
    .build .pr-link { margin-left: 14px; }
    .new-badge { display: none; background: #FF3B30; color: #fff; font-size: 0.7rem; font-weight: 700;
                 padding: 2px 8px; border-radius: 999px; margin-left: 8px; vertical-align: middle; cursor: pointer; }
    .seen-tag { display: none; color: #34C759; font-size: 0.78rem; font-weight: 600; margin-left: 8px; cursor: pointer; }
    .time-pill { display: inline-block; background: #5856D6; color: #fff; font-size: 0.7rem; font-weight: 700;
                 padding: 2px 8px; border-radius: 999px; margin-left: 8px; vertical-align: middle; }
    .time-pill:empty { display: none; }
    [data-build-id].unseen .new-badge { display: inline-block; }
    [data-build-id].seen .seen-tag { display: inline-block; }
    li.build.seen { opacity: 0.5; }
    @media (prefers-color-scheme: dark) {
      body { color: #f2f2f7; background: #000; }
      li.build { border-color: #2c2c2e; }
      .sub, .meta { color: #98989f; }
    }
  </style>
</head>
<body>`;

const slotPage = (slot, isLatest) => `${pageHead(slot.title)}
  <a class="back" href="${BASE}/">← All builds</a>
  <main data-build-id="${buildId(slot)}">
    <h1>${escapeHtml(slot.title)}${isLatest ? '<span class="badge">latest</span>' : ""}<span class="new-badge">NEW</span><span class="time-pill" data-time="${slot.time}"></span><span class="seen-tag">✓ installed</span></h1>
    <p class="sub">PR #${slot.pr} · ${escapeHtml(slot.sha)} · ${escapeHtml(formatTime(slot.time))}</p>
    <a class="btn" href="${installLink(slot.pr)}">Install</a>
    <p class="slot-pr"><a class="pr-link" href="${prUrl(slot.pr)}">View PR #${slot.pr} on GitHub →</a></p>
    <p class="hint">Open this page in Safari on your iPhone, then tap Install.</p>
  </main>
${ENHANCE_SCRIPT}
</body>
</html>
`;

const rootPage = (slots) => `${pageHead("Quickie — Builds")}
  <h1>Quickie</h1>
  <p class="sub">The ${slots.length} most recent build${slots.length === 1 ? "" : "s"}, newest first.</p>
  <ul class="builds">
${slots
  .map(
    (slot, i) => `    <li class="build${i === 0 ? " latest" : ""}" data-build-id="${buildId(slot)}">
      <div class="title">${escapeHtml(slot.title)}${i === 0 ? '<span class="badge">latest</span>' : ""}<span class="new-badge">NEW</span><span class="time-pill" data-time="${slot.time}"></span><span class="seen-tag">✓ installed</span></div>
      <div class="meta">PR #${slot.pr} · ${escapeHtml(slot.sha)} · ${escapeHtml(formatTime(slot.time))}</div>
      <a class="btn" href="${installLink(slot.pr)}">Install</a>
      <a class="pr-link" href="${prUrl(slot.pr)}">View PR #${slot.pr} →</a>
    </li>`,
  )
  .join("\n")}
  </ul>
  <p class="hint">Open this page in Safari on your iPhone, then tap Install on the build you want.</p>
${ENHANCE_SCRIPT}
</body>
</html>
`;

async function readManifest() {
  try {
    const raw = await fs.readFile(path.join(SITE_DIR, "builds.json"), "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

async function main() {
  const existing = await readManifest();

  // Upsert this PR's slot at the front (newest first); a rebuild of an older PR
  // refreshes its slot and moves it back to the top.
  const slot = { pr: PR_NUMBER, title: PR_TITLE, sha: SHORT_SHA, time: NOW.toISOString() };
  const withoutThis = existing.filter((s) => Number(s.pr) !== PR_NUMBER);
  const kept = [slot, ...withoutThis].slice(0, RETENTION);
  const keptPrs = new Set(kept.map((s) => Number(s.pr)));

  // Drop folders for any PR no longer retained (pruned, or orphaned from a past run).
  const buildsDir = path.join(SITE_DIR, "builds");
  let entries = [];
  try {
    entries = await fs.readdir(buildsDir);
  } catch {
    /* builds/ doesn't exist yet */
  }
  for (const name of entries) {
    const m = /^pr-(\d+)$/.exec(name);
    if (!m || !keptPrs.has(Number(m[1]))) {
      await fs.rm(path.join(buildsDir, name), { recursive: true, force: true });
    }
  }

  // Write this PR's slot: copy the fresh .ipa, regenerate its manifest + install page.
  const slotDir = path.join(buildsDir, `pr-${PR_NUMBER}`);
  await fs.mkdir(slotDir, { recursive: true });
  await fs.copyFile(IPA_PATH, path.join(slotDir, "quickie.ipa"));
  await fs.writeFile(path.join(slotDir, "manifest.plist"), manifestPlist(slot));

  // Regenerate every retained slot's install page (the "latest" badge moves).
  for (let i = 0; i < kept.length; i++) {
    const s = kept[i];
    await fs.writeFile(
      path.join(buildsDir, `pr-${s.pr}`, "index.html"),
      slotPage(s, i === 0),
    );
  }

  await fs.writeFile(path.join(SITE_DIR, "index.html"), rootPage(kept));
  await fs.writeFile(path.join(SITE_DIR, "builds.json"), JSON.stringify(kept, null, 2) + "\n");

  console.log(
    `Published PR #${PR_NUMBER} (${SHORT_SHA}). Retained slots: ${kept.map((s) => `pr-${s.pr}`).join(", ")}`,
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
