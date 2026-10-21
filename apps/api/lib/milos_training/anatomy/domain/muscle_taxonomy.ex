defmodule MilosTraining.Anatomy.Domain.MuscleTaxonomy do
  @moduledoc """
  Code-owned, versioned muscle tree for WOD goals, the anatomy atlas and
  muscle coverage (ADR-163): region -> group -> head.

  Every group and head carries the Terminologia Anatomica 2 ids of the meshes
  that draw it in the atlas asset (ADR-164, anatomy-models `ta2-<id>.<side>`
  nodes), so the API, the atlas and coverage share one vocabulary. A group
  without heads owns its meshes directly; a group with heads owns the union of
  its heads' meshes.

  Ids are stable slugs. Names may change, but an id is never reassigned to a
  different muscle; bump `version/0` when nodes are added or removed so stored
  goals can be migrated or re-suggested. Display names are translated on the
  client (`anatomy.<id>`); `name` here is the English reference name.

  Only muscles that training loads in a way worth showing are in the tree.
  Meshes outside it (face, eye, pelvic floor, intrinsic hand and foot muscles)
  render neutral in the atlas.
  """

  @version 1

  # {region_id, name, [{group_id, name, ta2_ids, [{head_id, name, ta2_ids}]}]}
  @tree [
    {"neck", "Neck",
     [
       {"sternocleidomastoid", "Sternocleidomastoid", ["2156"], []},
       {"scalenes", "Scalenes", ["2152", "2153", "2154"], []},
       {"splenius", "Splenius", ["2273", "2274"], []}
     ]},
    {"shoulders", "Shoulders",
     [
       {"deltoid", "Deltoid", [],
        [
          {"deltoid-anterior", "Anterior deltoid", ["2453"]},
          {"deltoid-lateral", "Lateral deltoid", ["2454"]},
          {"deltoid-posterior", "Posterior deltoid", ["2455"]}
        ]},
       {"rotator-cuff", "Rotator cuff", [],
        [
          {"supraspinatus", "Supraspinatus", ["2457"]},
          {"infraspinatus", "Infraspinatus", ["2458"]},
          {"teres-minor", "Teres minor", ["2459"]},
          {"subscapularis", "Subscapularis", ["2460"]}
        ]}
     ]},
    {"chest", "Chest",
     [
       {"pectoralis-major", "Pectoralis major", [],
        [
          {"pectoralis-major-clavicular", "Clavicular head", ["2302"]},
          {"pectoralis-major-sternocostal", "Sternocostal head", ["2303"]},
          {"pectoralis-major-abdominal", "Abdominal head", ["2304"]}
        ]},
       {"pectoralis-minor", "Pectoralis minor", ["2305"], []},
       {"serratus-anterior", "Serratus anterior", ["2307"], []}
     ]},
    {"upper-back", "Upper back",
     [
       {"trapezius", "Trapezius", [],
        [
          {"trapezius-upper", "Upper trapezius", ["2227"]},
          {"trapezius-middle", "Middle trapezius", ["2228"]},
          {"trapezius-lower", "Lower trapezius", ["2229"]}
        ]},
       {"rhomboids", "Rhomboids", ["2232", "2233"], []},
       {"levator-scapulae", "Levator scapulae", ["2234"], []},
       {"latissimus-dorsi", "Latissimus dorsi", ["2231"], []},
       {"teres-major", "Teres major", ["2462"], []}
     ]},
    {"lower-back", "Lower back",
     [
       {"erector-spinae", "Erector spinae", [],
        [
          {"iliocostalis", "Iliocostalis", ["2258", "2260", "2261"]},
          {"longissimus", "Longissimus", ["2263", "2265", "2266"]},
          {"spinalis", "Spinalis", ["2268", "2269", "2270"]}
        ]},
       {"multifidus", "Multifidus", ["2277", "2278", "2279"], []},
       {"quadratus-lumborum", "Quadratus lumborum", ["2382"], []}
     ]},
    {"arms", "Arms",
     [
       {"biceps-brachii", "Biceps", [],
        [
          {"biceps-brachii-long", "Long head", ["2465"]},
          {"biceps-brachii-short", "Short head", ["2466"]}
        ]},
       {"brachialis", "Brachialis", ["2469"], []},
       {"triceps-brachii", "Triceps", [],
        [
          {"triceps-brachii-long", "Long head", ["2472"]},
          {"triceps-brachii-lateral", "Lateral head", ["2473"]},
          {"triceps-brachii-medial", "Medial head", ["2474"]}
        ]}
     ]},
    {"forearms", "Forearms",
     [
       {"brachioradialis", "Brachioradialis", ["2496"], []},
       {"forearm-flexors", "Wrist and finger flexors",
        ["2481", "2482", "2484", "2485", "2487", "2488", "2491", "2492"], []},
       {"forearm-extensors", "Wrist and finger extensors",
        ["2497", "2499", "2500", "2506", "2508", "2509", "2515"], []}
     ]},
    {"core", "Core",
     [
       {"rectus-abdominis", "Rectus abdominis", ["2357"], []},
       {"obliques", "Obliques", [],
        [
          {"obliques-external", "External oblique", ["2364"]},
          {"obliques-internal", "Internal oblique", ["2373"]}
        ]},
       {"transversus-abdominis", "Transversus abdominis", ["2375"], []},
       {"diaphragm", "Diaphragm", ["2327"], []}
     ]},
    {"hips", "Hips and glutes",
     [
       {"glutes", "Glutes", [],
        [
          {"gluteus-maximus", "Gluteus maximus", ["2598"]},
          {"gluteus-medius", "Gluteus medius", ["2599"]},
          {"gluteus-minimus", "Gluteus minimus", ["2600"]}
        ]},
       {"hip-flexors", "Hip flexors", [],
        [
          {"iliopsoas", "Iliopsoas", ["2594", "2595"]},
          {"tensor-fasciae-latae", "Tensor fasciae latae", ["2602"]},
          {"sartorius", "Sartorius", ["2610"]}
        ]},
       {"hip-rotators", "Deep hip rotators",
        ["2604", "2605", "2606", "2607", "2608", "2636"], []}
     ]},
    {"thighs", "Thighs",
     [
       {"quadriceps", "Quadriceps", [],
        [
          {"rectus-femoris", "Rectus femoris", ["2614"]},
          {"vastus-lateralis", "Vastus lateralis", ["2618"]},
          {"vastus-intermedius", "Vastus intermedius", ["2619"]},
          {"vastus-medialis", "Vastus medialis", ["2620"]}
        ]},
       {"hamstrings", "Hamstrings", [],
        [
          {"biceps-femoris-long", "Biceps femoris, long head", ["2639"]},
          {"biceps-femoris-short", "Biceps femoris, short head", ["2640"]},
          {"semitendinosus", "Semitendinosus", ["2641"]},
          {"semimembranosus", "Semimembranosus", ["2642"]}
        ]},
       {"adductors", "Adductors", [],
        [
          {"adductor-magnus", "Adductor magnus", ["2630"]},
          {"adductor-longus", "Adductor longus", ["2628"]},
          {"adductor-brevis", "Adductor brevis", ["2629"]},
          {"gracilis", "Gracilis", ["2635"]},
          {"pectineus", "Pectineus", ["2627"]}
        ]}
     ]},
    {"lower-legs", "Lower legs",
     [
       {"calves", "Calves", [],
        [
          {"gastrocnemius-medial", "Gastrocnemius, medial head", ["2659"]},
          {"gastrocnemius-lateral", "Gastrocnemius, lateral head", ["2658"]},
          {"soleus", "Soleus", ["2660"]}
        ]},
       {"tibialis-anterior", "Tibialis anterior", ["2644"], []},
       {"fibularis", "Fibularis", ["2652", "2653"], []}
     ]}
  ]

  @nodes (for {region_id, region_name, groups} <- @tree, reduce: [] do
            acc ->
              group_nodes =
                Enum.flat_map(groups, fn {group_id, group_name, group_ta2, heads} ->
                  head_nodes =
                    Enum.map(heads, fn {head_id, head_name, head_ta2} ->
                      %{
                        id: head_id,
                        kind: :head,
                        name: head_name,
                        parent_id: group_id,
                        region_id: region_id,
                        group_id: group_id,
                        ta2_ids: head_ta2
                      }
                    end)

                  group = %{
                    id: group_id,
                    kind: :group,
                    name: group_name,
                    parent_id: region_id,
                    region_id: region_id,
                    group_id: group_id,
                    ta2_ids: group_ta2 ++ Enum.flat_map(head_nodes, & &1.ta2_ids)
                  }

                  [group | head_nodes]
                end)

              region = %{
                id: region_id,
                kind: :region,
                name: region_name,
                parent_id: nil,
                region_id: region_id,
                group_id: nil,
                ta2_ids: Enum.flat_map(group_nodes, &if(&1.kind == :group, do: &1.ta2_ids, else: []))
              }

              acc ++ [region | group_nodes]
          end)

  @by_id Map.new(@nodes, &{&1.id, &1})

  @doc "Taxonomy version; bumped whenever a node is added or removed."
  def version, do: @version

  @doc "Every node in tree order (region, then its groups, each followed by its heads)."
  def nodes, do: @nodes

  def fetch(id) when is_binary(id), do: Map.get(@by_id, id)
  def fetch(_id), do: nil

  def known?(id), do: Map.has_key?(@by_id, id)

  @doc "Ids that may be targeted by goals and feedback: groups and heads (regions are views)."
  def targetable?(id) do
    case fetch(id) do
      %{kind: kind} when kind in [:group, :head] -> true
      _other -> false
    end
  end

  def regions, do: Enum.filter(@nodes, &(&1.kind == :region))
  def groups, do: Enum.filter(@nodes, &(&1.kind == :group))

  def children(id), do: Enum.filter(@nodes, &(&1.parent_id == id))

  @doc """
  The group a target rolls up to (a group is its own group). Coverage and the
  goal summary count at group level, the atlas drills down to heads.
  """
  def group_of(id) do
    case fetch(id) do
      %{kind: :group} -> id
      %{kind: :head, group_id: group_id} -> group_id
      _other -> nil
    end
  end

  @doc "The heads of a group; a group without heads is its own single head."
  def heads_of(group_id) do
    case children(group_id) do
      [] -> if known?(group_id), do: [group_id], else: []
      heads -> Enum.map(heads, & &1.id)
    end
  end
end
