// Controlled transaction events; actual browser persistence is verified separately.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('services/run_checkpoint/checkpoint_web_storage.js', 'utf8');
const flush = async () => { await Promise.resolve(); await Promise.resolve(); await Promise.resolve(); };

function fixture() {
  const window = {};
  let request, get, transaction;
  const database = {
    close() {},
    transaction() {
      transaction = { objectStore: () => ({ get: () => (get = {}) }) };
      return transaction;
    },
  };
  vm.runInNewContext(source, {
    window, queueMicrotask,
    indexedDB: { open: () => (request = {}) },
  });
  const api = window.SkillLinesCheckpointStorage.create();
  return {
    api,
    read(row) {
      request.result = database;
      request.onsuccess();
      get.result = row;
      get.onsuccess();
    },
    complete() { transaction.oncomplete(); },
    abort() { transaction.onabort(); },
    versionchange() { database.onversionchange(); },
  };
}

(async () => {
  const f = fixture();
  const payload = ('a'.repeat(65535) + '😀中文').repeat(4);
  const responses = [];
  f.api.openChunked((...args) => responses.push(args));
  f.read({ revision: 7, payload });
  await flush();
  assert.equal(responses.length, 0, 'get success is not a transaction acknowledgement');
  const busy = [];
  f.api.openChunked((...args) => busy.push(args));
  await flush();
  assert.equal(busy[0][1], 'web_storage_busy');
  f.complete();
  await flush();
  assert.equal(responses.length, 1);
  const meta = JSON.parse(responses[0][2]);
  assert.equal(meta.units, payload.length);
  assert.equal(f.api.readOpenChunk('stale', 0), null);
  assert.equal(f.api.readOpenChunk(meta.id, 1), null);
  let combined = '', index = 0;
  while (combined.length < meta.units) {
    const chunk = f.api.readOpenChunk(meta.id, index++);
    assert.ok(chunk.length > 0 && chunk.length <= 65536);
    assert.ok(!/[\uD800-\uDBFF]$/.test(chunk));
    combined += chunk;
  }
  assert.equal(combined, payload);
  assert.equal(f.api.finishOpen(meta.id, index), true);
  assert.equal(f.api.finishOpen(meta.id, index), false);

  for (const text of ['a'.repeat(65535), 'a'.repeat(65536), 'a'.repeat(65537), '\ud800', '\udc00']) {
    const edge = fixture(), events = [];
    edge.api.openChunked((...args) => events.push(args));
    edge.read({ revision: 1, payload: text }); edge.complete(); await flush();
    const metadata = JSON.parse(events[0][2]);
    if (text.length === 1) {
      assert.equal(edge.api.readOpenChunk(metadata.id, 0), null);
    } else {
      let output = '', sequence = 0;
      while (output.length < text.length) output += edge.api.readOpenChunk(metadata.id, sequence++);
      assert.equal(output, text);
      assert.equal(edge.api.finishOpen(metadata.id, sequence), true);
    }
  }

  const partial = fixture();
  const result = [];
  partial.api.openChunked((...args) => result.push(args));
  partial.read({ revision: 2, payload });
  partial.complete();
  await flush();
  const id = JSON.parse(result[0][2]).id;
  assert.equal(partial.api.finishOpen(id, 0), false, 'incomplete transfer never confirms');
  assert.equal(partial.api.readOpenChunk(id, 0), null, 'failed finish releases the payload');

  const cancelled = fixture(), cancelledResult = [];
  cancelled.api.openChunked((...args) => cancelledResult.push(args));
  cancelled.read({ revision: 3, payload }); cancelled.complete(); await flush();
  const cancelledId = JSON.parse(cancelledResult[0][2]).id;
  const writing = [];
  cancelled.api.save('not committed', (...args) => writing.push(args)); await flush();
  assert.equal(writing[0][1], 'web_storage_busy');
  cancelled.versionchange();
  assert.equal(cancelled.api.readOpenChunk(cancelledId, 0), null);
  assert.equal(cancelled.api.finishOpen(cancelledId, 0), false);

  const aborted = fixture(), abortedResult = [];
  aborted.api.openChunked((...args) => abortedResult.push(args));
  aborted.read({ revision: 4, payload }); aborted.abort(); aborted.complete(); await flush();
  assert.equal(abortedResult.length, 1);
  assert.equal(abortedResult[0][0], false);
  console.log('checkpoint chunk bridge: transaction acknowledgement, busy, sequence, Unicode and cleanup passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
