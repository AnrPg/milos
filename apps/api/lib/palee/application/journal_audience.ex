defmodule Palee.Application.JournalAudience do
  @moduledoc """
  «Οι coach μου» across providers (ADR-162; board 17, Q5; per coach since
  2026-10-21), the member's side: the default audience of the coach rungs
  (every coach of every active provider unless the member left some out),
  an entry's own audience, and how the member's feed shows both. The rules
  themselves are `Journal.Domain.CoachAudience`; row security applies the
  same ones to every coach read.

  Requests name coaches as `%{"organization_id" => id, "user_id" => id}`;
  a bare provider id still means every coach it has.

  Endpoints: `GET|PUT /api/me/journal/coach-audience` and
  `PUT /api/me/journal/entries/:kind/:id/audience`.
  """

  alias Palee.Application.{BroadcastUserSync, JournalEntryLookup}
  alias Palee.{Identity, Journal, Organizations}

  @doc "The member's audience inputs: active providers, their coaches and exclusions."
  def member(%{user_id: user_id} = context, providers \\ nil) do
    providers = providers || Organizations.list_my_providers(context)

    excluded =
      Journal.with_context(context, fn -> Journal.list_audience_exclusions(user_id) end)

    Journal.audience_member(
      Organizations.active_provider_ids(providers),
      Organizations.list_my_provider_coaches(context),
      excluded
    )
  end

  @doc "`GET /api/me/journal/coach-audience`."
  def get_default(context) do
    providers = Organizations.list_my_providers(context)
    member = member(context, providers)
    default = Journal.default_audience(member)
    {active, _former} = Organizations.split_providers(providers)
    people = member.coaches |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Identity.list_by_ids()
    people = Map.new(people, &{&1.id, &1})

    {:ok,
     %{
       organization_ids: Journal.audience_organizations(default),
       coaches: coach_refs(default),
       providers:
         Enum.map(active, fn provider ->
           coaches =
             member.coaches
             |> Enum.filter(&(elem(&1, 0) == provider.organization_id))
             |> Enum.map(fn {_org, user_id} = coach ->
               person = Map.get(people, user_id, %{})

               %{
                 user_id: user_id,
                 name: Map.get(person, :display_nickname) || Map.get(person, :nickname),
                 avatar_url: Map.get(person, :avatar_url),
                 included: MapSet.member?(default, coach)
               }
             end)
             |> Enum.sort_by(&String.downcase(&1.name || ""))

           %{
             organization_id: provider.organization_id,
             name: provider.name,
             kind: provider.kind,
             included: Enum.any?(coaches, & &1.included),
             coaches: coaches
           }
         end)
     }}
  end

  @doc "`PUT /api/me/journal/coach-audience`: the coaches «Οι coach μου» means."
  def put_default(%{user_id: user_id} = context, targets) do
    member = member(context)

    with {:ok, targets} <- targets(targets),
         {:ok, coaches} <- Journal.resolve_audience(targets, member),
         {:ok, exclusions} <- Journal.audience_exclusions_for(coaches, member) do
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
  def put_entry(%{user_id: user_id} = context, kind, id, targets) do
    Journal.with_context(context, fn ->
      with {:ok, entry} <- JournalEntryLookup.fetch(kind, id, user_id),
           {:ok, audience} <- store_entry(context, kind, entry, targets) do
        {:ok, %{kind: kind, id: entry.id, audience: audience}}
      end
    end)
    |> tap(fn
      {:ok, _result} -> broadcast(user_id, "journal_audience_changed")
      _error -> :ok
    end)
  end

  @doc "Validates and stores an entry's own audience; answers how the feed shows it."
  def store_entry(%{user_id: user_id} = context, kind, entry, targets) do
    member = member(context)
    subject = subject(kind, entry)

    with {:ok, coaches} <- entry_coaches(targets, member),
         {:ok, override} <- Journal.validate_audience(coaches, subject, member) do
      :ok = Journal.put_entry_audience(user_id, kind, entry.id, override)
      {:ok, view(subject, member, override)}
    end
  end

  @doc """
  What a request names, as `CoachAudience.resolve/2` takes it: provider ids
  and `{organization_id, coach_user_id}`.
  """
  def targets(nil), do: {:ok, []}
  def targets(:none), do: {:error, :unknown_coach}

  def targets(targets) when is_list(targets) do
    Enum.reduce_while(targets, {:ok, []}, fn target, {:ok, acc} ->
      case target(target) do
        {:ok, target} -> {:cont, {:ok, [target | acc]}}
        :error -> {:halt, {:error, :unknown_coach}}
      end
    end)
    |> then(fn
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end)
  end

  def targets(_targets), do: {:error, :unknown_coach}

  @doc """
  What a request body names: provider ids under `ids_key` and coaches under
  `coaches_key`. `:none` when it sends neither, `nil` when both are null
  (reset to the default).
  """
  def requested(params, ids_key, coaches_key) when is_map(params) do
    case {Map.fetch(params, ids_key), Map.fetch(params, coaches_key)} do
      {:error, :error} ->
        :none

      {ids, coaches} ->
        ids = fetched(ids)
        coaches = fetched(coaches)
        if is_nil(ids) and is_nil(coaches), do: nil, else: List.wrap(ids) ++ List.wrap(coaches)
    end
  end

  defp fetched({:ok, value}), do: value
  defp fetched(:error), do: nil

  defp target(id) when is_binary(id), do: {:ok, id}

  defp target(%{} = coach) do
    with organization_id when is_binary(organization_id) <- field(coach, "organization_id"),
         user_id when is_binary(user_id) <- field(coach, "user_id") do
      {:ok, {organization_id, user_id}}
    else
      _missing -> :error
    end
  end

  defp target(_target), do: :error

  defp entry_coaches(nil, _member), do: {:ok, nil}
  defp entry_coaches(:none, _member), do: {:error, :unknown_coach}

  defp entry_coaches(targets, member) do
    with {:ok, targets} <- targets(targets), do: Journal.resolve_audience(targets, member)
  end

  defp field(map, key), do: Map.get(map, key) || Map.get(map, String.to_atom(key))

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
          do:
            Enum.filter(Journal.choosable_visibilities(kind), &(&1 in ~w(private coach_can_view))),
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
            do:
              Enum.filter(
                Journal.choosable_visibilities(item.kind),
                &(&1 in ~w(private coach_can_view))
              ),
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

    %{
      custom: not is_nil(override),
      organization_ids: Journal.audience_organizations(readers),
      coaches: coach_refs(readers)
    }
  end

  defp coach_refs(coaches),
    do:
      coaches
      |> Enum.sort()
      |> Enum.map(fn {organization_id, user_id} ->
        %{organization_id: organization_id, user_id: user_id}
      end)

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

  # ADR-161: a watch workout of its own is the device's entry.
  defp device_source(%{kind: "device_activity", entry: entry}),
    do: device(Map.get(entry, :provider))

  defp device_source(_item), do: nil

  defp device(source) when is_binary(source),
    do: if(Journal.device_source?(source), do: source)

  defp device(source) when is_atom(source) and not is_nil(source),
    do: device(Atom.to_string(source))

  defp device(_source), do: nil

  defp broadcast(user_id, reason),
    do: BroadcastUserSync.for_user(user_id, ["my_journal"], reason: reason, payload: %{})
end
