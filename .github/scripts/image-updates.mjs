#!/usr/bin/env node
//
// image-updates.mjs [--apply] [--json <file>] [--summary <file>]
//
// NEMTUS: watches Docker Hub for newer tags of the images pinned in presets/shared.yml and, with --apply,
// bumps them everywhere the old reference appears in tracked files (the preset plus the expected-compose
// test fixtures and docs), so the unit suite keeps passing. Used by .github/workflows/image-watch.yml.
//
// Rules (deliberately conservative — the fork keeps upstream's images):
//   symbolServerImage  symbolplatform/symbol-server  gcc-X.Y.Z.W (newest, any)
//   symbolRestImage    symbolplatform/symbol-rest    X.Y.Z within the same major
//   mongoImage         mongo                         X.Y.Z within the same major.minor (a minor/major
//                                                    MongoDB upgrade is a data migration, never automatic)
//   httpsPortalImage   steveltn/https-portal         X.Y.Z within the same major
// The explorer/faucet images are upstream alpha builds without a release line and are not watched.
// A tag must be at least MIN_AGE_DAYS (default 7) old before it is proposed (supply-chain cooldown);
// younger candidates are reported as "pending".
//
// No dependencies: Node.js 24 (global fetch).

import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, appendFileSync } from 'node:fs';

const PRESET = 'presets/shared.yml';
const MIN_AGE_DAYS = Number(process.env.MIN_AGE_DAYS ?? 7);
// Files that record history rather than the current pin; never rewritten.
const EXCLUDE = new Set(['CHANGELOG.md', 'NEMTUS-CHANGELOG.md']);

const RULES = [
    { key: 'symbolServerImage', hub: 'symbolplatform/symbol-server', name: 'gcc-', re: /^gcc-(\d+)\.(\d+)\.(\d+)\.(\d+)$/, keep: 0 },
    { key: 'symbolRestImage', hub: 'symbolplatform/symbol-rest', name: '', re: /^(\d+)\.(\d+)\.(\d+)$/, keep: 1 },
    { key: 'mongoImage', hub: 'library/mongo', name: '', re: /^(\d+)\.(\d+)\.(\d+)$/, keep: 2 },
    { key: 'httpsPortalImage', hub: 'steveltn/https-portal', name: '', re: /^(\d+)\.(\d+)\.(\d+)$/, keep: 1 },
];

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const option = (name) => {
    const i = args.indexOf(name);
    return i >= 0 ? args[i + 1] : undefined;
};

const parts = (rule, tag) => {
    const m = rule.re.exec(tag);
    return m ? m.slice(1).map(Number) : undefined;
};
const compare = (a, b) => {
    for (let i = 0; i < Math.max(a.length, b.length); i++) {
        const d = (a[i] ?? 0) - (b[i] ?? 0);
        if (d) return d;
    }
    return 0;
};

async function hubTags(rule, prefix) {
    const tags = [];
    let url = `https://hub.docker.com/v2/repositories/${rule.hub}/tags?page_size=100&ordering=last_updated&name=${encodeURIComponent(prefix)}`;
    for (let page = 0; url && page < 10; page++) {
        const res = await fetch(url, { headers: { Accept: 'application/json' } });
        if (!res.ok) throw new Error(`Docker Hub ${rule.hub}: HTTP ${res.status}`);
        const body = await res.json();
        for (const t of body.results ?? []) tags.push({ name: t.name, pushed: t.tag_last_pushed ?? t.last_updated });
        url = body.next;
    }
    return tags;
}

async function check(preset) {
    const results = [];
    for (const rule of RULES) {
        const line = new RegExp(`^${rule.key}: *(\\S+)\\s*$`, 'm').exec(preset);
        if (!line) throw new Error(`${PRESET}: ${rule.key} not found`);
        const current = line[1];
        const colon = current.lastIndexOf(':');
        const image = current.slice(0, colon);
        const tag = current.slice(colon + 1);
        const cur = parts(rule, tag);
        if (!cur) {
            results.push({ ...rule, current, status: 'skipped', note: `current tag '${tag}' does not match the watched pattern` });
            continue;
        }
        // Narrow the Hub query to the kept prefix (e.g. mongo "7.0.") — mongo alone has hundreds of tags.
        const keptPrefix = rule.name + cur.slice(0, rule.keep).map((n) => `${n}.`).join('');
        const tags = await hubTags(rule, keptPrefix);
        const now = Date.now();
        let best;
        let pending;
        for (const t of tags) {
            const p = parts(rule, t.name);
            if (!p || compare(p, cur) <= 0) continue;
            if (compare(p.slice(0, rule.keep), cur.slice(0, rule.keep)) !== 0) continue;
            const ageDays = (now - Date.parse(t.pushed)) / 86400000;
            const candidate = { tag: t.name, parts: p, ageDays };
            if (ageDays < MIN_AGE_DAYS) {
                if (!pending || compare(p, pending.parts) > 0) pending = candidate;
            } else if (!best || compare(p, best.parts) > 0) {
                best = candidate;
            }
        }
        const next = best ? `${image}:${best.tag}` : undefined;
        results.push({
            key: rule.key,
            current,
            next,
            pending: pending && (!best || compare(pending.parts, best.parts) > 0) ? `${image}:${pending.tag} (${pending.ageDays.toFixed(1)} days old)` : undefined,
            status: next ? 'update' : 'current',
        });
    }
    return results;
}

function apply(results) {
    const changed = new Set();
    for (const r of results.filter((x) => x.status === 'update')) {
        let files = [];
        try {
            files = execFileSync('git', ['grep', '-l', '-F', r.current], { encoding: 'utf8' }).split('\n').filter(Boolean);
        } catch {
            files = [];
        }
        for (const f of files.filter((f) => !EXCLUDE.has(f))) {
            const text = readFileSync(f, 'utf8');
            // Replace whole image references only (the next char must not continue the tag).
            const re = new RegExp(`${r.current.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![\\w.-])`, 'g');
            const updated = text.replace(re, r.next);
            if (updated !== text) {
                writeFileSync(f, updated);
                changed.add(f);
            }
        }
    }
    return [...changed].sort();
}

function markdown(results, changed) {
    const rows = results.map((r) => `| \`${r.key}\` | \`${r.current}\` | ${r.next ? `\`${r.next}\`` : '—'} | ${r.pending ?? r.note ?? ''} |`);
    const out = [
        `| Preset key | Current | Proposed (≥ ${MIN_AGE_DAYS} days old) | Pending / note |`,
        '|---|---|---|---|',
        ...rows,
    ];
    if (changed?.length) out.push('', `Files updated: ${changed.map((f) => `\`${f}\``).join(', ')}`);
    return out.join('\n');
}

const preset = readFileSync(PRESET, 'utf8');
const results = await check(preset);
const changed = flag('--apply') ? apply(results) : [];
const md = markdown(results, changed);
console.log(md);
if (option('--json')) writeFileSync(option('--json'), JSON.stringify({ results, changed }, null, 2));
if (option('--summary')) appendFileSync(option('--summary'), `${md}\n`);
