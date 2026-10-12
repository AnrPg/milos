defmodule MilosTraining.Workouts.Domain.JsonSchema do
  @moduledoc """
  Minimal, dependency-free JSON Schema (draft 2020-12 subset) validator.

  Supports the keywords the canonical workout schemas use: `type` (string or
  list), `properties`, `required`, `additionalProperties: false`, `items`,
  `minItems`, `maxItems`, `enum`, `const`, `minimum`, `exclusiveMinimum`,
  `maximum`, `minLength`, `maxLength`, `oneOf`, `not` and `$ref` into `$defs`.
  A `not` schema reports its own `description` as the problem, so a schema
  can say *why* a key is forbidden. Unknown keywords (`title`,
  `description`, `examples`...) are ignored, as JSON Schema requires.

  `oneOf` reports the errors of the branch whose `const` discriminators match
  the data (e.g. the section with the same `format`), so messages stay
  specific instead of listing every branch.

  Returns `[]` or a list of `%{"path" => "a.b.0", "problem" => text}`.
  """

  def validate(schema, data), do: validate(schema, data, "", schema)

  @doc "Validates `data` found at `path` of a larger document (paths are prefixed)."
  def validate_at(schema, data, path), do: validate(schema, data, path, schema)

  defp validate(%{"$ref" => "#/$defs/" <> name}, data, path, root) do
    validate(get_in(root, ["$defs", name]), data, path, root)
  end

  defp validate(schema, data, path, root) when is_map(schema) do
    case check_type(schema, data, path) do
      [] ->
        Enum.flat_map(
          [&enum/4, &const/4, &number/4, &string/4, &object/4, &array/4, &one_of/4, &negate/4],
          & &1.(schema, data, path, root)
        )

      type_errors ->
        type_errors
    end
  end

  defp validate(_schema, _data, _path, _root), do: []

  ## type

  defp check_type(%{"type" => types}, data, path) do
    types = List.wrap(types)

    if Enum.any?(types, &type?(&1, data)),
      do: [],
      else: [error(path, "must be #{Enum.join(types, " or ")}")]
  end

  defp check_type(_schema, _data, _path), do: []

  defp type?("object", data), do: is_map(data)
  defp type?("array", data), do: is_list(data)
  defp type?("string", data), do: is_binary(data)

  defp type?("integer", data),
    do: is_integer(data) or (is_float(data) and data == Float.round(data))

  defp type?("number", data), do: is_number(data)
  defp type?("boolean", data), do: is_boolean(data)
  defp type?("null", data), do: is_nil(data)
  defp type?(_type, _data), do: false

  ## enum / const

  defp enum(%{"enum" => values}, data, path, _root) do
    if data in values, do: [], else: [error(path, "must be one of #{format_values(values)}")]
  end

  defp enum(_schema, _data, _path, _root), do: []

  defp const(%{"const" => value}, data, path, _root) do
    if data == value, do: [], else: [error(path, "must be #{Jason.encode!(value)}")]
  end

  defp const(_schema, _data, _path, _root), do: []

  ## numbers and strings

  defp number(schema, data, path, _root) when is_number(data) do
    min = Map.get(schema, "minimum")
    exclusive_min = Map.get(schema, "exclusiveMinimum")
    max = Map.get(schema, "maximum")

    cond do
      is_number(min) and data < min ->
        [error(path, "must be ≥ #{min}")]

      is_number(exclusive_min) and data <= exclusive_min ->
        [error(path, "must be > #{exclusive_min}")]

      is_number(max) and data > max ->
        [error(path, "must be ≤ #{max}")]

      true ->
        []
    end
  end

  defp number(_schema, _data, _path, _root), do: []

  defp string(schema, data, path, _root) when is_binary(data) do
    length = String.length(data)
    min = Map.get(schema, "minLength")
    max = Map.get(schema, "maxLength")

    cond do
      is_integer(min) and length < min -> [error(path, "must have at least #{min} characters")]
      is_integer(max) and length > max -> [error(path, "must have at most #{max} characters")]
      true -> []
    end
  end

  defp string(_schema, _data, _path, _root), do: []

  ## objects

  defp object(schema, data, path, root) when is_map(data) do
    properties = Map.get(schema, "properties", %{})

    required =
      schema
      |> Map.get("required", [])
      |> Enum.reject(&Map.has_key?(data, &1))
      |> Enum.map(&error(join(path, &1), "is required"))

    additional =
      if Map.get(schema, "additionalProperties") == false do
        data
        |> Map.keys()
        |> Enum.reject(&Map.has_key?(properties, &1))
        |> Enum.map(&error(join(path, &1), "is not allowed here"))
      else
        []
      end

    nested =
      Enum.flat_map(properties, fn {key, subschema} ->
        case Map.fetch(data, key) do
          {:ok, value} -> validate(subschema, value, join(path, key), root)
          :error -> []
        end
      end)

    required ++ additional ++ nested
  end

  defp object(_schema, _data, _path, _root), do: []

  ## arrays

  defp array(schema, data, path, root) when is_list(data) do
    count = length(data)
    min = Map.get(schema, "minItems")
    max = Map.get(schema, "maxItems")

    size =
      cond do
        is_integer(min) and count < min -> [error(path, "must have at least #{min} items")]
        is_integer(max) and count > max -> [error(path, "must have at most #{max} items")]
        true -> []
      end

    items =
      case Map.get(schema, "items") do
        nil ->
          []

        item_schema ->
          data
          |> Enum.with_index()
          |> Enum.flat_map(fn {item, index} ->
            validate(item_schema, item, join(path, index), root)
          end)
      end

    size ++ items
  end

  defp array(_schema, _data, _path, _root), do: []

  ## oneOf

  defp one_of(%{"oneOf" => branches}, data, path, root) do
    branches = Enum.map(branches, &resolve(&1, root))
    results = Enum.map(branches, &{&1, validate(&1, data, path, root)})

    case Enum.count(results, fn {_branch, errors} -> errors == [] end) do
      1 ->
        []

      0 ->
        case Enum.find(results, fn {branch, _errors} -> discriminators_match?(branch, data) end) do
          {_branch, errors} -> errors
          nil -> [error(path, "does not match any allowed shape#{discriminator_hint(branches)}")]
        end

      _many ->
        [error(path, "matches more than one allowed shape")]
    end
  end

  defp one_of(_schema, _data, _path, _root), do: []

  ## not

  defp negate(%{"not" => forbidden} = schema, data, path, root) do
    if validate(forbidden, data, path, root) == [],
      do: [error(path, Map.get(schema, "description", "is not allowed here"))],
      else: []
  end

  defp negate(_schema, _data, _path, _root), do: []

  defp resolve(%{"$ref" => "#/$defs/" <> name}, root), do: get_in(root, ["$defs", name])
  defp resolve(schema, _root), do: schema

  defp discriminators_match?(branch, data) when is_map(data) do
    consts =
      branch
      |> Map.get("properties", %{})
      |> Enum.filter(fn {_key, subschema} ->
        is_map(subschema) and Map.has_key?(subschema, "const")
      end)

    consts != [] and
      Enum.all?(consts, fn {key, subschema} -> Map.get(data, key) == subschema["const"] end)
  end

  defp discriminators_match?(_branch, _data), do: false

  defp discriminator_hint(branches) do
    values =
      branches
      |> Enum.flat_map(fn branch ->
        branch
        |> Map.get("properties", %{})
        |> Enum.flat_map(fn
          {key, %{"const" => value}} -> [{key, value}]
          _other -> []
        end)
      end)

    case values do
      [] ->
        ""

      [{key, _value} | _rest] ->
        "; #{key} must be one of #{format_values(Enum.map(values, &elem(&1, 1)))}"
    end
  end

  ## helpers

  defp format_values(values), do: Enum.map_join(values, ", ", &Jason.encode!/1)

  defp join("", key), do: to_string(key)
  defp join(path, key), do: "#{path}.#{key}"

  defp error(path, problem), do: %{"path" => path, "problem" => problem}
end
