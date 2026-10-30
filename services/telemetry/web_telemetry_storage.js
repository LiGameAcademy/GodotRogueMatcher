/* Append-only observation files. Checkpoints use a separate database/transaction. */
(() => {
  "use strict";
  const FILE_LIMIT = 16 * 1024 * 1024, TOTAL_LIMIT = 64 * 1024 * 1024, COUNT_LIMIT = 2048;
  const size = (value) => new TextEncoder().encode(value).byteLength;
  const nameValid = (name) => typeof name === "string" && !name.includes("..") &&
    /^(telemetry|sessions|run_records)\/[A-Za-z0-9][A-Za-z0-9_.-]{0,180}\.jsonl$/.test(name);
  const fileValid = (row) => row && Object.keys(row).length === 3 && row.schema === "web-collection-file-v1" &&
    Number.isSafeInteger(row.revision) && row.revision > 0 && typeof row.text === "string" &&
    row.text.endsWith("\n") && size(row.text) <= FILE_LIMIT;
  const totalValid = (row) => row && Object.keys(row).length === 3 && row.schema === "web-collection-total-v1" &&
    Number.isSafeInteger(row.bytes) && row.bytes >= 0 && row.bytes <= TOTAL_LIMIT &&
    Number.isSafeInteger(row.files) && row.files >= 0 && row.files <= COUNT_LIMIT;
  const notify = (callback, ok, reason = "", data = "") =>
    queueMicrotask(() => callback(JSON.stringify({ ok, reason, data })));
  window.SkillLinesWebTelemetry = {
    create() {
      let database = null, writing = false, ready = false, opening = false;
      const snapshot = (finish) => {
        try {
          const transaction = database.transaction("files", "readonly");
          const store = transaction.objectStore("files");
          const keys = store.getAllKeys(), values = store.getAll();
          transaction.onabort = () => finish(false, "web_telemetry_read_failed");
          transaction.oncomplete = () => {
            const files = {}, rows = values.result, names = keys.result;
            let total = null, bytes = 0, count = 0, valid = rows.length === names.length;
            for (let i = 0; i < names.length; i++) {
              if (names[i] === "__total") { total = rows[i]; continue; }
              if (!nameValid(names[i]) || !fileValid(rows[i])) { valid = false; break; }
              files[names[i]] = rows[i];
              bytes += size(rows[i].text); count++;
            }
            if (!valid || !totalValid(total) || total.bytes !== bytes || total.files !== count)
              finish(false, "web_telemetry_snapshot_invalid");
            else finish(true, "", JSON.stringify(files));
          };
        } catch (_) { finish(false, "web_telemetry_read_failed"); }
      };
      return {
        open(callback) {
          if (opening || database) { notify(callback, false, "web_telemetry_busy"); return; }
          opening = true;
          let settled = false;
          const finish = (ok, reason = "", data = "") => {
            if (settled) return;
            settled = true;
            opening = false;
            ready = ok;
            if (!ok && database) { database.close(); database = null; }
            notify(callback, ok, reason, data);
          };
          try {
            const request = indexedDB.open("skill-lines-telemetry-v1", 1);
            request.onupgradeneeded = () => {
              const store = request.result.createObjectStore("files");
              store.put({ schema: "web-collection-total-v1", bytes: 0, files: 0 }, "__total");
            };
            request.onerror = () => finish(false, "web_telemetry_open_failed");
            request.onblocked = () => finish(false, "web_telemetry_blocked");
            request.onsuccess = () => {
              if (settled) { request.result.close(); return; }
              database = request.result;
              database.onversionchange = () => { database.close(); database = null; ready = false; };
              snapshot(finish);
            };
          } catch (_) { finish(false, "web_telemetry_open_failed"); }
        },
        snapshot(callback) {
          if (!database || !ready) { notify(callback, false, "web_telemetry_not_open"); return; }
          let settled = false;
          snapshot((ok, reason = "", data = "") => {
            if (settled) return;
            settled = true;
            if (!ok) { ready = false; if (database) database.close(); database = null; }
            notify(callback, ok, reason, data);
          });
        },
        append(payload, callback) {
          if (!database || !ready) { notify(callback, false, "web_telemetry_not_open"); return; }
          if (writing) { notify(callback, false, "web_telemetry_busy"); return; }
          let batch;
          try { batch = JSON.parse(payload); } catch (_) { notify(callback, false, "web_telemetry_request_invalid"); return; }
          if (!batch || Object.keys(batch).length !== 3 || !nameValid(batch.name) ||
              !Number.isSafeInteger(batch.revision) || batch.revision < 0 || batch.revision >= Number.MAX_SAFE_INTEGER ||
              typeof batch.text !== "string" || !batch.text.endsWith("\n") || size(batch.text) > FILE_LIMIT) {
            notify(callback, false, "web_telemetry_request_invalid"); return;
          }
          writing = true;
          let transaction = null, problem = "web_telemetry_write_failed";
          let settled = false;
          const finish = (ok) => {
            if (settled) return;
            settled = true; writing = false;
            notify(callback, ok, ok ? "" : problem);
          };
          try {
            transaction = database.transaction("files", "readwrite");
            transaction.oncomplete = () => finish(true);
            transaction.onabort = () => finish(false);
            const store = transaction.objectStore("files");
            const get = store.get(batch.name), totals = store.get("__total");
            let reads = 0;
            const append = () => {
              if (++reads !== 2) return;
              const old = get.result, total = totals.result;
              if (!totalValid(total) || (old !== undefined && (!fileValid(old) || total.files < 1 || total.bytes < size(old.text)))) {
                problem = "web_telemetry_snapshot_invalid"; transaction.abort(); return;
              }
              if ((old === undefined ? 0 : old.revision) !== batch.revision) {
                problem = "web_telemetry_conflict"; transaction.abort(); return;
              }
              const text = (old === undefined ? "" : old.text) + batch.text;
              const added = size(batch.text), count = total.files + (old === undefined ? 1 : 0);
              if (size(text) > FILE_LIMIT || total.bytes + added > TOTAL_LIMIT || count > COUNT_LIMIT) {
                problem = "web_telemetry_size_limit"; transaction.abort(); return;
              }
              store.put({ schema: "web-collection-file-v1", revision: batch.revision + 1, text }, batch.name);
              store.put({ schema: "web-collection-total-v1", bytes: total.bytes + added, files: count }, "__total");
            };
            get.onsuccess = append; totals.onsuccess = append;
          } catch (_) {
            if (transaction) { try { transaction.abort(); } catch (_) { finish(false); } }
            else finish(false);
          }
        },
      };
    },
  };
})();
