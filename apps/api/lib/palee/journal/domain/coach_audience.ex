defmodule Palee.Journal.Domain.CoachAudience do
  @moduledoc """
  «Οι coach μου» across providers (ADR-162; board 17, Q5 and Q6; per coach
  since ANR's call of 2026-10-21): which coaches read one of a member's
  journal entries. One policy, mirrored in SQL by
  `palee_entry_visible_to_acting_coach` (home provider) and
  `palee_journal_entry_shared_with_coach` (everyone else).

  A reader is a coach of a provider: `{organization_id, coach_user_id}`.

  1. Nothing below a coach rung reaches anyone (the ADR-139 ladder);
     injuries and reviews are the home provider's on any rung.
  2. Only a provider the member is an **active** member of reads anything:
     once a membership ends, its coaches lose access to every entry from
     that day (Q6), whatever it was shared with.
  3. Every coach of the **home** provider (where the entry was recorded:
     their class, their programme) reads it on a coach rung, as before.
  4. Anyone else reads it only when shared with them: an entry's own
     audience (`override`, a set of coaches) when the member set one;
     without one, a provider-less entry (freeform, device) goes to the
     member's default audience (every coach of every active provider minus
     the ones they left out; a coach who joins later is in), and an entry
     recorded at one provider goes nowhere else.

  Freeform and device entries start private (`Visibility.initial/3`); the
  default audience only matters once the member moves one up the ladder.
  """

  alias Palee.Journal.Domain.Visibility

  @shareable ~w(execution training_log pr note check_in)
  @always_home ~w(injury review)

  @type coach :: {String.t(), String.t()}
  @type member :: %{
          active: MapSet.t(String.t()),
          coaches: MapSet.t(coach()),
          excluded: MapSet.t(coach())
        }
  @type entry :: %{
          required(:kind) => String.t(),
          required(:organization_id) => String.t() | nil,
          required(:journal_visibility) => String.t()
        }

  @doc "Kinds whose entries can be shared beyond their home provider."
  def shareable_kinds, do: @shareable
  def shareable?(kind), do: kind in @shareable

  @doc """
  The member's side: active provider ids, the coaches of those providers
  (`{organization_id, coach_user_id}`) and the coaches left out by default.
  """
  def member(active_ids, coaches, excluded \\ []) do
    active = MapSet.new(active_ids)

    %{
      active: active,
      coaches: coaches |> Enum.filter(&MapSet.member?(active, elem(&1, 0))) |> MapSet.new(),
      excluded: MapSet.new(excluded)
    }
  end

  @doc "Where the coach rung goes for a provider-less entry without its own audience."
  def default_audience(%{coaches: coaches, excluded: excluded}),
    do: MapSet.difference(coaches, excluded)

  @doc "Every coach that reads `entry` (a set of `{organization_id, coach_user_id}`)."
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

  @doc "Does this coach of this provider read `entry`?"
  def visible_to?(entry, coach, member, override \\ nil),
    do: MapSet.member?(readers(entry, member, override), coach)

  @doc "The providers among `readers`."
  def organizations(readers), do: readers |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()

  @doc """
  Who a coach rung on this entry would reach: `:gym` (a home provider),
  `:audience` (shared with at least one coach elsewhere) or `:none`.
  """
  def reach(entry, member, override \\ nil) do
    cond do
      is_binary(entry.organization_id) -> :gym
      MapSet.size(shared(entry, member, override)) > 0 -> :audience
      true -> :none
    end
  end

  @doc """
  Expands what a request names into coaches: `{organization_id,
  coach_user_id}` pairs as they are, and a provider id as every coach it
  has. Anything outside the member's providers is refused.
  """
  def resolve(targets, member) when is_list(targets) do
    Enum.reduce_while(targets, {:ok, MapSet.new()}, fn target, {:ok, acc} ->
      case target(target, member) do
        {:ok, coaches} -> {:cont, {:ok, MapSet.union(acc, coaches)}}
        error -> {:halt, error}
      end
    end)
  end

  def resolve(_targets, _member), do: {:error, :unknown_provider}

  @doc """
  Validates an entry's own audience (already `resolve/2`d). `nil` resets it
  to the default. The home provider's coaches are implied and dropped. A
  provider-less entry cannot be narrowed to nobody (that is `private`).
  """
  def validate_override(nil, _entry, _member), do: {:ok, nil}

  def validate_override(%MapSet{} = coaches, entry, member) do
    with true <- shareable?(entry.kind) || {:error, :audience_not_supported},
         true <- MapSet.subset?(coaches, member.coaches) || {:error, :unknown_coach} do
      coaches =
        coaches
        |> Enum.reject(&(elem(&1, 0) == entry.organization_id))
        |> Enum.sort()

      cond do
        coaches == [] and is_nil(entry.organization_id) -> {:error, :empty_audience}
        coaches == [] -> {:ok, nil}
        true -> {:ok, coaches}
      end
    end
  end

  def validate_override(_coaches, _entry, _member), do: {:error, :unknown_coach}

  @doc """
  Validates a default audience (already `resolve/2`d): the coaches to leave
  out are every other coach of the active providers (so a coach who joins
  later is included).
  """
  def exclusions_for(%MapSet{} = coaches, member) do
    if MapSet.subset?(coaches, member.coaches),
      do: {:ok, member.coaches |> MapSet.difference(coaches) |> Enum.sort()},
      else: {:error, :unknown_coach}
  end

  def exclusions_for(_coaches, _member), do: {:error, :unknown_coach}

  defp target({organization_id, coach_user_id} = coach, member)
       when is_binary(organization_id) and is_binary(coach_user_id) do
    if MapSet.member?(member.coaches, coach),
      do: {:ok, MapSet.new([coach])},
      else: {:error, :unknown_coach}
  end

  defp target(organization_id, member) when is_binary(organization_id) do
    if MapSet.member?(member.active, organization_id),
      do: {:ok, coaches_of(member, organization_id)},
      else: {:error, :unknown_provider}
  end

  defp target(_target, _member), do: {:error, :unknown_provider}

  defp coaches_of(member, organization_id),
    do: member.coaches |> Enum.filter(&(elem(&1, 0) == organization_id)) |> MapSet.new()

  defp home(%{organization_id: id}, %{active: active} = member) when is_binary(id) do
    if MapSet.member?(active, id), do: coaches_of(member, id), else: MapSet.new()
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
    |> MapSet.intersection(member.coaches)
    |> Enum.reject(&(elem(&1, 0) == entry.organization_id))
    |> MapSet.new()
  end
end
