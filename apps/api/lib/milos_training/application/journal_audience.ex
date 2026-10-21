defmodule MilosTraining.Application.JournalAudience do
  @moduledoc """
  «Οι coach μου» across providers (ADR-162; board 17, Q5), the member's side:
  the default audience of the coach rungs (every active provider unless the
  member left some out), an entry's own audience, and how the member's feed
  shows both. The rules themselves are `Journal.Domain.CoachAudience`; row
  security applies the same ones to every coach read.

  Endpoints: `GET|PUT /api/me/journal/coach-audience` and
  `PUT /api/me/journal/entries/:kind/:id/audience`.
  """

  alias MilosTraining.Application.{BroadcastUserSync, JournalEntryLookup}
  alias MilosTraining.{Journal, Organizations}

  @doc "The member's audience inputs: active providers and exclusions."
  def member(%{user_id: user_id} = context, providers \\ nil) do
    providers = providers || Organizations.list_my_providers(context)

    excluded =
      Journal.with_context(context, fn -> Journal.list_audience_exclusions(user_id) end)

    Journal.audience_member(Organizations.active_provider_ids(providers), excluded)
  end

  @doc "`GET /api/me/journal/coach-audience`."
  def get_default(context) do
    providers = Organizations.list_my_providers(context)
    member = member(context, providers)
    default = Journal.default_audience(member)
    {active, _former} = Organizations.split_providers(providers)

    {:ok,
     %{
       organization_ids: Enum.sort(default),
       providers:
         Enum.map(active, fn provider ->
           %{
             organization_id: provider.organization_id,
             name: provider.name,
             kind: provider.kind,
             included: MapSet.member?(default, provider.organization_id)
           }
         end)
     }}
  end

  @doc "`PUT /api/me/journal/coach-audience`: the providers «Οι coach μου» means."
  def put_default(%{user_id: user_id} = context, ids) do
    with {:ok, exclusions} <- Journal.audience_exclusions_for(ids, member(context)) do
      :ok =
        Journal.with_context(context, fn ->
          Journal.replace_audience_exclusions(user_id, exclusions)
        end)

      broadcast(user_id, "journal_audience_changed")
      get_default(context)
    end
  end

  @doc """
  `PUT /api/me/journal/entries/:kind/:id/audience`: narrows (or, for a
  provider-less entry, names) who reads one entry; `nil` resets it.
  """
  def put_entry(%{user_id: user_id} = context, kind, id, ids) do
    Journal.with_context(context, fn ->
      with {:ok, entry} <- JournalEntryLookup.fetch(kind, id, user_id),
           {:ok, audience} <- store_entry(context, kind, entry, ids) do
        {:ok, %{kind: kind, id: entry.id, audience: audience}}
      end
    end)
    |> tap(fn
      {:ok, _result} -> broadcast(user_id, "journal_audience_changed")
      _error -> :ok
    end)
  end

  @doc "Validates and stores an entry's own audience; answers how the feed shows it."
  def store_entry(%{user_id: user_id} = context, kind, entry, ids) do
    member = member(context)
    subject = subject(kind, entry)

    with {:ok, override} <- Journal.validate_audience(ids, subject, member) do
      :ok = Journal.put_entry_audience(user_id, kind, entry.id, override)
      {:ok, view(subject, member, override)}
    end
  end

  @doc "Who a coach rung on this entry reaches (`:gym`, `:audience`, `:none`)."
  def reach(%{user_id: user_id} = context, kind, entry) do
    override = override(user_id, kind, entry.id)
    Journal.audience_reach(subject(kind, entry), member(context), override)
  end

  @doc "The rungs the member may move this entry to, given its audience."
  def choosable(context, kind, entry) do
    case {entry.organization_id, Journal.shareable_kind?(kind)} do
      {nil, true} ->
        if reach(context, kind, entry) == :audience,
          do: Enum.filter(Journal.choosable_visibilities(kind), &(&1 in ~w(private coach_can_view))),
          else: Journal.choosable_visibilities(kind, nil)

      {organization_id, _shareable} ->
        Journal.choosable_visibilities(kind, organization_id)
    end
  end

  @doc """
  Labels the member's own feed items (ADR-162): each item's `source`
  (provider, freeform or device; «πρώην» once the membership ended) and, for
  shareable kinds, its `audience` (`custom` and the providers a coach rung
  reaches). A provider-less entry becomes movable to `coach_can_view` once
  it has an audience.
  """
  def annotate(items, %{user_id: user_id}, providers, member) do
    directory = Organizations.provider_directory(providers)

    overrides =
      items
      |> Enum.filter(&Journal.shareable_kind?(&1.kind))
      |> Enum.group_by(& &1.kind, & &1.id)
      |> Map.new(fn {kind, ids} -> {kind, Journal.entry_audiences(user_id, kind, ids)} end)

    Enum.map(items, fn item ->
      source = Journal.entry_source(item.organization_id, device_source(item), directory)
      item = Map.put(item, :source, source)

      if Journal.shareable_kind?(item.kind) do
        override = overrides |> Map.get(item.kind, %{}) |> Map.get(item.id)
        subject = subject(item.kind, item)
        audience = view(subject, member, override)

        choosable =
          if is_nil(item.organization_id) and audience.organization_ids != [],
            do: Enum.filter(Journal.choosable_visibilities(item.kind), &(&1 in ~w(private coach_can_view))),
            else: item.choosable_visibilities

        %{item | choosable_visibilities: choosable} |> Map.put(:audience, audience)
      else
        Map.put(item, :audience, nil)
      end
    end)
  end

  defp view(subject, member, override) do
    readers =
      subject
      |> Map.put(:journal_visibility, "coach_can_view")
      |> Journal.audience_readers(member, override)

    %{custom: not is_nil(override), organization_ids: readers |> Enum.sort()}
  end

  defp override(user_id, kind, id) do
    if Journal.shareable_kind?(kind),
      do: user_id |> Journal.entry_audiences(kind, [id]) |> Map.get(id),
      else: nil
  end

  defp subject(kind, entry),
    do: %{
      kind: kind,
      organization_id: Map.get(entry, :organization_id),
      journal_visibility: Map.get(entry, :journal_visibility) || "private"
    }

  defp device_source(%{kind: "training_log", entry: entry}),
    do: device(Map.get(entry, :source_type))

  defp device_source(%{kind: "wellness", entry: %{entries: [_ | _] = entries}}) do
    sources = entries |> Enum.map(&device(Map.get(&1, :source))) |> Enum.uniq()
    if match?([source] when is_binary(source), sources), do: hd(sources)
  end

  defp device_source(_item), do: nil

  defp device(source) when is_binary(source),
    do: if(Journal.device_source?(source), do: source)

  defp device(source) when is_atom(source) and not is_nil(source), do: device(Atom.to_string(source))
  defp device(_source), do: nil

  defp broadcast(user_id, reason),
    do: BroadcastUserSync.for_user(user_id, ["my_journal"], reason: reason, payload: %{})
end
