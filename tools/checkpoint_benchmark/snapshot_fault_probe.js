/* Isolated test-host fault injection. Never loaded by the game entry point. */
(() => {
  "use strict";
  if (location.origin !== "http://127.0.0.1:8994" || window.snapshotFault) return;
  const state = window.snapshotFault = { abortCheckpoint: false, holdTelemetryAck: false, aborted: 0, held: 0 };
  const put = IDBObjectStore.prototype.put;
  IDBObjectStore.prototype.put = function (...args) {
    const tx = this.transaction;
    if (tx.db.name === "skill-lines-checkpoints-v1" && state.abortCheckpoint) {
      ++state.aborted;
      tx.abort();
      throw new DOMException("Agent test transaction abort", "AbortError");
    }
    return put.apply(this, args);
  };
  const descriptor = Object.getOwnPropertyDescriptor(IDBTransaction.prototype, "oncomplete");
  Object.defineProperty(IDBTransaction.prototype, "oncomplete", {
    configurable: descriptor.configurable, enumerable: descriptor.enumerable,
    get: descriptor.get,
    set(callback) {
      descriptor.set.call(this, function (event) {
        if (state.holdTelemetryAck && this.db.name === "skill-lines-telemetry-v1" && this.mode === "readwrite") {
          ++state.held;
          return;
        }
        if (callback) callback.call(this, event);
      });
    }
  });
})();
