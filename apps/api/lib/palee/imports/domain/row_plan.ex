defmodule Palee.Imports.Domain.RowPlan do
  @moduledoc """
  ADR-254: what one row means and what applying it does. Pure.

    * `read/3` turns the row's cells into typed values through the mapping;
      a cell that cannot be read is dropped with a warning, never guessed;
    * `fingerprint/1` identifies the row by its values (not its position),
      so the same row in a retry or in a re-uploaded file is recognised and
      applied once;
    * `plan/3` decides the outcome and the actions from the values and the
      facts the caller looked up (who the person is, what already exists).

  Actions, in the order they are applied: `create_person` or
  `match_person`, `finance_profile`, `create_package`, `assign_package`,
  `credit`, `payment`, `visit`.
  """

  alias Palee.Imports.Domain.{DateParser, Fields, Values}

  @type warning :: %{code: String.t(), field: String.t() | nil}

  @doc """
  `%{values, warnings}`: `values` maps field keys to typed values (dates as
  `Date`, money as integer cents) and always has `name` (the display name,
  or nil) and `role`.
  """
  def read(cells, mapping, %{date_order: date_order, default_role: default_role}) do
    {values, warnings} =
      Enum.reduce(mapping, {%{}, []}, fn %{column: column, field: field}, {values, warnings} ->
        cell = Enum.at(cells, column)

        case read_cell(Fields.type(field), cell, date_order) do
          {:ok, value} -> {Map.put(values, field, value), warnings}
          :blank -> {values, warnings}
          {:error, code} -> {values, [warning(code, field) | warnings]}
        end
      end)

    values =
      values
      |> Map.put("name", display_name(values))
      |> Map.put_new("role", default_role)

    {values, warnings} = sanity(values, warnings)
    %{values: values, warnings: Enum.reverse(warnings)}
  end

  defp read_cell("text", cell, _order), do: Values.text(cell)
  defp read_cell("email", cell, _order), do: Values.email(cell)
  defp read_cell("phone", cell, _order), do: Values.phone(cell)
  defp read_cell("role", cell, _order), do: Values.role(cell)
  defp read_cell("status", cell, _order), do: Values.membership_status(cell)
  defp read_cell("payment_method", cell, _order), do: Values.payment_method(cell)
  defp read_cell("money", cell, _order), do: Values.money(cell)
  defp read_cell("date", cell, order), do: DateParser.parse(cell, order)

  defp display_name(values) do
    full = values["full_name"]
    parts = [values["first_name"], values["last_name"]] |> Enum.reject(&is_nil/1)

    cond do
      is_binary(full) -> full
      parts != [] -> Enum.join(parts, " ")
      true -> nil
    end
  end

  # Values that read fine but cannot be used as they are.
  defp sanity(values, warnings) do
    {values, warnings}
    |> drop_if("credit_balance", &(&1 < 0), "negative_balance")
    |> drop_if("payment_amount", &(&1 <= 0), "invalid_amount")
    |> drop_if("package_price", &(&1 < 0), "invalid_amount")
    |> then(fn {values, warnings} ->
      if Map.has_key?(values, "payment_amount") and not Map.has_key?(values, "payment_date"),
        do: {values, [warning("payment_without_date", "payment_date") | warnings]},
        else: {values, warnings}
    end)
  end

  defp drop_if({values, warnings}, field, bad?, code) do
    case Map.fetch(values, field) do
      {:ok, value} ->
        if bad?.(value),
          do: {Map.delete(values, field), [warning(code, field) | warnings]},
          else: {values, warnings}

      :error ->
        {values, warnings}
    end
  end

  def warning(code, field \\ nil), do: %{code: to_string(code), field: field}

  @doc "SHA-256 (hex) of the row's values in a canonical form."
  def fingerprint(values) when is_map(values) do
    canonical =
      values
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Enum.sort()
      |> Enum.map_join("\u001F", fn {key, value} -> "#{key}=#{canonical(value)}" end)

    :crypto.hash(:sha256, canonical) |> Base.encode16(case: :lower)
  end

  defp canonical(%Date{} = date), do: Date.to_iso8601(date)
  defp canonical(value) when is_binary(value), do: Values.fold(value)
  defp canonical(value), do: to_string(value)

  @doc """
  Who the row's person is, from `index` (what the caller knows of the
  business, all keys optional):

    * `members` – `%{user_id => client?}` of the active members;
    * `profiles_by_email` – `%{email => [user_id]}` of every login;
    * `people_by_email`, `people_by_phone` – `%{key => user_id}` of the
      people imports brought in before;
    * `planned_by_email`, `planned_by_phone` – `%{key => row_number}` of
      people earlier rows of this file will create.

  Email first, then phone: a member of the business with that email; a
  person imported before with that email; then with that phone (last 10
  digits); then a person an earlier row creates. An email of a Palee
  account that is not in the business matches nobody: the import never
  tells staff which addresses have an account (ADR-211), and never adds
  someone's own account to a business without them.
  """
  def match(values, index) do
    email = values["email"]
    phone = values["phone"] && Values.phone_key(values["phone"])
    members = index[:members] || %{}

    member =
      email &&
        Enum.find(
          Map.get(index[:profiles_by_email] || %{}, email, []),
          &Map.has_key?(members, &1)
        )

    imported =
      (email && get_in(index, [:people_by_email, email])) ||
        (phone && get_in(index, [:people_by_phone, phone]))

    planned =
      (email && get_in(index, [:planned_by_email, email])) ||
        (phone && get_in(index, [:planned_by_phone, phone]))

    cond do
      member -> {:member, member, Map.fetch!(members, member)}
      imported && Map.has_key?(members, imported) -> {:member, imported, members[imported]}
      imported -> {:imported, imported}
      planned -> {:planned, planned}
      true -> :new
    end
  end

  @doc """
  The plan of one row. `facts`:

    * `:person` – `{:member, user_id, client?}` (already in the business),
      `{:imported, user_id}` (imported before, matched by email or phone),
      `{:planned, row_number}` (created by an earlier row of this file) or
      `:new`;
    * `:already_imported?` – a row with this fingerprint was applied;
    * `:duplicate_of` – an earlier row of this file has this fingerprint;
    * `:package_exists?` – a package of this name exists;
    * `:subscription_exists?`, `:visit_exists?`, `:credit_imported?`
      (known when applying; false in a dry run).

  `%{outcome, actions, warnings, errors}`.
  """
  def plan(values, facts, warnings \\ []) do
    cond do
      facts[:already_imported?] ->
        result("already_imported", [], warnings, [])

      facts[:duplicate_of] ->
        result("duplicate_row", [], warnings, [])

      true ->
        person_plan(values, facts, warnings)
    end
  end

  defp person_plan(values, facts, warnings) do
    identified? =
      Enum.any?(~w(email phone name), &(not is_nil(values[&1]))) or
        not is_nil(values["external_id"])

    named? = not is_nil(values["name"])

    case facts[:person] || :new do
      _any when not identified? ->
        result("invalid", [], warnings, [warning("missing_person")])

      :new when not named? ->
        result("invalid", [], warnings, [warning("missing_name", "full_name")])

      :new ->
        {actions, warnings} = finance_actions(values, facts, true, warnings)
        result("create_person", [:create_person | actions], warnings, [])

      {:planned, _row} ->
        {actions, warnings} = finance_actions(values, facts, true, warnings)
        result("update_person", [:match_person | actions], warnings, [])

      {:imported, _user_id} ->
        {actions, warnings} = finance_actions(values, facts, true, warnings)
        result("update_person", [:match_person | actions], warnings, [])

      {:member, _user_id, client?} ->
        {actions, warnings} = finance_actions(values, facts, client?, warnings)
        result("update_person", [:match_person | actions], warnings, [])
    end
  end

  defp finance_actions(values, facts, client?, warnings) do
    finance? =
      Enum.any?(
        ~w(package_name credit_balance payment_amount membership_status notes joined_on),
        &Map.has_key?(values, &1)
      )

    cond do
      not client? and (finance? or Map.has_key?(values, "visit_date")) ->
        {[], warnings ++ [warning("not_a_client")]}

      true ->
        {package_actions, warnings} = package_actions(values, facts, warnings)
        {credit_actions, warnings} = credit_actions(values, facts, warnings)

        visit_actions =
          cond do
            not Map.has_key?(values, "visit_date") -> []
            facts[:visit_exists?] -> []
            true -> [:visit]
          end

        warnings =
          if Map.has_key?(values, "visit_date") and facts[:visit_exists?],
            do: warnings ++ [warning("visit_exists", "visit_date")],
            else: warnings

        payment = if Map.has_key?(values, "payment_amount"), do: [:payment], else: []

        actions =
          [:finance_profile] ++ package_actions ++ credit_actions ++ payment ++ visit_actions

        {actions, warnings}
    end
  end

  defp package_actions(values, facts, warnings) do
    cond do
      not Map.has_key?(values, "package_name") ->
        {[], warnings}

      facts[:subscription_exists?] ->
        {[], warnings ++ [warning("subscription_exists", "package_name")]}

      facts[:package_exists?] ->
        {[:assign_package], warnings}

      true ->
        {[:create_package, :assign_package],
         warnings ++ [warning("package_created", "package_name")]}
    end
  end

  defp credit_actions(values, facts, warnings) do
    cond do
      not Map.has_key?(values, "credit_balance") or values["credit_balance"] == 0 ->
        {[], warnings}

      facts[:credit_imported?] ->
        {[], warnings ++ [warning("credit_already_imported", "credit_balance")]}

      true ->
        {[:credit], warnings}
    end
  end

  defp result(outcome, actions, warnings, errors),
    do: %{outcome: outcome, actions: actions, warnings: warnings, errors: errors}

  @doc "The subscription status a package's dates give on `today`."
  def subscription_status(%{"package_ends_on" => %Date{} = ends_on}, %Date{} = today) do
    if Date.compare(ends_on, today) == :lt, do: "expired", else: "active"
  end

  def subscription_status(_values, _today), do: "active"
end
