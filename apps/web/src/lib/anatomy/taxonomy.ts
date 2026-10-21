/**
 * Offline mirror of the API's muscle tree
 * (`Palee.Anatomy.Domain.MuscleTaxonomy`, ADR-163): region -> group ->
 * head, each group and head carrying the Terminologia Anatomica 2 ids of the
 * atlas meshes that draw it (ADR-164, nodes `ta2-<id>.<l|r|m>`).
 *
 * The API module is the source of truth; `taxonomy.test.ts` parses it and
 * fails when this copy drifts. When `GET /api/anatomy/taxonomy` exists, its
 * answer wins and this stays the offline fallback. Display names are
 * translated through `Anatomy.muscle.<id>`; `name` is the English reference.
 */

export type MuscleNodeKind = "region" | "group" | "head";

export type MuscleNodeId = string;

export type MuscleNode = {
  id: MuscleNodeId;
  kind: MuscleNodeKind;
  name: string;
  parentId: MuscleNodeId | null;
  regionId: MuscleNodeId;
  groupId: MuscleNodeId | null;
  ta2Ids: readonly string[];
};

type HeadTuple = readonly [id: string, name: string, ta2Ids: readonly string[]];
type GroupTuple = readonly [id: string, name: string, ta2Ids: readonly string[], heads: readonly HeadTuple[]];
type RegionTuple = readonly [id: string, name: string, groups: readonly GroupTuple[]];
export type TaxonomyTree = readonly RegionTuple[];

export const TAXONOMY_VERSION = 1;

// {region, name, [{group, name, ta2_ids, [{head, name, ta2_ids}]}]}, as in the API module.
export const TAXONOMY_TREE: TaxonomyTree = [
  ["neck", "Neck", [
    ["sternocleidomastoid", "Sternocleidomastoid", ["2156"], []],
    ["scalenes", "Scalenes", ["2152", "2153", "2154"], []],
    ["splenius", "Splenius", ["2273", "2274"], []],
  ]],
  ["shoulders", "Shoulders", [
    ["deltoid", "Deltoid", [], [
      ["deltoid-anterior", "Anterior deltoid", ["2453"]],
      ["deltoid-lateral", "Lateral deltoid", ["2454"]],
      ["deltoid-posterior", "Posterior deltoid", ["2455"]],
    ]],
    ["rotator-cuff", "Rotator cuff", [], [
      ["supraspinatus", "Supraspinatus", ["2457"]],
      ["infraspinatus", "Infraspinatus", ["2458"]],
      ["teres-minor", "Teres minor", ["2459"]],
      ["subscapularis", "Subscapularis", ["2460"]],
    ]],
  ]],
  ["chest", "Chest", [
    ["pectoralis-major", "Pectoralis major", [], [
      ["pectoralis-major-clavicular", "Clavicular head", ["2302"]],
      ["pectoralis-major-sternocostal", "Sternocostal head", ["2303"]],
      ["pectoralis-major-abdominal", "Abdominal head", ["2304"]],
    ]],
    ["pectoralis-minor", "Pectoralis minor", ["2305"], []],
    ["serratus-anterior", "Serratus anterior", ["2307"], []],
  ]],
  ["upper-back", "Upper back", [
    ["trapezius", "Trapezius", [], [
      ["trapezius-upper", "Upper trapezius", ["2227"]],
      ["trapezius-middle", "Middle trapezius", ["2228"]],
      ["trapezius-lower", "Lower trapezius", ["2229"]],
    ]],
    ["rhomboids", "Rhomboids", ["2232", "2233"], []],
    ["levator-scapulae", "Levator scapulae", ["2234"], []],
    ["latissimus-dorsi", "Latissimus dorsi", ["2231"], []],
    ["teres-major", "Teres major", ["2462"], []],
  ]],
  ["lower-back", "Lower back", [
    ["erector-spinae", "Erector spinae", [], [
      ["iliocostalis", "Iliocostalis", ["2258", "2260", "2261"]],
      ["longissimus", "Longissimus", ["2263", "2265", "2266"]],
      ["spinalis", "Spinalis", ["2268", "2269", "2270"]],
    ]],
    ["multifidus", "Multifidus", ["2277", "2278", "2279"], []],
    ["quadratus-lumborum", "Quadratus lumborum", ["2382"], []],
  ]],
  ["arms", "Arms", [
    ["biceps-brachii", "Biceps", [], [
      ["biceps-brachii-long", "Long head", ["2465"]],
      ["biceps-brachii-short", "Short head", ["2466"]],
    ]],
    ["brachialis", "Brachialis", ["2469"], []],
    ["triceps-brachii", "Triceps", [], [
      ["triceps-brachii-long", "Long head", ["2472"]],
      ["triceps-brachii-lateral", "Lateral head", ["2473"]],
      ["triceps-brachii-medial", "Medial head", ["2474"]],
    ]],
  ]],
  ["forearms", "Forearms", [
    ["brachioradialis", "Brachioradialis", ["2496"], []],
    ["forearm-flexors", "Wrist and finger flexors", ["2481", "2482", "2484", "2485", "2487", "2488", "2491", "2492"], []],
    ["forearm-extensors", "Wrist and finger extensors", ["2497", "2499", "2500", "2506", "2508", "2509", "2515"], []],
  ]],
  ["core", "Core", [
    ["rectus-abdominis", "Rectus abdominis", ["2357"], []],
    ["obliques", "Obliques", [], [
      ["obliques-external", "External oblique", ["2364"]],
      ["obliques-internal", "Internal oblique", ["2373"]],
    ]],
    ["transversus-abdominis", "Transversus abdominis", ["2375"], []],
    ["diaphragm", "Diaphragm", ["2327"], []],
  ]],
  ["hips", "Hips and glutes", [
    ["glutes", "Glutes", [], [
      ["gluteus-maximus", "Gluteus maximus", ["2598"]],
      ["gluteus-medius", "Gluteus medius", ["2599"]],
      ["gluteus-minimus", "Gluteus minimus", ["2600"]],
    ]],
    ["hip-flexors", "Hip flexors", [], [
      ["iliopsoas", "Iliopsoas", ["2594", "2595"]],
      ["tensor-fasciae-latae", "Tensor fasciae latae", ["2602"]],
      ["sartorius", "Sartorius", ["2610"]],
    ]],
    ["hip-rotators", "Deep hip rotators", ["2604", "2605", "2606", "2607", "2608", "2636"], []],
  ]],
  ["thighs", "Thighs", [
    ["quadriceps", "Quadriceps", [], [
      ["rectus-femoris", "Rectus femoris", ["2614"]],
      ["vastus-lateralis", "Vastus lateralis", ["2618"]],
      ["vastus-intermedius", "Vastus intermedius", ["2619"]],
      ["vastus-medialis", "Vastus medialis", ["2620"]],
    ]],
    ["hamstrings", "Hamstrings", [], [
      ["biceps-femoris-long", "Biceps femoris, long head", ["2639"]],
      ["biceps-femoris-short", "Biceps femoris, short head", ["2640"]],
      ["semitendinosus", "Semitendinosus", ["2641"]],
      ["semimembranosus", "Semimembranosus", ["2642"]],
    ]],
    ["adductors", "Adductors", [], [
      ["adductor-magnus", "Adductor magnus", ["2630"]],
      ["adductor-longus", "Adductor longus", ["2628"]],
      ["adductor-brevis", "Adductor brevis", ["2629"]],
      ["gracilis", "Gracilis", ["2635"]],
      ["pectineus", "Pectineus", ["2627"]],
    ]],
  ]],
  ["lower-legs", "Lower legs", [
    ["calves", "Calves", [], [
      ["gastrocnemius-medial", "Gastrocnemius, medial head", ["2659"]],
      ["gastrocnemius-lateral", "Gastrocnemius, lateral head", ["2658"]],
      ["soleus", "Soleus", ["2660"]],
    ]],
    ["tibialis-anterior", "Tibialis anterior", ["2644"], []],
    ["fibularis", "Fibularis", ["2652", "2653"], []],
  ]],
];

/** Every node in tree order (region, then its groups, each followed by its heads). */
export function buildNodes(tree: TaxonomyTree): MuscleNode[] {
  return tree.flatMap(([regionId, regionName, groups]) => {
    const groupNodes = groups.flatMap(([groupId, groupName, groupTa2, heads]) => {
      const headNodes: MuscleNode[] = heads.map(([headId, headName, headTa2]) => ({
        id: headId,
        kind: "head",
        name: headName,
        parentId: groupId,
        regionId,
        groupId,
        ta2Ids: headTa2,
      }));
      const group: MuscleNode = {
        id: groupId,
        kind: "group",
        name: groupName,
        parentId: regionId,
        regionId,
        groupId,
        ta2Ids: [...groupTa2, ...headNodes.flatMap((head) => head.ta2Ids)],
      };
      return [group, ...headNodes];
    });
    const region: MuscleNode = {
      id: regionId,
      kind: "region",
      name: regionName,
      parentId: null,
      regionId,
      groupId: null,
      ta2Ids: groupNodes.filter((node) => node.kind === "group").flatMap((node) => node.ta2Ids),
    };
    return [region, ...groupNodes];
  });
}

export const MUSCLE_NODES: readonly MuscleNode[] = buildNodes(TAXONOMY_TREE);

const BY_ID = new Map(MUSCLE_NODES.map((node) => [node.id, node]));
const CHILDREN = new Map<string, MuscleNode[]>();
for (const node of MUSCLE_NODES) {
  if (node.parentId) CHILDREN.set(node.parentId, [...(CHILDREN.get(node.parentId) ?? []), node]);
}

/** ta2 id -> the head (or head-less group) whose mesh it is. */
const LEAF_BY_TA2 = new Map<string, MuscleNode>();
for (const node of MUSCLE_NODES) {
  const leaf = node.kind === "head" || (node.kind === "group" && !CHILDREN.has(node.id));
  if (leaf) for (const ta2 of node.ta2Ids) LEAF_BY_TA2.set(ta2, node);
}

export function muscleNode(id: string | null | undefined): MuscleNode | undefined {
  return id ? BY_ID.get(id) : undefined;
}

export function isMuscleNodeId(id: string): boolean {
  return BY_ID.has(id);
}

export function childrenOf(id: string): MuscleNode[] {
  return CHILDREN.get(id) ?? [];
}

/** The group a target rolls up to (a group is its own group); null for regions and unknown ids. */
export function groupOf(id: string): MuscleNodeId | null {
  const node = BY_ID.get(id);
  return node && node.kind !== "region" ? node.groupId : null;
}

/** The heads of a group; a group without heads is its own single head. */
export function headsOf(groupId: string): MuscleNodeId[] {
  const heads = childrenOf(groupId);
  if (heads.length > 0) return heads.map((head) => head.id);
  return BY_ID.get(groupId)?.kind === "group" ? [groupId] : [];
}

/** The head (or head-less group) a mesh draws; undefined for meshes outside the tree. */
export function leafForTa2(ta2: string): MuscleNode | undefined {
  return LEAF_BY_TA2.get(ta2);
}
