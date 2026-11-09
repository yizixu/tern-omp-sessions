import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { open, readdir, stat } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
export const PREFIX_BYTES = 32 * 1024;
const disappeared = error => error?.code === 'ENOENT' || error?.code === 'ENOTDIR';
const text = value => typeof value === 'string' ? value : '';
const compact = value => text(value).replace(/\s+/gu, ' ').trim();
export function pathKey(value, platform = process.platform) {
  const normalized = (platform === 'win32' ? path.win32 : path).resolve(value);
  return platform === 'win32' ? normalized.toLowerCase() : normalized;
}

export async function inspectTern(tern) {
  const { stdout } = await execFileAsync(tern, ['inspect', '--json'], {
    encoding: 'utf8', timeout: 10_000, maxBuffer: 16 * 1024 * 1024,
    windowsHide: true,
  });
  return JSON.parse(stdout);
}

export async function agentRoot(env = process.env, home = homedir()) {
  if (env.OMP_AGENT_DIR) {
    try {
      if ((await stat(env.OMP_AGENT_DIR)).isDirectory()) return env.OMP_AGENT_DIR;
    } catch (error) {
      if (!disappeared(error)) throw error;
    }
  }
  return path.join(home, '.omp', 'agent');
}

function userText(message) {
  if (typeof message.content === 'string') return message.content;
  if (!Array.isArray(message.content)) return '';
  return message.content.filter(part => part?.type === 'text').map(part => text(part.text)).join('\n');
}

export function parsePrefix(source, { truncated = false } = {}) {
  const lines = source.replace(/^\uFEFF/u, '').split('\n');
  if (truncated) lines.pop(); // A cut JSONL record is not a malformed record.
  let header;
  let titleSlot;
  let preview = '';
  let sawUser = false;
  const warnings = [];
  for (let index = 0; index < lines.length; index++) {
    if (!lines[index].trim()) continue;
    let record;
    try { record = JSON.parse(lines[index]); }
    catch { warnings.push(`Malformed JSON at line ${index + 1}`); continue; }
    if (!record || typeof record !== 'object') {
      warnings.push(`Invalid record at line ${index + 1}`);
      continue;
    }
    if (index === 0 && record.type === 'title') titleSlot = text(record.title);
    if (!header && record.type === 'session') header = record;
    if (!sawUser && record.type === 'message' && record.message?.role === 'user') {
      sawUser = true;
      preview = compact(userText(record.message)).slice(0, 280);
    }
  }
  if (!header) warnings.push('Missing session header in prefix');
  return {
    id: text(header?.id), cwd: text(header?.cwd),
    title: compact(titleSlot === undefined ? header?.title : titleSlot),
    preview, warnings,
  };
}

export async function readSession(file) {
  let handle;
  try {
    handle = await open(file, 'r');
    const info = await handle.stat();
    const buffer = Buffer.alloc(PREFIX_BYTES);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);
    return { ...parsePrefix(buffer.subarray(0, bytesRead).toString('utf8'), {
      truncated: info.size > bytesRead,
    }), modified: info.mtimeMs / 1000 };
  } finally {
    await handle?.close();
  }
}

export function liveSessions(inspection, platform = process.platform) {
  const locations = new Map();
  for (const session of inspection.sessions ?? []) {
    for (const tab of session.tabs ?? []) {
      const location = [session.name ?? session.id,
        tab.name ?? tab.number ?? tab.id].filter(value => value !== undefined && value !== '').join(' / ');
      for (const block of tab.blocks ?? []) {
        if (typeof block.id === 'number') locations.set(block.id, location);
      }
    }
  }
  const result = new Map();
  for (const pane of inspection.panes ?? []) {
    if (!text(pane.omp_session_file) || typeof pane.pane !== 'number'
      || (pane.exited !== null && pane.exited !== undefined)) continue;
    const file = pane.omp_session_file;
    const key = pathKey(file, platform);
    let entry = result.get(key);
    if (!entry) result.set(key, entry = { path: file, cwd: text(pane.cwd), panes: [] });
    entry.panes.push({ pane: pane.pane, title: text(pane.title), working: pane.working === true,
      location: locations.get(pane.pane) ?? '' });
  }
  return result;
}

export async function savedSessionFiles(root, warnings = []) {
  const sessions = path.join(root, 'sessions');
  let buckets;
  try { buckets = await readdir(sessions, { withFileTypes: true }); }
  catch (error) {
    if (!disappeared(error)) warnings.push(`Cannot read ${sessions}: ${error.message}`);
    return [];
  }
  const files = [];
  for (const bucket of buckets) {
    if (!bucket.isDirectory()) continue;
    const directory = path.join(sessions, bucket.name);
    let entries;
    try { entries = await readdir(directory, { withFileTypes: true }); }
    catch (error) {
      if (!disappeared(error)) warnings.push(`Cannot read ${directory}: ${error.message}`);
      continue;
    }
    for (const entry of entries) {
      if (entry.isFile() && entry.name.endsWith('.jsonl')) files.push(path.join(directory, entry.name));
    }
  }
  return files;
}

export async function scanSessions({ tern, mode = 'list', root, inspection,
  platform = process.platform } = {}) {
  if (mode !== 'list' && mode !== 'live') throw new Error(`Unknown command: ${mode}`);
  const snapshot = inspection ?? await inspectTern(tern);
  const active = liveSessions(snapshot, platform);
  const warnings = [];
  const files = new Map([...active].map(([key, entry]) => [key, entry.path]));
  if (mode === 'list') {
    for (const file of await savedSessionFiles(root ?? await agentRoot(), warnings)) {
      const key = pathKey(file, platform);
      if (!files.has(key)) files.set(key, file);
    }
  }
  const pending = [...files];
  const sessions = [];
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(8, pending.length) }, async () => {
    while (next < pending.length) {
      const [key, file] = pending[next++];
      const live = active.get(key);
      let metadata;
      try { metadata = await readSession(file); }
      catch (error) {
        if (!disappeared(error)) warnings.push(`Cannot read ${file}: ${error.message}`);
        if (!live) continue;
        metadata = { id: '', cwd: '', title: '', preview: '', modified: 0, warnings: [] };
      }
      warnings.push(...metadata.warnings.map(warning => `${file}: ${warning}`));
      if (!live && !metadata.title && !metadata.preview) continue;
      sessions.push({ id: metadata.id || path.basename(file, '.jsonl'), path: file,
        cwd: metadata.cwd || live?.cwd || '',
        title: metadata.title || metadata.preview || live?.panes[0]?.title || path.basename(file, '.jsonl'),
        modified: metadata.modified, preview: metadata.preview, panes: live?.panes ?? [] });
    }
  }));
  sessions.sort((a, b) => Number(b.panes.length > 0) - Number(a.panes.length > 0)
    || b.modified - a.modified || a.path.localeCompare(b.path));
  return { sessions, warnings, updated: Date.now() / 1000 };
}

export async function main(args = process.argv.slice(2)) {
  const [mode, flag, tern, ...extra] = args;
  if (!['list', 'live'].includes(mode) || flag !== '--tern' || !tern || extra.length) {
    throw new Error('Usage: sessions.mjs <list|live> --tern <executable>');
  }
  process.stdout.write(`${JSON.stringify(await scanSessions({ mode, tern }))}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
