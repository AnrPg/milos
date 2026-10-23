defmodule Palee.Community.Domain.HostPolicy do
  @moduledoc """
  Who an event is hosted as (ADR-185 §1–2). Pure.

  * **«Διοργάνωση ως».** A person hosts «Ως εγώ» (their own one-person
    organiser organisation, created on first use) or as any business
    where they hold `manage_events`.
  * **A person's own events** are for everyone (`open`, they show in Γύρω
    μου and to the host's followers) or by invitation only (`club`: the
    organiser's club has only the host, so only people holding the host's
    link come). They never belong to a member group.
  * **Rate limits.** A person creates at most #{5} new events (a weekly run
    counts once) per 24 hours and holds at most #{30} upcoming live
    occurrences, so self-serve hosting cannot be used to flood Γύρω μου.
  """

  @daily_limit 5
  @upcoming_limit 30
  @self "self"

  def self_host, do: @self
  def daily_limit, do: @daily_limit
  def upcoming_limit, do: @upcoming_limit

  @doc "The organiser kind of organisation behind «Ως εγώ»."
  def organiser_kind, do: "organiser"

  @doc "Whether an organisation is a person's own (organiser kind)."
  def organiser?(%{provider_kind: kind}), do: kind == "organiser"
  def organiser?(kind) when is_binary(kind), do: kind == "organiser"
  def organiser?(_other), do: false

  @doc """
  How a host choice reads: `:self`, `{:business, organization_id}`, or
  `{:error, :invalid_host}`.
  """
  def parse(@self), do: :self
  def parse(nil), do: :self

  def parse(organization_id) when is_binary(organization_id) do
    case Ecto.UUID.cast(organization_id) do
      {:ok, id} -> {:business, id}
      :error -> {:error, :invalid_host}
    end
  end

  def parse(_other), do: {:error, :invalid_host}

  @doc """
  A person's own event's terms: never a group's; everyone or by invitation
  only (`club`), whatever else was asked.
  """
  def organiser_terms(attrs) do
    attrs = Map.delete(attrs, :channel_id)

    case Map.get(attrs, :audience) do
      "group" -> Map.put(attrs, :audience, "club")
      _other -> attrs
    end
  end

  @doc """
  Whether a person may create another event: `created_last_day` counts
  distinct events (a weekly run once) created in the last 24 hours,
  `upcoming` the live occurrences still ahead; `new_occurrences` is how
  many the new one adds.
  """
  def creation_check(%{created_last_day: created, upcoming: upcoming}, new_occurrences) do
    cond do
      created >= @daily_limit -> {:error, :event_rate_limited}
      upcoming + new_occurrences > @upcoming_limit -> {:error, :event_rate_limited}
      true -> :ok
    end
  end

  @doc "Name of a person's organiser organisation and its club: the person's nickname."
  def organiser_name(nickname) when is_binary(nickname) do
    case String.trim(nickname) do
      name when byte_size(name) >= 2 -> String.slice(name, 0, 80)
      _short -> "Palee events"
    end
  end

  def organiser_name(_nickname), do: "Palee events"
end
