import fs from "node:fs";
import path from "node:path";

import { parseElixirTaxonomy } from "./elixir-taxonomy";
import { FITNESS_QUALITIES } from "./qualities";
import {
  MUSCLE_NODES,
  TAXONOMY_TREE,
  TAXONOMY_VERSION,
  groupOf,
  headsOf,
  leafForTa2,
  muscleNode,
} from "./taxonomy";

const domainDir = path.resolve(__dirname, "../../../../api/lib/milos_training/anatomy/domain");
const taxonomySource = path.join(domainDir, "muscle_taxonomy.ex");
const qualitiesSource = path.join(domainDir, "fitness_qualities.ex");
const atlasIndex = path.resolve(__dirname, "../../../public/anatomy/v1/index.json");

describe("muscle taxonomy mirror", () => {
  // The web image is built without the API sources; the monorepo checkout (CI) has them.
  it.skipIf(!fs.existsSync(taxonomySource))("matches the API module (tree and version)", () => {
    const { version, tree } = parseElixirTaxonomy(fs.readFileSync(taxonomySource, "utf8"));
    expect(TAXONOMY_VERSION).toBe(version);
    expect(TAXONOMY_TREE).toEqual(tree);
  });

  it.skipIf(!fs.existsSync(qualitiesSource))("lists the API's ten fitness qualities in order", () => {
    const source = fs.readFileSync(qualitiesSource, "utf8");
    const block = /@qualities \[([\s\S]*?)\]/.exec(source)?.[1] ?? "";
    expect([...FITNESS_QUALITIES]).toEqual([...block.matchAll(/"([^"]+)"/g)].map((match) => match[1]));
  });

  it("has unique ids and parents that exist", () => {
    const ids = MUSCLE_NODES.map((node) => node.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const node of MUSCLE_NODES) {
      if (node.parentId) expect(muscleNode(node.parentId)).toBeDefined();
    }
  });

  it("rolls heads up to groups and owns every mesh once", () => {
    expect(groupOf("deltoid-anterior")).toBe("deltoid");
    expect(groupOf("latissimus-dorsi")).toBe("latissimus-dorsi");
    expect(groupOf("shoulders")).toBeNull();
    expect(headsOf("deltoid")).toEqual(["deltoid-anterior", "deltoid-lateral", "deltoid-posterior"]);
    expect(headsOf("latissimus-dorsi")).toEqual(["latissimus-dorsi"]);
    expect(muscleNode("deltoid")?.ta2Ids).toEqual(["2453", "2454", "2455"]);
    expect(leafForTa2("2454")?.id).toBe("deltoid-lateral");
    expect(leafForTa2("2231")?.id).toBe("latissimus-dorsi");
    expect(leafForTa2("9999")).toBeUndefined();

    const leaves = MUSCLE_NODES.filter((n) => n.kind === "head" || (n.kind === "group" && headsOf(n.id)[0] === n.id));
    const ta2 = leaves.flatMap((n) => n.ta2Ids);
    expect(new Set(ta2).size).toBe(ta2.length);
  });

  it("only names meshes that the vendored atlas has", () => {
    const index = JSON.parse(fs.readFileSync(atlasIndex, "utf8")) as { nodes: Record<string, unknown> };
    const atlasTa2 = new Set(Object.keys(index.nodes).map((id) => /^ta2-(\d+)/.exec(id)?.[1]));
    const missing = MUSCLE_NODES.flatMap((n) => n.ta2Ids).filter((id) => !atlasTa2.has(id));
    expect(missing).toEqual([]);
  });
});
