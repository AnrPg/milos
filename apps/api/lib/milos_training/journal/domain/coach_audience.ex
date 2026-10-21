defmodule MilosTraining.Journal.Domain.CoachAudience do
  @moduledoc """
  «Οι coach μου» across providers (ADR-162; board 17, Q5 and Q6): which
  providers read one of a member's journal entries. One policy, mirrored in
  SQL by `milos_entry_visible_to_acting_coach` (home provider) and
  `milos_journal_entry_shared_with_org` (everyone else).

  1. Nothing below a coach rung reaches anyone (the ADR-139 ladder);
     injuries and reviews are the home provider's on any rung.
  2. Only a provider the member is an **active** member of reads anything:
     once a membership ends, that provider loses access to every entry from
     that day (Q6), whatever it was shared with.
  3. The **home** provider (where the entry was recorded: their class, their
     programme) always reads it on a coach rung, as before.
  4. Anyone else reads it only when shared: an entry's own audience
     (`override`, a set of provider ids) when the member set one; without
     one, a provider-less entry (freeform, device) goes to the member's
     default audience (every active provider minus the ones they excluded),
     and an entry recorded at one provider goes nowhere else. So a coach at
     provider A never sees provider B's programme unless the member shared it
     with A.

  Freeform and device entries start private (`Visibility.initial/3`); the
  default audience only matters once the member moves one up the ladder.
  """

  alias MilosTraining.Journal.Domain.Visibility

  @shareable ~w(execution training_log pr note check_in)
  @always_home ~w(injury review)

  @type member :: %{active: MapSet.t(String.t()), excluded: MapSet.t(String.t())}
  @type entry :: %{
          required(:kind) => String.t(),
          required(:organization_id) => String.t() | nil,
          required(:journal_visibility) => String.t()
        }

  @doc "Kinds whose entries can be shared beyond their home provider."
  def shareable_kinds, do: @shareable
  def shareable?(kind), do: kind in @shareable

  @doc "The member's providers: active organization ids and the excluded ones."
  def member(active_ids, excluded_ids \\ []),
    do: %{active: MapSet.new(active_ids), excluded: MapSet.new(excluded_ids)}

  @doc "Where the coach rung goes for a provider-less entry without its own audience."
  def default_audience(%{active: active, excluded: excluded}),
    do: MapSet.difference(active, excluded)

  @doc "Every provider that reads `entry` (a set of organization ids)."
  def readers(entry, member, override \\ nil)

  def readers(%{kind: kind} = entry, member, _override) when kind in @always_home,
    do: home(entry, member)

  def readers(entry, member, override) do
    if Visibility.reaches_coach?(entry.journal_visibility) do
      entry
      |> home(member)
      |> MapSet.union(shared(entry, member, override))
    else
      MapSet.new()
    end
  end

  @doc "Does provider `organization_id` read `entry`?"
  def visible_to?(entry, organization_id, member, override \\ nil),
    do: MapSet.member?(readers(entry, member, override), organization_id)

  @doc """
  Who a coach rung on this entry would reach: `:gym` (a home provider),
  `:audience` (shared with at least one active provider) or `:none`.
  """
  def reach(entry, member, override \\ nil) do
    cond do
      is_binary(entry.organization_id) -> :gym
      MapSet.size(shared(entry, member, override)) > 0 -> :audience
      true -> :none
    end
  end

  @doc """
  Validates an entry's own audience. `nil` resets it to the default. Every id
  must be an active provider; the home provider is implied and dropped. A
  provider-less entry cannot be narrowed to nobody (that is `private`).
  """
  def validate_override(nil, _entry, _member), do: {:ok, nil}

  def validate_override(ids, entry, member) when is_list(ids) do
    with true <- shareable?(entry.kind) || {:error, :audience_not_supported},
         true <- Enum.all?(ids, &is_binary/1) || {:error, :unknown_provider},
         true <- Enum.all?(ids, &MapSet.member?(member.active, &1)) || {:error, :unknown_provider} do
      ids = ids |> Enum.reject(&(&1 == entry.organization_id)) |> Enum.uniq() |> Enum.sort()

      cond do
        ids == [] and is_nil(entry.organization_id) -> {:error, :empty_audience}
        ids == [] -> {:ok, nil}
        true -> {:ok, ids}
      end
    end
  end

  def validate_override(_ids, _entry, _member), do: {:error, :unknown_provider}

  @doc """
  Validates a default audience: a subset of the active providers. Returns the
  providers to exclude (the default includes every new provider).
  """
  def exclusions_for(ids, member) when is_list(ids) do
    if Enum.all?(ids, &(is_binary(&1) and MapSet.member?(member.active, &1))),
      do: {:ok, member.active |> MapSet.difference(MapSet.new(ids)) |> Enum.sort()},
      else: {:error, :unknown_provider}
  end

  def exclusions_for(_ids, _member), do: {:error, :unknown_provider}

  defp home(%{organization_id: id}, %{active: active}) when is_binary(id) do
    if MapSet.member?(active, id), do: MapSet.new([id]), else: MapSet.new()
  end

  defp home(_entry, _member), do: MapSet.new()

  defp shared(%{kind: kind} = entry, member, override) do
    candidates =
      cond do
        not shareable?(kind) -> MapSet.new()
        is_list(override) -> MapSet.new(override)
        is_nil(entry.organization_id) -> default_audience(member)
        true -> MapSet.new()
      end

    candidates
    |> MapSet.intersection(member.active)
    |> MapSet.delete(entry.organization_id)
  end
end
