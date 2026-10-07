// Executed by Apple's Run JavaScript on Web Page action, not by the publisher.
// No credential or pairing key is ever present in the page's JavaScript.
const selection = window.getSelection().toString();
const title = document.title;
const author = document.querySelector('meta[name="author"]')?.content || '';
const payload = {
  version: 1,
  kind: selection.trim() ? 'quotation' : 'link',
  mode: 'MODE',
  text: selection,
  source_title: title,
  source_url: location.href,
  source_author: author,
};
const bytes = new TextEncoder().encode(JSON.stringify(payload));
const encoded = btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join(''));
completion(encodeURIComponent(encoded));
