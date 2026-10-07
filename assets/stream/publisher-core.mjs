/** Deterministic, literal-text GitHub Contents API posting. No service or LLM. */
export const CONTENTS_API = 'https://api.github.com/repos/frontierkodiak/clbswrs.co-v2/contents/';
export const BRANCH = 'gh-pages';

export function encodeUtf8(text) {
  return btoa(Array.from(new TextEncoder().encode(text), byte =>
    String.fromCharCode(byte)).join(''));
}

export function decodePayload(encoded) {
  const bytes = Uint8Array.from(atob(encoded), char => char.charCodeAt(0));
  const payload = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
  if (payload.version !== 1 || !['quotation', 'link'].includes(payload.kind)) {
    throw new Error('Unsupported shared post. Nothing was published.');
  }
  return payload;
}

export function canAutoPublish(payload, suppliedKey, storedKey) {
  return payload?.kind === 'quotation' && payload?.mode === 'auto' &&
    typeof storedKey === 'string' && storedKey.length >= 32 &&
    suppliedKey === storedKey;
}

function httpUrl(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('Add the source URL.'); }
  if (!['http:', 'https:'].includes(url.protocol)) {
    throw new Error('Source URLs must start with https:// or http://.');
  }
  return value;
}

export function newYorkDate(date) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York', year: 'numeric', month: '2-digit',
    day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
    hourCycle: 'h23', timeZoneName: 'longOffset',
  }).formatToParts(date).map(part => [part.type, part.value]));
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:${parts.second}${parts.timeZoneName.replace('GMT', '')}`;
}

export function preparePost(fields, now = new Date(), id = crypto.randomUUID()) {
  if (!['note', 'quotation', 'link'].includes(fields.kind)) {
    throw new Error('Choose a post kind.');
  }
  if (fields.kind !== 'link' && !fields.text.trim()) {
    throw new Error(fields.kind === 'quotation' ? 'No selected quotation was shared. Select text in Safari first.' : 'Write a note first.');
  }
  if (fields.kind !== 'note' && !fields.source_title.trim()) {
    throw new Error('Add the source title.');
  }
  if (fields.kind !== 'note') httpUrl(fields.source_url);
  const slug = `${now.toISOString().replace(/[-:.]/g, '').replace('Z', '')}-${id}`;
  const data = {
    kind: fields.kind,
    date: newYorkDate(now),
    title: fields.kind === 'note' ? fields.title : '',
    text: fields.text,
    reaction: fields.kind === 'quotation' ? fields.reaction : '',
    source_title: fields.kind === 'note' ? '' : fields.source_title,
    source_url: fields.kind === 'note' ? '' : fields.source_url,
    source_author: fields.kind === 'note' ? '' : fields.source_author,
    tags: [...new Set(fields.tags.split(',').map(tag => tag.trim()).filter(Boolean))],
    date_source: "Posted from Caleb's device; device clock, displayed in New York time.",
  };
  // JSON is a YAML subset: quotes, newlines, --- and Liquid stay literal data.
  const file = `---\n${JSON.stringify(data, null, 2)}\n---\n`;
  return {path: `_stream/${slug}.md`, permalink: `/stream/${slug}/`,
    file, content: encodeUtf8(file), data};
}

export async function publishPost(post, token, fetcher = fetch) {
  if (!token) throw new Error('Save your GitHub token in Phone setup first.');
  const headers = {
    Accept: 'application/vnd.github+json',
    Authorization: `Bearer ${token}`,
    'X-GitHub-Api-Version': '2026-03-10',
    'Content-Type': 'application/json',
  };
  const response = await fetcher(CONTENTS_API + post.path, {
    method: 'PUT', headers,
    body: JSON.stringify({branch: BRANCH, message: `post(stream): ${post.data.kind}`,
      content: post.content}),
  });
  if (response.ok) return response.json();
  // A lost response can leave the file committed. Verify exact content on retry;
  // never overwrite an existing post and never create a second path on retry.
  if (response.status === 422 || response.status === 409) {
    const existing = await fetcher(`${CONTENTS_API}${post.path}?ref=${BRANCH}`, {headers});
    if (existing.ok) {
      const body = await existing.json();
      if (body.content?.replace(/\s/g, '') === post.content) return {content: body, recovered: true};
    }
  }
  if (response.status === 401 || response.status === 403) {
    throw new Error('GitHub denied access. Check the token, its expiry and Contents: write permission. Your draft is saved.');
  }
  throw new Error(`GitHub returned ${response.status}. Your draft is saved; retry this same post.`);
}
