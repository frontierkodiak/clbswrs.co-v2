async page => {
  page.setDefaultTimeout(10000);
  const base = 'http://127.0.0.1:4313';
  const literal = '  “Quote” 🦋\n---\n{{ site.secret }}\n<script>no()</script>  ';
  const key = 'a'.repeat(72);
  const payload = {version:1, kind:'quotation', mode:'auto', text:literal, source_title:'Synthetic source', source_url:'https://example.org/article', source_author:'Name'};
  const encoded = await page.evaluate(value => btoa(Array.from(new TextEncoder().encode(JSON.stringify(value)), byte => String.fromCharCode(byte)).join('')), payload);
  const writes = [];
  await page.unroute('https://api.github.com/**');
  await page.route('https://api.github.com/**', async route => {
    if (route.request().method() !== 'PUT') throw new Error('Unexpected request');
    writes.push(JSON.parse(route.request().postData()));
    await route.fulfill({status:201, contentType:'application/json', body:JSON.stringify({content:{html_url:'https://github.com/example/synthetic'}})});
  });
  await page.evaluate(key => { localStorage.clear(); localStorage.setItem('stream.github-token','synthetic-token'); localStorage.setItem('stream.shortcut-key',key); }, key);
  await page.goto(base+'/stream/post/');
  await page.goto(base+'/stream/post/#payload='+encodeURIComponent(encoded)+'&key=wrong');
  await page.waitForFunction(() => document.getElementById('status').textContent.includes('not paired'));
  if (writes.length !== 0) throw new Error('Unpaired link wrote to GitHub');
  if (await page.locator('#text').inputValue() !== literal) throw new Error('Text altered');
  if (await page.evaluate(() => location.hash)) throw new Error('Fragment retained');
  await page.locator('#discard').click();
  await page.goto(base+'/stream/post/#payload='+encodeURIComponent(encoded)+'&key='+key);
  await page.waitForFunction(() => document.getElementById('status').textContent.includes('Committed'));
  if (writes.length !== 1) throw new Error('Paired quote did not make exactly one write');
  const file = await page.evaluate(value => new TextDecoder().decode(Uint8Array.from(atob(value), char => char.charCodeAt(0))), writes[0].content);
  if (JSON.parse(file.slice(4,-5)).text !== literal) throw new Error('Committed text altered');
  if (JSON.stringify(writes).includes('synthetic-token')) throw new Error('Token leaked');
  await page.screenshot({path:'publisher-success-mobile.png'});
  await page.unroute('https://api.github.com/**');
  let attempts = 0;
  await page.route('https://api.github.com/**', async route => {
    attempts++;
    await route.fulfill({status:503, contentType:'application/json', body:'{}'});
  });
  await page.locator('#text').fill('Synthetic note; not published.');
  await page.locator('#publish').click();
  await page.waitForFunction(() => document.getElementById('status').textContent.includes('503'));
  const pendingBefore = await page.evaluate(() => localStorage.getItem('stream.pending'));
  await page.reload();
  if (await page.locator('#text').inputValue() !== 'Synthetic note; not published.') throw new Error('Lost failed draft');
  await page.locator('#publish').click();
  await page.waitForFunction(() => document.getElementById('status').textContent.includes('503'));
  const pendingAfter = await page.evaluate(() => localStorage.getItem('stream.pending'));
  if (pendingBefore !== pendingAfter || attempts !== 2) throw new Error('Retry changed file or duplicated request');
  await page.locator('#discard').click();
  await page.evaluate(() => localStorage.clear());
  return {unpairedWrites:0, pairedWrites:writes.length, retryAttempts:attempts, literalText:true, fragmentCleared:true};
}
