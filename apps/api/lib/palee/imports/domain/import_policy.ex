defmodule Palee.Imports.Domain.ImportPolicy do
  @moduledoc """
  ADR-254: the rules of one import. Pure.

  Life of an import:

      draft ──apply──▶ queued ──▶ applying ──▶ applied
        │                               └────▶ failed   (the job stopped)
        └─delete (never applied)
      applied | failed ──apply again──▶ queued   (rows already applied are skipped)
      applied | failed ──undo (7 days)──▶ undone

  The mapping, the date order and the default role can change only while
  the import is a draft: once a row is applied, a retry must read every
  row the same way.
  """

  alias Palee.Imports.Domain.{DateParser, Fields}

  @max_bytes 5 * 1024 * 1024
  @max_rows 20_000
  @max_invitations 200
  @undo_days 7
  @preview_rows 50

  @statuses ~w(draft queued applying applied failed undone)
  @row_statuses ~w(pending applied skipped failed undone)
  @outcomes ~w(create_person update_person already_imported duplicate_row invalid)
  @warnings ~w(invalid_email invalid_phone invalid_date invalid_amount invalid_role
               invalid_status negative_balance payment_without_date package_created
               subscription_exists visit_exists credit_already_imported not_a_client
               undecodable_bytes)
  @errors ~w(missing_person missing_name)
  @roles ~w(member athlete)

  def max_bytes, do: @max_bytes
  def max_rows, do: @max_rows
  def max_invitations, do: @max_invitations
  def undo_days, do: @undo_days
  def preview_rows, do: @preview_rows
  def statuses, do: @statuses
  def row_statuses, do: @row_statuses
  def outcomes, do: @outcomes
  def warnings, do: @warnings
  def errors, do: @errors
  def roles, do: @roles

  @doc "The public limits, for the upload screen."
  def limits,
    do: %{
      max_bytes: @max_bytes,
      max_rows: @max_rows,
      max_invitations: @max_invitations,
      undo_days: @undo_days
    }

  @doc "`:ok` or `{:error, :file_too_large | :empty_file}` for an upload's size."
  def check_size(0), do: {:error, :empty_file}
  def check_size(bytes) when bytes > @max_bytes, do: {:error, :file_too_large}
  def check_size(_bytes), do: :ok

  def check_rows(0), do: {:error, :no_rows}
  def check_rows(rows) when rows > @max_rows, do: {:error, :too_many_rows}
  def check_rows(_rows), do: :ok

  @doc """
  Validates a mapping (`[%{column, field}]`, field nil = ignored) against a
  header of `width` columns. `{:ok, [%{column, field}]}` with only mapped
  columns, or `{:error, :invalid_mapping}`.
  """
  def validate_mapping(mapping, width) when is_list(mapping) and is_integer(width) do
    mapped =
      mapping
      |> Enum.map(fn entry -> {get(entry, :column), get(entry, :field)} end)
      |> Enum.reject(fn {_column, field} -> field in [nil, ""] end)

    columns = Enum.map(mapped, &elem(&1, 0))
    fields = Enum.map(mapped, &elem(&1, 1))

    valid? =
      Enum.all?(columns, &(is_integer(&1) and &1 >= 0 and &1 < width)) and
        Enum.all?(fields, &(&1 in Fields.keys())) and
        Enum.uniq(fields) == fields and Enum.uniq(columns) == columns and
        Enum.any?(fields, &(&1 in Fields.identity_keys()))

    if valid?,
      do: {:ok, mapped |> Enum.sort() |> Enum.map(fn {c, f} -> %{column: c, field: f} end)},
      else: {:error, :invalid_mapping}
  end

  def validate_mapping(_mapping, _width), do: {:error, :invalid_mapping}

  @doc "Import options: `date_order` and the role of people without one."
  def validate_options(options) when is_map(options) do
    date_order = get(options, :date_order)
    default_role = get(options, :default_role)

    cond do
      date_order not in DateParser.orders() -> {:error, :invalid_date_order}
      default_role not in @roles -> {:error, :invalid_default_role}
      true -> {:ok, %{date_order: date_order, default_role: default_role}}
    end
  end

  # ── Transitions ────────────────────────────────────────────────────────

  def editable?(%{status: "draft"}), do: true
  def editable?(_import), do: false

  @doc "Apply (or apply again after a stop): `:ok` or `{:error, :import_not_applicable}`."
  def can_apply(%{status: status}) when status in ~w(draft applied failed), do: :ok
  def can_apply(_import), do: {:error, :import_not_applicable}

  def can_delete(%{status: "draft"}), do: :ok
  def can_delete(_import), do: {:error, :import_already_applied}

  @doc "Undo is possible for #{@undo_days} days after the import finished."
  def can_undo(%{status: status, finished_at: %DateTime{} = finished_at}, %DateTime{} = now)
      when status in ~w(applied failed) do
    if DateTime.compare(now, undo_until(finished_at)) == :gt,
      do: {:error, :undo_window_closed},
      else: :ok
  end

  def can_undo(%{status: "undone"}, _now), do: {:error, :import_already_undone}
  def can_undo(_import, _now), do: {:error, :import_not_applied}

  def undo_until(%DateTime{} = finished_at), do: DateTime.add(finished_at, @undo_days * 86_400)
  def undo_until(_finished_at), do: nil

  def can_invite(%{status: status}) when status in ~w(applied failed), do: :ok
  def can_invite(_import), do: {:error, :import_not_applied}

  @doc "At most #{@max_invitations} invitations per call."
  def invitation_batch(requested) when is_integer(requested) and requested > 0,
    do: min(requested, @max_invitations)

  def invitation_batch(_requested), do: @max_invitations

  @doc "The status an import ends in after the job: failed rows do not fail it."
  def finished_status(:completed), do: "applied"
  def finished_status(:stopped), do: "failed"

  defp get(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp get(_value, _key), do: nil
end
