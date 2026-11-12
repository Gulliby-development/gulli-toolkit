// Screenshots every HTML file given: node tools/preview/shoot.js a.html b.html ...
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ deviceScaleFactor: Number(process.env.SCALE || 1) });
  for (const f of process.argv.slice(2)) {
    await p.goto('file://' + require('path').resolve(f));
    const el = await p.$('.ui');
    await el.screenshot({ path: f.replace(/\.html$/, '.png') });
  }
  await b.close();
})();
