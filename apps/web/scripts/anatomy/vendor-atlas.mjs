// Vendors the anatomy-models atlas (github.com/lucgrn3/anatomy-models @ ac52bab,
// CC BY-SA 4.0) into public/anatomy/v1 (ADR-164).
//
//   git clone https://github.com/lucgrn3/anatomy-models /tmp/am && git -C /tmp/am checkout ac52bab
//   (meshoptimizer is already in node_modules; otherwise npm install --no-save meshoptimizer@0.22.0)
//   node scripts/anatomy/vendor-atlas.mjs /tmp/am public/anatomy/v1
//
// What it does:
// - muscles.glb: removes every node whose credits.json source is `openanatomy`
//   (the two middle-ear muscles, 3D Slicer licence, both sides) together with
//   its mesh, accessors and geometry bytes. The meshopt streams are decoded raw
//   (filter NONE), the removed accessor ranges are cut out and the streams are
//   re-encoded with the same mode and filter, so kept geometry is bit-identical
//   (each stream is round-trip checked).
// - bones.glb, LICENSE: copied as they are.
// - index.json: muscle nodes only, centre/radius/box (for camera focus).
// - credits.json: the removed nodes, their source and the Slicer notice dropped.
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { MeshoptDecoder, MeshoptEncoder } from "meshoptimizer";

const [atlasDir, outDir] = process.argv.slice(2);
if (!atlasDir || !outDir) {
  console.error("usage: node scripts/anatomy/vendor-atlas.mjs <anatomy-models checkout> <out dir>");
  process.exit(1);
}
mkdirSync(outDir, { recursive: true });
await MeshoptDecoder.ready;
await MeshoptEncoder.ready;

const BANNED_SOURCE = "openanatomy";
const credits = JSON.parse(readFileSync(path.join(atlasDir, "credits.json"), "utf8"));
const banned = new Set(
  Object.entries(credits.nodes)
    .filter(([, credit]) => credit.source === BANNED_SOURCE)
    .map(([id]) => id),
);

function stripGlb(input, output) {
  const glb = readFileSync(input);
  const jsonLen = glb.readUInt32LE(12);
  const json = JSON.parse(glb.subarray(20, 20 + jsonLen).toString("utf8"));
  const binLen = glb.readUInt32LE(20 + jsonLen);
  const binStart = 20 + jsonLen + 8;
  const bin = glb.subarray(binStart, binStart + binLen);

  const removedNodes = new Set();
  json.nodes.forEach((node, i) => banned.has(node.name) && removedNodes.add(i));
  const removedMeshes = new Set([...removedNodes].map((i) => json.nodes[i].mesh));
  if (json.nodes.some((n, i) => !removedNodes.has(i) && removedMeshes.has(n.mesh))) {
    throw new Error("a removed mesh is shared with a kept node");
  }
  const primitiveAccessors = (p) => [...Object.values(p.attributes), ...(p.indices == null ? [] : [p.indices])];
  const removedAcc = new Set();
  for (const m of removedMeshes) json.meshes[m].primitives.flatMap(primitiveAccessors).forEach((a) => removedAcc.add(a));
  if (json.meshes.some((m, mi) => !removedMeshes.has(mi) && m.primitives.flatMap(primitiveAccessors).some((a) => removedAcc.has(a)))) {
    throw new Error("a removed accessor is shared with a kept mesh");
  }

  const chunks = [];
  let compOffset = 0;
  let fallbackOffset = 0;
  json.bufferViews = json.bufferViews.map((view, vi) => {
    const ext = view.extensions?.EXT_meshopt_compression;
    if (!ext) throw new Error("uncompressed buffer views are not supported");
    const stride = ext.byteStride;
    const raw = new Uint8Array(ext.count * stride);
    MeshoptDecoder.decodeGltfBuffer(raw, ext.count, stride, bin.subarray(ext.byteOffset, ext.byteOffset + ext.byteLength), ext.mode, "NONE");

    const accessors = json.accessors
      .map((a, ai) => ({ a, ai }))
      .filter(({ a }) => a.bufferView === vi)
      .sort((x, y) => (x.a.byteOffset ?? 0) - (y.a.byteOffset ?? 0));
    const kept = [];
    let cursor = 0;
    accessors.forEach(({ a, ai }, k) => {
      const start = a.byteOffset ?? 0;
      const end = k + 1 < accessors.length ? accessors[k + 1].a.byteOffset : raw.length;
      if (removedAcc.has(ai)) return;
      a.byteOffset = cursor;
      kept.push(raw.subarray(start, end));
      cursor += end - start;
    });
    if (cursor % stride) throw new Error("stride misalignment after cut");
    const out = new Uint8Array(cursor);
    let o = 0;
    for (const span of kept) {
      out.set(span, o);
      o += span.length;
    }
    const count = cursor / stride;
    const encoded = MeshoptEncoder.encodeGltfBuffer(out, count, stride, ext.mode);
    const check = new Uint8Array(cursor);
    MeshoptDecoder.decodeGltfBuffer(check, count, stride, encoded, ext.mode, "NONE");
    if (Buffer.compare(Buffer.from(check), Buffer.from(out)) !== 0) throw new Error("meshopt round-trip mismatch");

    const next = {
      ...view,
      byteOffset: fallbackOffset,
      byteLength: cursor,
      extensions: { EXT_meshopt_compression: { ...ext, byteOffset: compOffset, byteLength: encoded.length, count } },
    };
    chunks.push(encoded);
    compOffset += encoded.length;
    const pad = (4 - (compOffset % 4)) % 4;
    if (pad) {
      chunks.push(new Uint8Array(pad));
      compOffset += pad;
    }
    fallbackOffset += cursor + ((4 - (cursor % 4)) % 4);
    return next;
  });

  const remap = (list, removed, fix) => {
    const map = new Map();
    const kept = [];
    list.forEach((item, i) => {
      if (removed.has(i)) return;
      map.set(i, kept.length);
      kept.push(item);
    });
    kept.forEach((item) => fix?.(item));
    return [kept, map];
  };
  const [accessors, accMap] = remap(json.accessors, removedAcc);
  const [meshes, meshMap] = remap(json.meshes, removedMeshes, (m) => {
    for (const p of m.primitives) {
      for (const key of Object.keys(p.attributes)) p.attributes[key] = accMap.get(p.attributes[key]);
      if (p.indices != null) p.indices = accMap.get(p.indices);
    }
  });
  const removedNames = [...removedNodes].map((i) => json.nodes[i].name).sort();
  const [nodes, nodeMap] = remap(json.nodes, removedNodes, (n) => {
    if (n.mesh != null) n.mesh = meshMap.get(n.mesh);
  });
  const keepChildren = (ids) => ids.filter((c) => !removedNodes.has(c)).map((c) => nodeMap.get(c));
  for (const n of nodes) if (n.children) n.children = keepChildren(n.children);
  for (const s of json.scenes) s.nodes = keepChildren(s.nodes);
  Object.assign(json, { accessors, meshes, nodes });
  json.buffers[0].byteLength = compOffset;
  json.buffers[1].byteLength = fallbackOffset;

  let jsonBuf = Buffer.from(JSON.stringify(json), "utf8");
  jsonBuf = Buffer.concat([jsonBuf, Buffer.alloc((4 - (jsonBuf.length % 4)) % 4, 0x20)]);
  const binBuf = Buffer.concat(chunks.map((c) => Buffer.from(c)));
  const header = Buffer.alloc(12);
  header.writeUInt32LE(0x46546c67, 0);
  header.writeUInt32LE(2, 4);
  header.writeUInt32LE(12 + 8 + jsonBuf.length + 8 + binBuf.length, 8);
  const chunkHeader = (length, type) => {
    const h = Buffer.alloc(8);
    h.writeUInt32LE(length, 0);
    h.writeUInt32LE(type, 4);
    return h;
  };
  writeFileSync(output, Buffer.concat([header, chunkHeader(jsonBuf.length, 0x4e4f534a), jsonBuf, chunkHeader(binBuf.length, 0x004e4942), binBuf]));
  return removedNames;
}

const removed = stripGlb(path.join(atlasDir, "muscles.glb"), path.join(outDir, "muscles.glb"));
copyFileSync(path.join(atlasDir, "bones.glb"), path.join(outDir, "bones.glb"));
copyFileSync(path.join(atlasDir, "LICENSE"), path.join(outDir, "LICENSE"));

const index = JSON.parse(readFileSync(path.join(atlasDir, "index.json"), "utf8"));
const trimmed = { version: index.version, frame: index.frame, nodes: {} };
for (const [id, node] of Object.entries(index.nodes)) {
  if (node.layer !== "muscles" || banned.has(id)) continue;
  trimmed.nodes[id] = { c: node.c, r: node.r, box: node.box };
}
writeFileSync(path.join(outDir, "index.json"), JSON.stringify(trimmed));

const keptCredits = {
  ...credits,
  notices: credits.notices.filter((notice) => !/3D Slicer/i.test(notice)),
  sources: Object.fromEntries(Object.entries(credits.sources).filter(([key]) => key !== BANNED_SOURCE)),
  nodes: Object.fromEntries(Object.entries(credits.nodes).filter(([id]) => !banned.has(id))),
};
writeFileSync(path.join(outDir, "credits.json"), `${JSON.stringify(keptCredits, null, 1)}\n`);

console.log(`removed from muscles.glb: ${removed.join(", ")}`);
console.log(`index.json: ${Object.keys(trimmed.nodes).length} muscle nodes`);
