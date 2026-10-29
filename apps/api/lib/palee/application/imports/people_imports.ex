defmodule Palee.Application.Imports.PeopleImports do
  @moduledoc """
  Staff › Settings › Import (ADR-254): moving people and their history in
  from a CSV file of another system.

  Upload → mapping → dry run → apply (a background job) → report →
  invitations (an explicit step; an import never emails anyone by itself)
  → undo within 7 days. A business still in demo mode may upload and run
  the dry run; applying and inviting answer `business_not_activated`
  (`GoLivePolicy` action `:import_people`).
  """

  alias Palee.Application.{GoLive, InvitationEmails}
  alias Palee.Application.Imports.ImportWriter
  alias Palee.{Finance, Identity, Imports, Organizations}
  alias Palee.Imports.Domain.{ImportPolicy, Values}
  alias Palee.Workers.ApplyImportJob

  @doc "Fields, presets, date orders, limits and the codes the screens show."
  def catalog, do: Imports.catalog()

  def list(context), do: context |> Imports.list(%{limit: 50}) |> Enum.map(&view/1)

  def show(context, id) do
    case Imports.get(context, id) do
      nil -> {:error, :not_found}
      import -> {:ok, view(import, Imports.row_counts(context, id))}
    end
  end

  @doc """
  Stores an upload. `upload` is a `Plug.Upload` (or `%{filename, path}`);
  `source` an optional preset key.
  """
  def upload(context, upload, source) do
    with {:ok, %{filename: filename, path: path}} <- uploaded_file(upload),
         {:ok, %{size: size}} <- File.stat(path),
         :ok <- ImportPolicy.check_size(size),
         {:ok, content} <- File.read(path),
         {:ok, import} <-
           Imports.upload(
             context,
             %{filename: filename, content: content, source: blank_to_nil(source)},
             Map.get(context, :user_id)
           ) do
      {:ok, view(import, Imports.row_counts(context, import.id))}
    else
      {:error, reason} when is_atom(reason) and reason in [:enoent, :eacces] ->
        {:error, :import_file_missing}

      other ->
        other
    end
  end

  defp uploaded_file(%{filename: filename, path: path}) when is_binary(path),
    do: {:ok, %{filename: filename || "import.csv", path: path}}

  defp uploaded_file(_upload), do: {:error, :import_file_missing}

  @doc "Rows by number; filters `status`, `outcome`, paging `after_row`, `limit` (≤ 500)."
  def rows(context, id, params) do
    with %{} <- Imports.get(context, id) || {:error, :not_found} do
      filters =
        %{
          status: one_of(param(params, :status), ImportPolicy.row_statuses()),
          outcome: one_of(param(params, :outcome), ImportPolicy.outcomes()),
          after_row: param(params, :after_row),
          limit: param(params, :limit) || 100
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)

      rows = Imports.rows(context, id, filters)

      {:ok,
       %{
         rows: Enum.map(rows, &row_view/1),
         next_after_row:
           if(length(rows) == filters.limit, do: List.last(rows).row_number, else: nil)
       }}
    end
  end

  @doc """
  Saves the mapping and options of a draft (all optional) and runs the dry
  run: every row's outcome and warnings, nothing written outside imports.
  """
  def preview(context, id, params) do
    with %{} = import <- Imports.get(context, id) || {:error, :not_found},
         {:ok, import} <- Imports.configure(context, import, settings(params)),
         {:ok, import} <-
           Imports.dry_run(context, import, &business_index(context, &1), Imports.now()) do
      {:ok, view(import, Imports.row_counts(context, id))}
    end
  end

  defp settings(params) do
    %{
      mapping: mapping(param(params, :mapping)),
      date_order: param(params, :date_order),
      default_role: param(params, :default_role)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp mapping(nil), do: nil

  defp mapping(entries) when is_list(entries),
    do: Enum.map(entries, &%{column: param(&1, :column), field: param(&1, :field)})

  defp mapping(_other), do: []

  # What the dry run needs to know of the business.
  defp business_index(context, emails) do
    members =
      context
      |> Organizations.member_roles_by_user()
      |> Map.new(fn {user_id, %{roles: roles}} ->
        {user_id, ImportWriter.client_roles?(roles)}
      end)

    profiles =
      emails
      |> Identity.profiles_by_emails()
      |> Map.new(fn {email, profiles} -> {email, Enum.map(profiles, & &1.id)} end)

    packages =
      context
      |> Finance.list_packages()
      |> MapSet.new(&Values.fold(&1.name || ""))

    %{members: members, profiles_by_email: profiles, package_names: packages}
  end

  @doc """
  Applies the import in a background job (202): each row once, in its own
  transaction. Calling it again after a stop applies only the rows not yet
  applied.
  """
  def apply(context, id) do
    now = Imports.now()

    with :ok <- GoLive.check(context, :import_people),
         {:ok, import} <-
           Imports.transaction(context, fn ->
             with %{} = import <- Imports.get_for_update(context, id) || {:error, :not_found},
                  :ok <- ImportPolicy.can_apply(import),
                  {:ok, _mapped} <- Imports.mapped_columns(import) do
               Imports.update(context, id, %{
                 status: "queued",
                 applied_by_id: Map.get(context, :user_id),
                 queued_at: now,
                 last_error: nil
               })
             end
           end) do
      schedule(context, import)
      show(context, id)
    end
  end

  defp schedule(context, import) do
    if Application.get_env(:palee, :start_oban, true) do
      %{
        "organization_id" => context.organization_id,
        "import_id" => import.id,
        "user_id" => context.user_id
      }
      |> ApplyImportJob.new()
      |> Oban.insert()

      :ok
    else
      run(context, import.id)
    end
  end

  @doc """
  The job's work: applies the rows as the person who started the import
  (their permissions still apply) and writes the report.
  """
  def run_as(organization_id, import_id, user_id) do
    with %{} = account <- Identity.find_by_id(user_id) || {:error, :actor_unavailable},
         {:ok, context} <- Organizations.resolve_tenant_context_by_id(account, organization_id) do
      run(context, import_id)
    else
      {:error, reason} ->
        fail_system(organization_id, import_id, reason)
    end
  end

  def run(context, import_id) do
    case start(context, import_id) do
      {:ok, import} ->
        try do
          :ok = ImportWriter.apply_rows(context, import)
          finish(context, import_id, :completed, nil)
        rescue
          exception ->
            finish(context, import_id, :stopped, Exception.message(exception))
            reraise exception, __STACKTRACE__
        end

      {:error, :not_queued} ->
        :ok

      error ->
        error
    end
  end

  defp start(context, import_id) do
    Imports.transaction(context, fn ->
      case Imports.get_for_update(context, import_id) do
        %{status: status} when status in ["queued", "applying"] ->
          Imports.update(context, import_id, %{status: "applying", started_at: Imports.now()})

        _other ->
          {:error, :not_queued}
      end
    end)
  end

  defp finish(context, import_id, outcome, error) do
    {:ok, _import} =
      Imports.update(context, import_id, %{
        status: ImportPolicy.finished_status(outcome),
        finished_at: Imports.now(),
        summary: summary(context, import_id),
        last_error: error && String.slice(error, 0, 500)
      })

    :ok
  end

  defp fail_system(organization_id, import_id, reason) do
    context = %{organization_id: organization_id}

    Imports.update(context, import_id, %{
      status: "failed",
      finished_at: Imports.now(),
      last_error: "actor_unavailable: #{inspect(reason)}"
    })

    :ok
  end

  # The report: what the rows did.
  defp summary(context, import_id) do
    counts = Imports.row_counts(context, import_id)
    applied = Imports.rows(context, import_id, %{status: "applied", limit: :all})
    results = Enum.map(applied, & &1.result)

    count = fn key -> Enum.count(results, &Map.get(&1, key)) end

    %{
      rows: counts.statuses,
      outcomes: counts.outcomes,
      people_created: count.("created_profile"),
      people_matched: Enum.count(applied, &(&1.outcome == "update_person")),
      memberships_added: count.("membership_added"),
      packages_created: count.("package_created"),
      subscriptions: count.("subscription_id"),
      credits: count.("credit_entry_id"),
      payments: count.("payment_id"),
      visits: count.("check_in_id")
    }
  end

  @doc """
  Emails an invitation to the people this import brought in who have an
  address and have not claimed their profile, at most 200 per call and
  within the daily invitation limits (ADR-209). `params`: `person_ids`
  (optional, else everyone not yet invited), `limit`.
  """
  def invite(context, id, params) do
    with :ok <- GoLive.check(context, :import_people),
         %{} = import <- Imports.get(context, id) || {:error, :not_found},
         :ok <- ImportPolicy.can_invite(import) do
      wanted = param(params, :person_ids)
      batch = ImportPolicy.invitation_batch(param(params, :limit))

      candidates =
        context
        |> Imports.people_of_import(id)
        |> Enum.filter(&invitable?(context, &1))
        |> Enum.filter(&(is_nil(wanted) or &1.id in wanted))

      {now, remaining} = Enum.split(candidates, batch)
      send_invitations(context, now, length(remaining))
    end
  end

  defp invitable?(context, person) do
    is_binary(person.email) and is_nil(person.invited_at) and is_nil(person.removed_at) and
      match?(
        %{held_by_organization_id: held} when held == context.organization_id,
        Identity.find_by_id(person.user_id)
      )
  end

  defp send_invitations(_context, [], remaining),
    do: {:ok, %{sent: 0, failed: 0, results: [], remaining: remaining}}

  defp send_invitations(context, people, remaining) do
    roles_by_user = Organizations.member_roles_by_user(context)

    groups =
      Enum.group_by(people, fn person ->
        roles = get_in(roles_by_user, [person.user_id, :roles]) || ["member"]
        if Enum.any?(roles, &(to_string(&1) == "athlete")), do: "athlete", else: "member"
      end)

    Enum.reduce_while(groups, {:ok, []}, fn {role, group}, {:ok, results} ->
      emails = Enum.map(group, & &1.email)

      case InvitationEmails.bulk(context, %{"emails" => emails, "roles" => [role]}) do
        {:ok, %{results: sent}} ->
          {:cont, {:ok, results ++ record_invitations(context, group, sent)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} ->
        sent = Enum.count(results, &(&1.status == "queued"))

        {:ok,
         %{sent: sent, failed: length(results) - sent, results: results, remaining: remaining}}

      error ->
        error
    end
  end

  defp record_invitations(context, people, sent) do
    by_email = Map.new(sent, &{&1.email, &1})

    Enum.map(people, fn person ->
      case Map.get(by_email, person.email) do
        %{invitation_id: invitation_id} ->
          {:ok, _person} =
            Imports.update_person(context, person.id, %{
              invited_at: Imports.now(),
              invitation_id: invitation_id
            })

          %{person_id: person.id, email: person.email, status: "queued", error: nil}

        %{error: error} ->
          %{person_id: person.id, email: person.email, status: "failed", error: error}

        nil ->
          %{person_id: person.id, email: person.email, status: "failed", error: "invalid_address"}
      end
    end)
  end

  @doc "Reverses an applied import within 7 days of its end (see `ImportWriter.undo_rows/2`)."
  def undo(context, id) do
    now = Imports.now()

    with %{} = import <- Imports.get(context, id) || {:error, :not_found},
         :ok <- ImportPolicy.can_undo(import, now),
         {:ok, %{failed: failed}} <- ImportWriter.undo_rows(context, import),
         {:ok, _import} <-
           Imports.update(
             context,
             id,
             if(failed == 0,
               do: %{status: "undone", undone_at: now, undone_by_id: Map.get(context, :user_id)},
               else: %{last_error: "undo_incomplete: #{failed} rows"}
             )
           ) do
      if failed == 0, do: show(context, id), else: {:error, :undo_incomplete}
    end
  end

  @doc "Deletes an import that was never applied, with its rows."
  def delete(context, id) do
    with %{} = import <- Imports.get(context, id) || {:error, :not_found},
         :ok <- ImportPolicy.can_delete(import) do
      Imports.delete(context, id)
    end
  end

  # ── Views ───────────────────────────────────────────────────────────────

  @public ~w(id status source filename byte_size encoding delimiter header row_count mapping
             date_order default_role file_warnings preview previewed_at summary queued_at
             started_at finished_at undone_at last_error inserted_at)a

  defp view(import, counts \\ nil) do
    import
    |> Map.take(@public)
    |> Map.update!(:mapping, fn mapping -> Enum.map(mapping, &mapping_entry/1) end)
    |> Map.put(:undo_until, ImportPolicy.undo_until(import.finished_at))
    |> Map.put(:counts, counts)
  end

  defp mapping_entry(entry), do: %{column: param(entry, :column), field: param(entry, :field)}

  @row_public ~w(id row_number cells status outcome warnings errors result user_id error_code
                 applied_at)a

  defp row_view(row) do
    row
    |> Map.take(@row_public)
    |> Map.update!(:warnings, fn list -> Enum.map(list, &issue/1) end)
    |> Map.update!(:errors, fn list -> Enum.map(list, &issue/1) end)
  end

  defp issue(entry), do: %{code: param(entry, :code), field: param(entry, :field)}

  # ── Params ──────────────────────────────────────────────────────────────

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp param(_params, _key), do: nil

  defp one_of(nil, _allowed), do: nil
  defp one_of(value, allowed), do: if(value in allowed, do: value, else: nil)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
