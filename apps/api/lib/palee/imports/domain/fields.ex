defmodule Palee.Imports.Domain.Fields do
  @moduledoc """
  ADR-254: the Palee fields a column can be mapped to. Pure.

  One row of any file is one person and, optionally, what they have:
  a subscription package, a credit balance, one payment, one visit. A
  members list fills the person and package fields; a payment history
  repeats the person's email on every payment row; an attendance export
  repeats it on every visit row. Each field has a `type` (how a cell is
  read, `Values` / `DateParser`) and a `group` (what it writes).
  """

  @fields [
    %{key: "full_name", type: "text", group: "person"},
    %{key: "first_name", type: "text", group: "person"},
    %{key: "last_name", type: "text", group: "person"},
    %{key: "email", type: "email", group: "person"},
    %{key: "phone", type: "phone", group: "person"},
    %{key: "role", type: "role", group: "person"},
    %{key: "joined_on", type: "date", group: "person"},
    %{key: "membership_status", type: "status", group: "person"},
    %{key: "notes", type: "text", group: "person"},
    %{key: "external_id", type: "text", group: "person"},
    %{key: "package_name", type: "text", group: "package"},
    %{key: "package_price", type: "money", group: "package"},
    %{key: "package_starts_on", type: "date", group: "package"},
    %{key: "package_ends_on", type: "date", group: "package"},
    %{key: "credit_balance", type: "money", group: "credit"},
    %{key: "payment_amount", type: "money", group: "payment"},
    %{key: "payment_date", type: "date", group: "payment"},
    %{key: "payment_method", type: "payment_method", group: "payment"},
    %{key: "payment_note", type: "text", group: "payment"},
    %{key: "visit_date", type: "date", group: "visit"}
  ]

  @keys Enum.map(@fields, & &1.key)
  @types @fields |> Enum.map(& &1.type) |> Enum.uniq()
  @groups @fields |> Enum.map(& &1.group) |> Enum.uniq()
  @by_key Map.new(@fields, &{&1.key, &1})

  @doc "The catalog, in the order a mapping screen shows it."
  def all, do: @fields
  def keys, do: @keys
  def types, do: @types
  def groups, do: @groups

  def fetch(key), do: Map.fetch(@by_key, key)
  def type(key), do: @by_key |> Map.fetch!(key) |> Map.fetch!(:type)

  @doc "The fields that can identify a person (at least one must be mapped)."
  def identity_keys, do: ~w(email phone full_name first_name last_name)
end
