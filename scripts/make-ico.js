// 将多尺寸 PNG 打包为 Windows ICO (PNG-in-ICO, Vista+ 支持)
"use strict";
const fs = require("fs");
const path = require("path");

const buildDir = path.join(__dirname, "..", "pi-web-desktop-app", "build");
const sizes = [256, 64, 48, 32, 16];

const entries = sizes.map((size) => {
  const png = fs.readFileSync(path.join(buildDir, `icon-${size}.png`));
  return { size, png };
});

// ICO header
const header = Buffer.alloc(6);
header.writeUInt16LE(0, 0); // reserved
header.writeUInt16LE(1, 2); // type: icon
header.writeUInt16LE(entries.length, 4); // count

// directory entries (16 bytes each)
const dirEntries = [];
let offset = 6 + 16 * entries.length;
for (const e of entries) {
  const b = Buffer.alloc(16);
  b.writeUInt8(e.size === 256 ? 0 : e.size, 0); // width (0 = 256)
  b.writeUInt8(e.size === 256 ? 0 : e.size, 1); // height
  b.writeUInt8(0, 2); // colors
  b.writeUInt8(0, 3); // reserved
  b.writeUInt16LE(1, 4); // planes
  b.writeUInt16LE(32, 6); // bit count
  b.writeUInt32LE(e.png.length, 8); // size
  b.writeUInt32LE(offset, 12); // offset
  dirEntries.push(b);
  offset += e.png.length;
}

const ico = Buffer.concat([header, ...dirEntries, ...entries.map((e) => e.png)]);
const out = path.join(buildDir, "icon.ico");
fs.writeFileSync(out, ico);
console.log(`icon.ico written: ${ico.length} bytes (${sizes.join(",")}px)`);
