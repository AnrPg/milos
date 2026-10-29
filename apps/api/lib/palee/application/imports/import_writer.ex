defmodule Palee.Application.Imports.ImportWriter do
  @moduledoc """
  ADR-254: what applying and undoing an import writes, through the services
  of the contexts that own the data. Each row is applied in its own
  transaction with the row locked; any failure rolls the whole row back
  and marks it `failed`, so a retry applies it from scratch.

  Applying re-plans every row against the business as it is now (the dry
  run may be old): people are matched by email, then phone, among the
  business's members and the people imports brought in before.

  What a row writes:

    * a new person: a *held* profile (`Identity.register_held_person/2`),
      the membership without any announcement
      (`Organizations.add_imported_membership/2`) and the record in
      `imported_people`;
    * the finance profile when the person has none (`UpdateFinanceMember`);
    * the package, created when no package has its name
      (`CreateFinancePackage`), and the subscription
      (`AssignFinanceMemberPackage`) at the row's price and dates;
    * a credit balance once per person (`Finance.create_manual_credit/3`);
    * a payment as history only, without a fiscal document
      (`Finance.record_payment/3`);
    * a visit as a check-in with the method `imported`.
  """

  alias Palee.Application.{AssignFinanceMemberPackage, CreateFinancePackage, UpdateFinanceMember}
  alias Palee.{Facility, Finance, Identity, Imports, Organizations}
  alias Palee.Imports.Domain.{RowPlan, Values}

  @batch 200
  @placeholder_domain "import.palee.invalid"

  # ── Applying ────────────────────────────────────────────────────────────

  @doc "Applies every pending or failed row of `import`, in row order."
  def apply_rows(context, import) do
    with {:ok, mapped} <- Imports.mapped_columns(import) do
      Stream.unfold(0, fn after_row ->
        case Imports.rows(context, import.id, %{
               status: ["pending", "failed"],
               after_row: after_row,
               limit: @batch
             }) do
          [] -> nil
          batch -> {batch, List.last(batch).row_number}
        end
      end)
      |> Stream.flat_map(& &1)
      |> Enum.each(&apply_row(context, import, mapped, &1))

      :ok
    end
  end

  defp apply_row(context, import, mapped, row) do
    read = Imports.read_row(import, mapped, row)

    result =
      Imports.transaction(context, fn ->
        case Imports.lock_row(context, row.id) do
          %{status: status} = locked when status in ["pending", "failed"] ->
            apply_locked(context, import, locked, read)

          %{} ->
            {:ok, :done}

          nil ->
            {:error, :not_found}
        end
      end)

    case result do
      {:ok, _done} ->
        :ok

      {:error, reason} ->
        {:ok, _row} =
          Imports.update_row(context, row.id, %{
            status: "failed",
            fingerprint: read.fingerprint,
            error_code: error_code(reason)
          })

        :failed
    end
  end

  defp apply_locked(context, import, row, read) do
    values = read.values

    if Imports.applied?(context, read.fingerprint) do
      finish(context, row, read, %{
        outcome: "already_imported",
        warnings: read.warnings,
        errors: []
      })
    else
      index = live_index(context, values)
      match = RowPlan.match(values, index)
      user_id = matched_user(match)
      profile = user_id && Finance.get_member_profile(context, user_id)
      package = find_package(context, values["package_name"])
      person = user_id && Imports.find_person(context, :user_id, user_id)
      today = Organizations.local_today(context.organization_id, Imports.now())

      facts = %{
        person: match,
        package_exists?: not is_nil(package),
        subscription_exists?: subscription_exists?(profile, package, values),
        visit_exists?: visit_exists?(context, user_id, values["visit_date"]),
        credit_imported?: not is_nil(person && person.credit_entry_id)
      }

      plan = RowPlan.plan(values, facts, read.warnings)

      if plan.outcome in ~w(invalid already_imported duplicate_row) do
        finish(context, row, read, plan)
      else
        state = %{
          context: context,
          import: import,
          row: row,
          read: read,
          values: values,
          user_id: user_id,
          profile: profile,
          package: package,
          person: person,
          index: index,
          today: today,
          result: %{}
        }

        with {:ok, state} <- run_actions(plan.actions, state) do
          finish(context, row, read, plan, state)
        end
      end
    end
  end

  defp finish(context, row, read, plan, state \\ nil) do
    applied? = not is_nil(state)

    Imports.update_row(context, row.id, %{
      status: if(applied?, do: "applied", else: "skipped"),
      outcome: plan.outcome,
      fingerprint: read.fingerprint,
      warnings: plan.warnings,
      errors: plan.errors,
      error_code: nil,
      result: if(applied?, do: state.result, else: %{}),
      user_id: state && state.user_id,
      applied_at: if(applied?, do: Imports.now())
    })
  end

  defp run_actions(actions, state) do
    Enum.reduce_while(actions, {:ok, state}, fn action, {:ok, state} ->
      case action(action, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, reason} -> {:halt, {:error, {action, reason}}}
      end
    end)
  end

  # ── Actions ─────────────────────────────────────────────────────────────

  defp action(:create_person, %{context: context, values: values} = state) do
    role = values["role"]

    with {:ok, account} <-
           Identity.register_held_person(context.organization_id, account_params(state)),
         {:ok, _membership} <-
           Organizations.add_imported_membership(context, %{
             user_id: account.id,
             role: String.to_existing_atom(role),
             roles: [String.to_existing_atom(role)],
             status: :active,
             joined_at: joined_at(values, state),
             invited_by_user_id: context.user_id
           }),
         {:ok, person} <-
           Imports.save_person(context, %{
             user_id: account.id,
             import_id: state.import.id,
             created_profile: true,
             name: values["name"],
             email: values["email"],
             phone_key: Values.phone_key(values["phone"]),
             external_id: values["external_id"]
           }) do
      {:ok,
       %{
         state
         | user_id: account.id,
           person: person,
           result:
             Map.merge(state.result, %{"created_profile" => true, "membership_added" => true})
       }}
    end
  end

  defp action(:match_person, %{context: context, values: values, user_id: user_id} = state) do
    with {:ok, added?} <- ensure_membership(context, user_id, values, state),
         {:ok, person} <- remember_person(context, state) do
      {:ok,
       %{
         state
         | person: person,
           result: Map.merge(state.result, %{"membership_added" => added?})
       }}
    end
  end

  defp action(:finance_profile, %{context: context, user_id: user_id, values: values} = state) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: membership} = profile ->
        {:ok, %{state | profile: profile} |> put_result("membership_id", membership.id)}

      nil ->
        params =
          %{
            "status" => values["membership_status"] || "active",
            "signup_source" => "imported",
            "notes" => values["notes"],
            "starts_on" => values["joined_on"]
          }
          |> Map.reject(fn {_key, value} -> is_nil(value) end)

        with {:ok, membership} <- UpdateFinanceMember.call(context, user_id, params) do
          {:ok,
           state
           |> put_result("membership_id", membership.id)
           |> put_result("finance_profile_created", true)}
        end
    end
  end

  defp action(:create_package, %{context: context, values: values} = state) do
    params = %{
      name: String.slice(values["package_name"], 0, 120),
      package_type: "membership",
      base_price_cents: values["package_price"] || 0
    }

    with {:ok, package} <- CreateFinancePackage.call(context, params) do
      {:ok, %{state | package: package} |> put_result("package_created", true)}
    end
  end

  defp action(:assign_package, %{context: context, values: values, package: package} = state) do
    starts_on = values["package_starts_on"] || values["joined_on"] || state.today

    params =
      %{
        "membership_package_id" => package.id,
        "starts_on" => starts_on,
        "ends_on" => values["package_ends_on"],
        "status" => RowPlan.subscription_status(values, state.today),
        "signup_source" => "imported"
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    opts = if values["package_price"], do: [price_cents: values["package_price"]], else: []

    with {:ok, subscription} <-
           AssignFinanceMemberPackage.call(context, state.user_id, params, opts) do
      {:ok,
       state
       |> put_result("package_id", package.id)
       |> put_result("subscription_id", subscription.id)}
    end
  end

  defp action(:credit, %{context: context, values: values} = state) do
    amount = values["credit_balance"]

    with {:ok, entry} <-
           Finance.create_manual_credit(context, state.result["membership_id"], %{
             "amount_cents" => amount,
             "request_id" => derived_uuid(state.read.fingerprint, "credit"),
             "description" => "Imported balance",
             "created_by_id" => context.user_id
           }),
         {:ok, person} <-
           Imports.update_person(context, state.person.id, %{credit_entry_id: entry.id}) do
      {:ok,
       %{state | person: person}
       |> put_result("credit_entry_id", entry.id)
       |> put_result("credit_cents", amount)}
    end
  end

  defp action(:payment, %{context: context, values: values} = state) do
    params = %{
      "amount_cents" => values["payment_amount"],
      "paid_on" => values["payment_date"] || state.today,
      "payment_method" => values["payment_method"] || "other",
      "payment_status" => "paid",
      "notes" => values["payment_note"] || "Imported",
      "params" => %{
        "source" => "import",
        "import_id" => state.import.id,
        "row_number" => state.row.row_number
      }
    }

    with {:ok, payment} <- Finance.record_payment(context, state.result["membership_id"], params) do
      {:ok, put_result(state, "payment_id", payment.id)}
    end
  end

  defp action(:visit, %{context: context, values: values} = state) do
    date = values["visit_date"]

    with {:ok, check_in} <-
           Facility.create_check_in(context, %{
             user_id: state.user_id,
             checked_in_on: date,
             checked_in_at: DateTime.new!(date, ~T[12:00:00.000000], "Etc/UTC"),
             source: "staff",
             method: "imported",
             recorded_by_id: context.user_id
           }) do
      {:ok, put_result(state, "check_in_id", check_in.id)}
    end
  end

  defp put_result(state, key, value), do: %{state | result: Map.put(state.result, key, value)}

  # ── People ──────────────────────────────────────────────────────────────

  defp account_params(%{context: context, values: values, index: index}) do
    email = values["email"]
    taken? = email && Map.has_key?(index[:profiles_by_email] || %{}, email)
    name = values["name"] |> String.slice(0, Identity.display_name_max_length()) |> String.trim()
    suffix = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)
    base = (Identity.suggest_handle(name) || "member") |> String.slice(0, 22) |> String.trim(".")

    %{
      handle: "#{base}_#{suffix}",
      display_name: name,
      password: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      role: values["role"],
      # A new address becomes the login, so proving the inbox claims the
      # profile; an address that already has a login (or none) gets a
      # placeholder that can never receive mail (RFC 2606).
      email: if(email && not taken?, do: email, else: placeholder_email()),
      preferred_locale: locale(context)
    }
  end

  defp placeholder_email, do: "held-#{Ecto.UUID.generate()}@#{@placeholder_domain}"

  defp locale(context) do
    settings = Organizations.get_organization_settings(context.organization_id)
    default = settings && settings.default_locale
    if default in Identity.supported_locales(), do: default, else: "en"
  end

  defp joined_at(values, state) do
    case values["joined_on"] do
      %Date{} = date -> DateTime.new!(date, ~T[00:00:00.000000], "Etc/UTC")
      nil -> DateTime.new!(state.today, ~T[00:00:00.000000], "Etc/UTC")
    end
  end

  defp ensure_membership(context, user_id, values, state) do
    if Organizations.member_roles(context.organization_id, user_id) == [] do
      role = String.to_existing_atom(values["role"])

      with {:ok, _membership} <-
             Organizations.add_imported_membership(context, %{
               user_id: user_id,
               role: role,
               roles: [role],
               status: :active,
               joined_at: joined_at(values, state),
               invited_by_user_id: context.user_id
             }),
           do: {:ok, true}
    else
      {:ok, false}
    end
  end

  defp remember_person(context, %{person: nil, values: values, user_id: user_id} = state) do
    Imports.save_person(context, %{
      user_id: user_id,
      import_id: state.import.id,
      created_profile: false,
      name: values["name"],
      email: values["email"],
      phone_key: Values.phone_key(values["phone"]),
      external_id: values["external_id"]
    })
  end

  defp remember_person(context, %{person: person, values: values}) do
    changes =
      %{
        email: person.email || values["email"],
        phone_key: person.phone_key || Values.phone_key(values["phone"]),
        name: person.name || values["name"],
        external_id: person.external_id || values["external_id"],
        removed_at: nil
      }

    Imports.update_person(context, person.id, changes)
  end

  @doc "What the business knows about one row's person, fresh (see `RowPlan.match/2`)."
  def live_index(context, values) do
    email = values["email"]
    phone = Values.phone_key(values["phone"])
    profiles = if email, do: Identity.profiles_by_emails([email]), else: %{}
    profiles_by_email = Map.new(profiles, fn {key, list} -> {key, Enum.map(list, & &1.id)} end)

    by_email = email && Imports.find_person(context, :email, email)
    by_phone = phone && Imports.find_person(context, :phone_key, phone)

    candidates =
      (Map.get(profiles_by_email, email, []) ++
         Enum.map(Enum.reject([by_email, by_phone], &is_nil/1), & &1.user_id))
      |> Enum.uniq()

    members =
      Enum.reduce(candidates, %{}, fn user_id, acc ->
        case Organizations.member_roles(context.organization_id, user_id) do
          [] -> acc
          roles -> Map.put(acc, user_id, client_roles?(roles))
        end
      end)

    %{
      members: members,
      profiles_by_email: profiles_by_email,
      people_by_email: if(by_email, do: %{email => by_email.user_id}, else: %{}),
      people_by_phone: if(by_phone, do: %{phone => by_phone.user_id}, else: %{})
    }
  end

  @doc "Whether a role set holds a client role (member or athlete, ADR-217)."
  def client_roles?(roles), do: Enum.any?(roles, &(to_string(&1) in ["member", "athlete"]))

  defp matched_user({:member, user_id, _client?}), do: user_id
  defp matched_user({:imported, user_id}), do: user_id
  defp matched_user(_match), do: nil

  # ── Lookups ─────────────────────────────────────────────────────────────

  defp find_package(_context, nil), do: nil

  defp find_package(context, name) do
    folded = Values.fold(name)

    context
    |> Finance.list_packages()
    |> Enum.filter(&(Values.fold(&1.name || "") == folded))
    |> Enum.sort_by(&if(&1.active, do: 0, else: 1))
    |> List.first()
  end

  defp subscription_exists?(nil, _package, _values), do: false
  defp subscription_exists?(_profile, nil, _values), do: false

  defp subscription_exists?(profile, package, values) do
    starts_on = values["package_starts_on"] || values["joined_on"]

    Enum.any?(profile.package_subscriptions || [], fn subscription ->
      subscription.membership_package_id == package.id and subscription.status != "cancelled" and
        (is_nil(starts_on) or subscription.starts_on == starts_on)
    end)
  end

  defp visit_exists?(_context, nil, _date), do: false
  defp visit_exists?(_context, _user_id, nil), do: false

  defp visit_exists?(context, user_id, %Date{} = date),
    do: not is_nil(Facility.get_check_in(context, user_id, date))

  # ── Undo ────────────────────────────────────────────────────────────────

  @doc """
  Reverses every applied row of `import`, newest first: deletes its visits,
  removes its payments from the history, reverses its credit, cancels its
  subscriptions, and revokes the memberships it added (closing the finance
  profiles it created). Packages it created stay (staff may retire them).
  `{:ok, %{undone, failed}}`.
  """
  def undo_rows(context, import) do
    rows =
      context
      |> Imports.rows(import.id, %{status: "applied", limit: :all})
      |> Enum.reverse()

    counts =
      Enum.reduce(rows, %{undone: 0, failed: 0}, fn row, counts ->
        case undo_row(context, row) do
          :ok -> Map.update!(counts, :undone, &(&1 + 1))
          _error -> Map.update!(counts, :failed, &(&1 + 1))
        end
      end)

    {:ok, counts}
  end

  defp undo_row(context, row) do
    Imports.transaction(context, fn ->
      case Imports.lock_row(context, row.id) do
        %{status: "applied", result: result} = locked ->
          with :ok <- undo_actions(context, locked, result) do
            Imports.update_row(context, locked.id, %{status: "undone"})
          end

        _other ->
          {:ok, :done}
      end
    end)
    |> case do
      {:ok, _row} -> :ok
      error -> error
    end
  end

  defp undo_actions(context, row, result) do
    membership_id = result["membership_id"]
    actor = context.user_id

    steps = [
      fn -> undo_visit(context, result["check_in_id"]) end,
      fn -> undo_payment(context, result["payment_id"], actor) end,
      fn -> undo_credit(context, row, membership_id, result) end,
      fn -> undo_subscription(context, membership_id, result["subscription_id"]) end,
      fn -> undo_membership(context, row, result) end
    ]

    Enum.reduce_while(steps, :ok, fn step, :ok ->
      case step.() do
        :ok -> {:cont, :ok}
        {:ok, _value} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp undo_visit(_context, nil), do: :ok

  defp undo_visit(context, check_in_id) do
    case Facility.delete_check_in(context, check_in_id) do
      {:error, :not_found} -> :ok
      other -> other
    end
  end

  defp undo_payment(_context, nil, _actor), do: :ok

  defp undo_payment(context, payment_id, actor) do
    case Finance.soft_delete_finance_record(context, "payment", payment_id, actor, %{
           "reason" => "Import undone"
         }) do
      {:error, :not_found} -> :ok
      other -> other
    end
  end

  defp undo_credit(_context, _row, _membership_id, %{"credit_entry_id" => nil}), do: :ok

  defp undo_credit(context, row, membership_id, %{"credit_entry_id" => entry_id} = result)
       when is_binary(entry_id) do
    with {:ok, _reversal} <-
           Finance.reverse_credit_grant(context, membership_id, entry_id, %{
             "amount_cents" => result["credit_cents"],
             "request_id" => derived_uuid(row.fingerprint, "undo-credit"),
             "reason" => "Import undone",
             "created_by_id" => context.user_id
           }) do
      case Imports.find_person(context, :user_id, row.user_id) do
        %{credit_entry_id: ^entry_id} = person ->
          Imports.update_person(context, person.id, %{credit_entry_id: nil})

        _other ->
          :ok
      end
    end
  end

  defp undo_credit(_context, _row, _membership_id, _result), do: :ok

  defp undo_subscription(_context, _membership_id, nil), do: :ok

  defp undo_subscription(context, membership_id, subscription_id),
    do: Finance.cancel_subscription(context, membership_id, subscription_id)

  defp undo_membership(context, %{user_id: user_id}, %{"membership_added" => true} = result)
       when is_binary(user_id) do
    with :ok <- close_finance_profile(context, user_id, result),
         {:ok, _membership} <- Organizations.remove_imported_membership(context, user_id) do
      case Imports.find_person(context, :user_id, user_id) do
        nil -> :ok
        person -> Imports.update_person(context, person.id, %{removed_at: Imports.now()})
      end
    end
  end

  defp undo_membership(_context, _row, _result), do: :ok

  defp close_finance_profile(context, user_id, %{"finance_profile_created" => true}) do
    case UpdateFinanceMember.call(context, user_id, %{
           "status" => "cancelled",
           "commitment_override_reason" => "Import undone"
         }) do
      {:ok, _membership} -> :ok
      error -> error
    end
  end

  defp close_finance_profile(_context, _user_id, _result), do: :ok

  # ── Helpers ─────────────────────────────────────────────────────────────

  @doc "A stable UUID for an idempotency key derived from `seed` and `purpose`."
  def derived_uuid(seed, purpose) do
    <<bytes::binary-size(16), _rest::binary>> = :crypto.hash(:sha256, "#{seed}:#{purpose}")
    Ecto.UUID.load!(bytes)
  end

  defp error_code({action, reason}) when is_atom(action),
    do: String.slice("#{action}:#{error_code(reason)}", 0, 120)

  defp error_code(%Ecto.Changeset{}), do: "invalid"
  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code({reason, _details}) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(_reason), do: "failed"
end
