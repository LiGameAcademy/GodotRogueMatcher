/* One automatic slot per origin. Only transaction completion acknowledges persistence. */
(() => {
  "use strict";
  const empty = JSON.stringify({ schema: "checkpoint-web-files-v1", files: {} });
  const notify = (callback, ok, reason = "", data = "") =>
    queueMicrotask(() => callback(ok, reason, data));
  window.SkillLinesCheckpointStorage = {
    create() {
      let database = null;
      let revision = 0;
      let writing = false;
      const valid = (row) => row && Object.keys(row).length === 2 &&
        Number.isSafeInteger(row.revision) && row.revision > 0 && typeof row.payload === "string";
      return {
        open(callback) {
          let settled = false;
          const finish = (ok, reason, data = "") => {
            if (settled) return;
            settled = true;
            notify(callback, ok, reason, data);
          };
          try {
            const request = indexedDB.open("skill-lines-checkpoints-v1", 1);
            request.onupgradeneeded = () => {
              if (!request.result.objectStoreNames.contains("state")) request.result.createObjectStore("state");
            };
            request.onerror = () => finish(false, "web_storage_open_failed");
            request.onblocked = () => finish(false, "web_storage_blocked");
            request.onsuccess = () => {
              if (settled) { request.result.close(); return; }
              database = request.result;
              database.onversionchange = () => { database.close(); database = null; };
              try {
                const transaction = database.transaction("state", "readonly");
                const get = transaction.objectStore("state").get("automatic");
                let payload = empty;
                let problem = "";
                get.onsuccess = () => {
                  if (get.result === undefined) { revision = 0; return; }
                  if (!valid(get.result)) { problem = "web_storage_record_invalid"; return; }
                  revision = get.result.revision;
                  payload = get.result.payload;
                };
                transaction.oncomplete = () => finish(!problem, problem, problem ? "" : payload);
                transaction.onabort = () => finish(false, "web_storage_read_failed");
              } catch (_) { finish(false, "web_storage_read_failed"); }
            };
          } catch (_) { finish(false, "web_storage_open_failed"); }
        },
        save(payload, callback) {
          if (!database) { notify(callback, false, "web_storage_not_open"); return; }
          if (writing) { notify(callback, false, "web_storage_busy"); return; }
          if (typeof payload !== "string" || revision >= Number.MAX_SAFE_INTEGER) {
            notify(callback, false, "web_storage_record_invalid"); return;
          }
          writing = true;
          const expected = revision;
          let problem = "web_storage_write_failed";
          try {
            const transaction = database.transaction("state", "readwrite");
            const store = transaction.objectStore("state");
            const get = store.get("automatic");
            get.onsuccess = () => {
              const row = get.result;
              const current = row === undefined ? 0 : (valid(row) ? row.revision : -1);
              if (current !== expected) {
                problem = "web_storage_conflict";
                transaction.abort();
                return;
              }
              store.put({ revision: expected + 1, payload }, "automatic");
            };
            transaction.oncomplete = () => {
              revision = expected + 1;
              writing = false;
              notify(callback, true);
            };
            transaction.onabort = () => {
              writing = false;
              notify(callback, false, problem);
            };
          } catch (_) {
            writing = false;
            notify(callback, false, problem);
          }
        },
      };
    },
  };
})();
