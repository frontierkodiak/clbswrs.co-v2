import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import {canAutoPublish, decodePayload, encodeUtf8, newYorkDate, preparePost,
  publishPost, CONTENTS_API} from '../assets/stream/publisher-core.mjs';

const literal = '  “A quotation.” 🦋\n---\n{{ site.secret }}\n<script>alert("no")</script>\nLast line  ';
const fields = {kind: 'quotation', title: '', text: literal,
  reaction: 'My reaction\nwith two lines.', source_title: 'Source & <title>',
  source_url: 'https://example.org/article?a=1&b=2', source_author: 'Name',
  tags: 'ecology, art, ecology'};
const date = new Date('2026-10-07T22:53:00.000Z');

test('the committed document preserves exact Unicode, punctuation and whitespace', () => {
  const post = preparePost(fields, date, 'fixed-id');
  const decoded = Buffer.from(post.content, 'base64').toString('utf8');
  const data = JSON.parse(decoded.slice(4, -5));
  assert.equal(data.text, literal);
  assert.equal(data.reaction, fields.reaction);
  assert.equal(data.source_url, fields.source_url);
  assert.deepEqual(data.tags, ['ecology', 'art']);
  assert.equal(data.date, '2026-10-07T18:53:00-04:00');
  assert.equal(data.title, '');
  assert.match(post.path, /^_stream\/20261007T225300000-fixed-id\.md$/);
  assert.equal(newYorkDate(new Date('2026-01-01T02:00:00Z')), '2025-12-31T21:00:00-05:00');
});

test('an empty selection or unsafe source cannot silently become a quotation', () => {
  assert.throws(() => preparePost({...fields, text: ' \n '}), /No selected quotation/);
  assert.throws(() => preparePost({...fields, source_url: 'javascript:alert(1)'}), /https/);
  assert.throws(() => preparePost({...fields, source_title: ''}), /source title/);
  const note = preparePost({...fields, kind: 'note', title: ''}, date, 'note');
  assert.equal(note.data.title, '');
  assert.equal(note.data.source_url, '');
});

test('only a paired automatic quotation can skip the Post button', () => {
  const payload = {version: 1, kind: 'quotation', mode: 'auto'};
  const key = 'a'.repeat(72);
  assert.equal(canAutoPublish(payload, key, key), true);
  for (const [supplied, saved] of [[null, key], ['wrong', key], [null, null], ['PAIRING_KEY', 'PAIRING_KEY']]) {
    assert.equal(canAutoPublish(payload, supplied, saved), false);
  }
  assert.equal(canAutoPublish({...payload, kind: 'link'}, key, key), false);
  assert.equal(canAutoPublish({...payload, mode: 'compose'}, key, key), false);
  assert.throws(() => decodePayload(encodeUtf8('{"version":2,"kind":"quotation"}')), /Unsupported/);
});

test('Safari extraction preserves the selection and never receives a credential', () => {
  const script = readFileSync(new URL('../tools/safari-selection.js', import.meta.url), 'utf8').replace('MODE', 'auto');
  let encoded;
  vm.runInNewContext(script, {
    window: {getSelection: () => ({toString: () => literal})},
    document: {title: fields.source_title, querySelector: () => null},
    location: {href: fields.source_url}, TextEncoder, btoa, encodeURIComponent,
    completion: value => { encoded = value; },
  });
  const payload = decodePayload(decodeURIComponent(encoded));
  assert.equal(payload.text, literal);
  assert.equal(payload.source_title, fields.source_title);
  assert.equal(payload.source_author, '');
  assert.equal(payload.mode, 'auto');
  assert.doesNotMatch(script, /PAIRING_KEY|Bearer|github-token/);
});

test('one authenticated API create targets only this repo and gh-pages', async () => {
  const post = preparePost(fields, date, 'api');
  let calls = 0;
  await publishPost(post, 'synthetic-token', async (url, options) => {
    calls++;
    assert.equal(url, CONTENTS_API + post.path);
    assert.equal(options.method, 'PUT');
    assert.equal(options.headers.Authorization, 'Bearer synthetic-token');
    assert.deepEqual(JSON.parse(options.body), {
      branch: 'gh-pages', message: 'post(stream): quotation', content: post.content,
    });
    assert.doesNotMatch(options.body, /synthetic-token/);
    return {ok: true, json: async () => ({content: {path: post.path}})};
  });
  assert.equal(calls, 1);
});

test('a retry recovers a lost receipt without overwriting or duplicating the post', async () => {
  const post = preparePost(fields, date, 'retry');
  const calls = [];
  const receipt = await publishPost(post, 'synthetic-token', async (url, options) => {
    calls.push([url, options.method]);
    return options.method === 'PUT' ? {ok: false, status: 422} : {
      ok: true, json: async () => ({content: post.content + '\n', html_url: 'https://github.com/example'}),
    };
  });
  assert.equal(receipt.recovered, true);
  assert.deepEqual(calls, [[CONTENTS_API + post.path, 'PUT'],
    [`${CONTENTS_API}${post.path}?ref=gh-pages`, undefined]]);
  await assert.rejects(publishPost(post, 'synthetic-token', async (url, options) =>
    options.method === 'PUT' ? {ok: false, status: 409} : {
      ok: true, json: async () => ({content: 'different contents'}),
    }), /GitHub returned 409/);
});

test('failure never reports publication success', async () => {
  const post = preparePost(fields, date, 'failed');
  for (const code of [401, 403, 500]) {
    await assert.rejects(publishPost(post, 'synthetic-token', async () =>
      ({ok: false, status: code})), /draft is saved/);
  }
  await assert.rejects(publishPost(post, '', () => assert.fail('must not call network')), /token/);
});
