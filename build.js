// Builds blessedbynel.html from blessedbynel.tpl.html, pointing each {{image}} placeholder at its file in photos/.
const fs = require("fs");
const files = { logo: "logo", face: "face", p1: "1", p2: "2", p3: "3", p4: "4", p5: "5" };
const html = fs.readFileSync(__dirname + "/blessedbynel.tpl.html", "utf8")
  .replace(/\{\{(\w+)\}\}/g, (_, k) => `photos/${files[k]}.jpg`);
fs.writeFileSync(__dirname + "/blessedbynel.html", html);
console.log("blessedbynel.html", Math.round(html.length / 1024) + " KB");
