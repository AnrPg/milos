defmodule Palee.UnscopedQueryDetector do
  @moduledoc """
  TD-092 diagnostic (opt-in with `PALEE_TEST_DETECT_UNSCOPED=1`): records every
  Ecto query that a ConnCase request issues against a forced-RLS table while
  the session carries no scope at all (`app.organization_id` and `app.user_id`
  both empty). Under the production runtime role such a query reads nothing or
  is rejected, so each hit is a candidate missing `RepoContext.run/2`.

  The report is printed when the suite finishes. It is a discovery aid, not a
  gate: queries that legitimately run unscoped against RLS tables (none are
  expected) would show up here too.
  """

  @table __MODULE__
  @flag {__MODULE__, :active}
  @busy {__MODULE__, :busy}

  def enabled?, do: System.get_env("PALEE_TEST_DETECT_UNSCOPED") == "1"

  def start do
    :ets.new(@table, [:named_table, :public, :bag])

    :telemetry.attach(
      "td092-unscoped-query-detector",
      [:palee, :repo, :query],
      &__MODULE__.handle/4,
      nil
    )

    ExUnit.after_suite(fn _result -> report() end)
  end

  @doc "Runs `fun` (a request) with detection active."
  def watch(fun) do
    if enabled?() do
      Process.put(@flag, true)

      try do
        fun.()
      after
        Process.delete(@flag)
      end
    else
      fun.()
    end
  end

  def handle(_event, _measurements, %{source: source}, _config) when is_binary(source) do
    if Process.get(@flag) && !Process.get(@busy) && source in rls_tables() do
      Process.put(@busy, true)

      try do
        case Ecto.Adapters.SQL.query(
               Palee.Repo,
               "SELECT current_setting('app.organization_id', true), current_setting('app.user_id', true)",
               []
             ) do
          {:ok, %{rows: [[org, user]]}} when org in [nil, ""] and user in [nil, ""] ->
            :ets.insert(@table, {source, frame()})

          {:ok, %{rows: [[org, _user]]}} when org in [nil, ""] ->
            if source in tenant_only_tables(),
              do: :ets.insert(@table, {source <> " (user scope only)", frame()})

          _scoped_or_failed ->
            :ok
        end
      rescue
        _error -> :ok
      after
        Process.delete(@busy)
      end
    end
  end

  def handle(_event, _measurements, _metadata, _config), do: :ok

  defp rls_tables do
    case :persistent_term.get({__MODULE__, :tables}, nil) do
      nil ->
        %{rows: rows} =
          Ecto.Adapters.SQL.query!(
            Palee.Repo,
            "SELECT relname::text FROM pg_class WHERE relkind = 'r' AND relrowsecurity AND relforcerowsecurity",
            []
          )

        tables = rows |> List.flatten() |> MapSet.new()
        :persistent_term.put({__MODULE__, :tables}, tables)
        tables

      tables ->
        tables
    end
  end

  # Tables whose policies only ever admit rows by the session organization.
  defp tenant_only_tables do
    case :persistent_term.get({__MODULE__, :tenant_only}, nil) do
      nil ->
        %{rows: rows} =
          Ecto.Adapters.SQL.query!(
            Palee.Repo,
            """
            SELECT tablename::text FROM pg_policies
            GROUP BY tablename
            HAVING bool_and(coalesce(qual, '') NOT LIKE '%app.user_id%'
                            AND coalesce(qual, '') NOT LIKE '%palee_%')
            """,
            []
          )

        tables = rows |> List.flatten() |> MapSet.new()
        :persistent_term.put({__MODULE__, :tenant_only}, tables)
        tables

      tables ->
        tables
    end
  end

  defp frame do
    {:current_stacktrace, stack} = Process.info(self(), :current_stacktrace)

    stack
    |> Enum.filter(fn {module, _fun, _arity, location} ->
      file = to_string(location[:file] || "")

      String.starts_with?(Atom.to_string(module), "Elixir.Palee") and
        String.starts_with?(file, "lib/") and not String.contains?(file, "infrastructure/") and
        module != __MODULE__
    end)
    |> Enum.take(3)
    |> Enum.map_join(" <- ", fn {module, fun, arity, location} ->
      "#{inspect(module)}.#{fun}/#{arity}:#{location[:line]}"
    end)
  end

  defp report do
    hits = :ets.tab2list(@table)

    unless hits == [] do
      IO.puts("\n== TD-092 unscoped RLS queries during requests (#{length(hits)}) ==")

      hits
      |> Enum.frequencies()
      |> Enum.sort_by(fn {{source, frame}, _count} -> {frame, source} end)
      |> Enum.each(fn {{source, frame}, count} ->
        IO.puts("#{count}x #{source}: #{frame}")
      end)
    end
  end
end
