import {canAutoPublish, decodePayload, preparePost, publishPost} from './publisher-core.mjs';

const TOKEN = 'stream.github-token';
const KEY = 'stream.shortcut-key';
const DRAFT = 'stream.draft';
const PENDING = 'stream.pending';
const $ = id => document.getElementById(id);
const fields = ['kind', 'title', 'text', 'source-title', 'source-url', 'source-author', 'reaction', 'tags'];
let pending = null;
let busy = false;
let automatic = false;

function status(message) { $('status').textContent = message; }
function values() {
  return Object.fromEntries(fields.map(id => [id.replaceAll('-', '_'), $(id).value]));
}
function setValues(data) {
  for (const id of fields) {
    const value = data[id.replaceAll('-', '_')];
    if (typeof value === 'string') $(id).value = value;
  }
  showFields();
}
function showFields() {
  const kind = $('kind').value;
  $('source-fields').hidden = kind === 'note';
  $('reaction-fields').hidden = kind !== 'quotation';
  $('note-title-fields').hidden = kind !== 'note';
  $('text-label').textContent = {note: 'Note', quotation: 'Quotation', link: 'Comment (optional)'}[kind];
}
function saveDraft() {
  localStorage.setItem(DRAFT, JSON.stringify(values()));
}
function showAccess() {
  $('access-status').textContent = localStorage.getItem(TOKEN) ? 'Access saved on this phone.' : 'No access saved.';
  $('pairing-key').value = localStorage.getItem(KEY) || '';
}
function lockForm(locked) {
  for (const element of $('post-form').elements) element.disabled = locked;
}

async function submit(event) {
  event?.preventDefault();
  if (busy) return;
  busy = true;
  lockForm(true);
  $('receipt').hidden = true;
  try {
    const token = localStorage.getItem(TOKEN);
    if (!token) {
      $('settings').open = true;
      throw new Error('Save your GitHub token in Phone setup first. Nothing was published.');
    }
    saveDraft();
    pending ||= preparePost(values());
    localStorage.setItem(PENDING, JSON.stringify(pending));
    status('Sending to GitHub…');
    const result = await publishPost(pending, token);
    status('Committed to GitHub. The site will update when its Pages build finishes, usually within a few minutes.');
    const receipt = $('receipt');
    const link = document.createElement('a');
    link.href = pending.permalink;
    link.textContent = 'Post permalink (available after the build)';
    receipt.replaceChildren(link);
    const edit = document.createElement('a');
    edit.href = result.content.html_url;
    edit.textContent = 'Edit or delete on GitHub';
    receipt.append(' · ', edit);
    receipt.hidden = false;
    localStorage.removeItem(DRAFT);
    localStorage.removeItem(PENDING);
    pending = null;
    automatic = false;
    $('post-form').reset();
    showFields();
  } catch (error) {
    status(error instanceof TypeError ? 'Could not reach GitHub. Your draft is saved; tap Post to retry.' : error.message);
    if (pending) status(`${$('status').textContent} The submitted text is locked until retried or discarded.`);
  } finally {
    busy = false;
    lockForm(false);
    if (pending) {
      for (const id of fields) $(id).disabled = true;
      $('publish').textContent = 'Retry same post';
    } else {
      $('publish').textContent = 'Post';
    }
  }
}

function initialize() {
  const fragment = new URLSearchParams(location.hash.slice(1));
  // Shared text and the pairing key must not linger in address/history entries.
  history.replaceState(null, '', location.pathname);
  showAccess();
  const savedDraft = localStorage.getItem(DRAFT);
  if (savedDraft) setValues(JSON.parse(savedDraft));
  const savedPending = localStorage.getItem(PENDING);
  if (savedPending) {
    pending = JSON.parse(savedPending);
    setValues({...pending.data, tags: pending.data.tags.join(', ')});
    for (const id of fields) $(id).disabled = true;
    $('publish').textContent = 'Retry same post';
    status('A previous post has no confirmed receipt. Retry it or discard before starting another.');
    return;
  }
  if (fragment.has('payload')) {
    const payload = decodePayload(fragment.get('payload'));
    if (savedDraft) {
      status('A draft is already saved. It was kept; discard it before sharing a new quotation.');
      return;
    }
    setValues(payload);
    saveDraft();
    automatic = canAutoPublish(payload, fragment.get('key'), localStorage.getItem(KEY));
    if (payload.mode === 'auto' && !automatic) {
      status('This Shortcut is not paired with this phone. Review the quotation and tap Post, or pair it in Phone setup.');
    }
    if (automatic) submit();
  } else if (fragment.has('shared')) {
    if (savedDraft) {
      status('A draft is already saved. It was kept; discard it before sharing new text.');
      return;
    }
    const shared = fragment.get('shared');
    const urls = shared.match(/https?:\/\/[^\s<>]+/g) || [];
    const url = urls.at(-1) || '';
    setValues({kind: shared.trim() === url ? 'link' : 'quotation', text: shared, source_url: url});
    saveDraft();
    status('Check the shared text and fill in its source title. Apps share different amounts of metadata. Nothing has been posted.');
  }
  if (!localStorage.getItem(TOKEN)) $('settings').open = true;
  showFields();
}

$('post-form').addEventListener('submit', submit);
$('post-form').addEventListener('input', () => { showFields(); saveDraft(); });
$('save-token').addEventListener('click', () => {
  const token = $('token').value.trim();
  if (!token) { status('Paste a repository-scoped token first.'); return; }
  localStorage.setItem(TOKEN, token);
  $('token').value = '';
  showAccess();
  if (automatic) submit();
});
$('forget-token').addEventListener('click', () => {
  localStorage.removeItem(TOKEN);
  localStorage.removeItem(KEY);
  automatic = false;
  showAccess();
});
$('pair').addEventListener('click', () => {
  localStorage.setItem(KEY, crypto.randomUUID() + crypto.randomUUID());
  showAccess();
});
$('discard').addEventListener('click', () => {
  pending = null;
  automatic = false;
  localStorage.removeItem(DRAFT);
  localStorage.removeItem(PENDING);
  lockForm(false);
  $('post-form').reset();
  $('publish').textContent = 'Post';
  $('receipt').hidden = true;
  showFields();
  status('Draft discarded. A previously committed file, if any, is not deleted by this action.');
});

try { initialize(); } catch (error) {
  automatic = false;
  status(`Could not open the shared post: ${error.message} Nothing was published.`);
}

// Safari can reuse the publisher tab when another share changes only its
// fragment. That navigation must ingest the new selection too.
window.addEventListener('hashchange', () => {
  try { initialize(); } catch (error) {
    automatic = false;
    status(`Could not open the shared post: ${error.message} Nothing was published.`);
  }
});
