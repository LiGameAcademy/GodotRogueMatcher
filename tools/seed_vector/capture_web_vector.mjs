import { chromium } from "playwright";
import fs from "fs";

const url = process.argv[2] || "http://127.0.0.1:8766/";
const out = process.argv[3] || ".godot/seed-vector/42-web.json";
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
page.on("console", (msg) => {
	if (msg.text().includes("SEED_PORTABLE")) console.error("[console]", msg.text());
});
await page.goto(url, { waitUntil: "load", timeout: 120000 });
const vector = await page.waitForFunction(() => window.__SEED_PORTABLE_VECTOR__, null, { timeout: 120000 });
const data = await vector.jsonValue();
fs.mkdirSync(out.replace(/[^/\\]+$/, ""), { recursive: true });
fs.writeFileSync(out, JSON.stringify(data));
console.log("wrote", out);
await browser.close();
