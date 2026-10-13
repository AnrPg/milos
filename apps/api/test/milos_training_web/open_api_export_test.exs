defmodule MilosTrainingWeb.OpenApiExportTest do
  use ExUnit.Case, async: true

  alias MilosTrainingWeb.OpenApiExport

  describe "encode!/1" do
    test "orders object keys recursively and keeps array order" do
      # 40 keys make a large (hash-ordered) map, whose iteration order is not
      # alphabetical.
      big_keys = Enum.map(1..40, &"k#{String.pad_leading("#{&1}", 2, "0")}")
      big = Map.new(Enum.with_index(big_keys))

      value = %{
        zeta: [%{b: 1, a: 2}, 3, "x"],
        alpha: %{"y" => true, "b" => nil},
        big: big
      }

      json = OpenApiExport.encode!(value)

      assert keys_in_order?(json, ~w(alpha big zeta))
      assert keys_in_order?(json, ~w(b y))
      assert keys_in_order?(json, big_keys)

      assert json =~
               ~s("zeta": [\n    {\n      "a": 2,\n      "b": 1\n    },\n    3,\n    "x"\n  ])

      assert Jason.decode!(json) == Jason.decode!(Jason.encode!(value))
    end

    test "honours custom encoders and sorts every object of the real spec" do
      spec = MilosTrainingWeb.ApiSpec.spec()
      json = OpenApiExport.encode!(spec)

      assert Jason.decode!(json) == Jason.decode!(Jason.encode!(spec))
      assert sorted_everywhere?(Jason.decode!(json, objects: :ordered_objects))
    end

    test "is byte-for-byte deterministic and ends with a newline" do
      spec = MilosTrainingWeb.ApiSpec.spec()
      json = OpenApiExport.encode!(spec)

      assert json == OpenApiExport.encode!(spec)
      assert String.ends_with?(json, "}\n")
    end
  end

  defp keys_in_order?(json, keys) do
    positions = Enum.map(keys, fn key -> :binary.match(json, ~s("#{key}":)) end)
    Enum.all?(positions, &match?({_, _}, &1)) and positions == Enum.sort(positions)
  end

  defp sorted_everywhere?(%Jason.OrderedObject{values: values}) do
    keys = Enum.map(values, &elem(&1, 0))

    keys == Enum.sort(keys) and
      Enum.all?(values, fn {_key, value} -> sorted_everywhere?(value) end)
  end

  defp sorted_everywhere?(list) when is_list(list), do: Enum.all?(list, &sorted_everywhere?/1)
  defp sorted_everywhere?(_scalar), do: true
end
