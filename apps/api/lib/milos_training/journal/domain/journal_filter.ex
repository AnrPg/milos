defmodule MilosTraining.Journal.Domain.JournalFilter do
  @moduledoc """
  The Ημερολόγιο › Ροή filter (ADR-162, vision §7.2 filters table), modelled
  once and versioned like Γύρω μου's (ADR-154): the feed endpoint, the
  remembered last-used filter and named saved filters all go through
  `parse/1` and store `to_params/1`.

  * **Τύπος** `kinds`: feed kinds (none = every kind).
  * **Πηγή** `sources`: provider ids, `freeform`, `device` (none = all).
  * **Ορατότητα** `visibilities`: ladder rungs (none = all).
  * **Ημερομηνίες** `date_from` / `date_to`: calendar days, inclusive, UTC.
  * **Αναζήτηση** `q`: 2–100 characters, matched (case-insensitive, by
    substring, trigram indexed) against the entry's own text and its
    Σχόλια; kinds without text drop out while it is set.

  Unknown keys are ignored, so an older client's saved filter still parses;
  a filter from a newer version is refused rather than half-understood.
  """

  alias MilosTraining.Identity.Domain.FilterFields
  alias MilosTraining.Journal.Domain.Visibility

  @version 1
  @text_kinds ~w(execution training_log pr note check_in injury craving)

  @type t :: %__MODULE__{}

  defstruct version: @version,
            kinds: [],
            sources: [],
            visibilities: [],
            date_from: nil,
            date_to: nil,
            q: nil

  def version, do: @version
  def default, do: %__MODULE__{}

  @doc "Kinds holding text that `q` can match."
  def text_kinds, do: @text_kinds

  def parse(nil), do: parse(%{})

  def parse(params) when is_map(params) do
    params = FilterFields.stringify(params)

    with :ok <- FilterFields.version(params["v"], @version),
         {:ok, kinds} <- FilterFields.subset(:kinds, params["kinds"], Visibility.kinds()),
         {:ok, sources} <- FilterFields.sources(:sources, params["sources"]),
         {:ok, visibilities} <-
           FilterFields.subset(:visibilities, params["visibilities"], Visibility.rungs()),
         {:ok, {from, to}} <- FilterFields.date_range(params["date_from"], params["date_to"]),
         {:ok, q} <- FilterFields.text(:q, params["q"], 2, 100) do
      {:ok,
       %__MODULE__{
         kinds: kinds,
         sources: sources,
         visibilities: visibilities,
         date_from: from,
         date_to: to,
         q: q
       }}
    end
  end

  def parse(_params), do: {:error, [filter: "must be an object"]}

  @doc "The canonical JSON form, what saved filters store and the API echoes."
  def to_params(%__MODULE__{} = filter) do
    %{
      "v" => filter.version,
      "kinds" => filter.kinds,
      "sources" => filter.sources,
      "visibilities" => filter.visibilities,
      "date_from" => FilterFields.iso(filter.date_from),
      "date_to" => FilterFields.iso(filter.date_to),
      "q" => filter.q
    }
  end

  @doc "How many facets are set, for «Φίλτρα (n)»; a date range counts once."
  def active_count(%__MODULE__{} = filter) do
    [
      filter.kinds != [],
      filter.sources != [],
      filter.visibilities != [],
      not is_nil(filter.date_from) or not is_nil(filter.date_to),
      not is_nil(filter.q)
    ]
    |> Enum.count(& &1)
  end

  def default?(%__MODULE__{} = filter), do: active_count(filter) == 0

  @doc """
  The kinds a feed page asks for: the requested ones narrowed by the filter
  (and to kinds with text while `q` is set).
  """
  def kinds(%__MODULE__{} = filter, requested) do
    requested
    |> then(&if(filter.kinds == [], do: &1, else: Enum.filter(&1, fn k -> k in filter.kinds end)))
    |> then(&if(is_nil(filter.q), do: &1, else: Enum.filter(&1, fn k -> k in @text_kinds end)))
  end

  @doc """
  What each journal source applies in SQL: provider ids and whether
  freeform / device entries pass (`sources?: false` means no source filter),
  rungs, the half-open `[from, to)` UTC window and the text pattern.
  """
  def to_query(%__MODULE__{} = filter) do
    %{
      sources?: filter.sources != [],
      organization_ids: Enum.reject(filter.sources, &(&1 in ~w(freeform device))),
      freeform?: "freeform" in filter.sources,
      device?: "device" in filter.sources,
      visibilities: filter.visibilities,
      from: filter.date_from && DateTime.new!(filter.date_from, ~T[00:00:00], "Etc/UTC"),
      to: filter.date_to && DateTime.new!(Date.add(filter.date_to, 1), ~T[00:00:00], "Etc/UTC"),
      q: filter.q && like_pattern(filter.q)
    }
  end

  @doc "A `LIKE` pattern matching `text` anywhere, with wildcards escaped."
  def like_pattern(text) do
    escaped =
      text
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%" <> escaped <> "%"
  end
end
