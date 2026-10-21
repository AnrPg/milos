defmodule MilosTraining.Application.GetJournalFeed do
  @moduledoc """
  `GET /api/me/journal` (ADR-139 §9, ADR-162): the member's own journal
  across every provider, freeform and device entries, read in their
  personal session.

  The Ροή filter (`kinds`, `sources`, `visibilities`, `date_from`,
  `date_to`, `q`; `Journal.Domain.JournalFilter`) narrows every source in
  SQL. With `remember=true` the filter is also stored as the member's
  last-used Ημερολόγιο filter (ADR-151), so it follows them across devices.
  Each item carries its `source` label and, for shareable kinds, its
  coach `audience`.
  """

  alias MilosTraining.Application.{JournalAudience, JournalFeed, SavedFilters}
  alias MilosTraining.{Journal, Organizations}

  @filter_keys ~w(kinds sources visibilities date_from date_to q)

  def call(%{user_id: user_id} = context, params) when is_map(params) do
    params = Map.new(params, fn {key, value} -> {to_string(key), value} end)

    with {:ok, filter} <- Journal.parse_filter(Map.take(params, @filter_keys)),
         :ok <- remember(context, filter, params["remember"]) do
      providers = Organizations.list_my_providers(context)
      member = JournalAudience.member(context, providers)

      scope =
        if Journal.filter_default?(filter),
          do: :owner,
          else: {:owner, Journal.filter_query(filter)}

      Journal.with_context(context, fn ->
        with {:ok, page} <- JournalFeed.page(user_id, scope, feed_params(params, filter)) do
          {:ok,
           page
           |> Map.update!(:items, &JournalAudience.annotate(&1, context, providers, member))
           |> Map.put(:filter, Journal.filter_params(filter))
           |> Map.put(:active_filter_count, Journal.filter_active_count(filter))}
        end
      end)
    end
  end

  # The kinds a page asks for: narrowed by the filter, never empty (an
  # impossible combination, such as text search over body snapshots only,
  # yields an empty page instead of every kind).
  defp feed_params(params, filter) do
    kinds = Journal.filter_kinds(filter, JournalFeed.kinds())

    params
    |> Map.take(~w(cursor limit))
    |> Map.put("kinds", if(kinds == [], do: :none, else: kinds))
  end

  defp remember(context, filter, remember) when remember in [true, "true"] do
    case SavedFilters.remember(context, "journal", Journal.filter_params(filter)) do
      {:ok, _filters} -> :ok
      error -> error
    end
  end

  defp remember(_context, _filter, _remember), do: :ok
end
