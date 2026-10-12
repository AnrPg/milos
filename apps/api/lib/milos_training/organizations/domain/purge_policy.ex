defmodule MilosTraining.Organizations.Domain.PurgePolicy do
  @moduledoc """
  Pure state machine and guards for the reviewed tenant purge workflow
  (ADR-117).

      requested -> exporting -> exported -> approved -> purging -> completed
                       |                                  |
                       +------------> failed <------------+
      requested | exported | failed(export) -> cancelled
  """

  @statuses [
    :requested,
    :exporting,
    :exported,
    :approved,
    :purging,
    :completed,
    :failed,
    :cancelled
  ]
  @open_statuses @statuses -- [:completed, :cancelled]
  @irreversible_statuses [:approved, :purging]

  def statuses, do: @statuses
  def open_statuses, do: @open_statuses

  def open?(%{status: status}), do: status in @open_statuses
  def open?(_purge), do: false

  @doc "Validates a workflow event against the purge's current state."
  def transition(%{status: :requested}, :start_export), do: {:ok, :exporting}
  def transition(%{status: :exporting}, :start_export), do: {:ok, :exporting}

  def transition(%{status: :failed, failed_stage: "export"}, :start_export),
    do: {:ok, :exporting}

  def transition(%{status: :exporting}, :complete_export), do: {:ok, :exported}
  def transition(%{status: :exported}, :approve), do: {:ok, :approved}
  def transition(%{status: :approved}, :start_purge), do: {:ok, :purging}
  def transition(%{status: :purging}, :start_purge), do: {:ok, :purging}
  def transition(%{status: :failed, failed_stage: "purge"}, :start_purge), do: {:ok, :purging}
  def transition(%{status: :purging}, :complete), do: {:ok, :completed}
  def transition(%{status: :exporting}, :fail), do: {:ok, :failed}
  def transition(%{status: :purging}, :fail), do: {:ok, :failed}

  def transition(%{status: status}, :cancel) when status in [:requested, :exported],
    do: {:ok, :cancelled}

  def transition(%{status: :failed, failed_stage: "export"}, :cancel), do: {:ok, :cancelled}
  def transition(_purge, _event), do: {:error, :invalid_purge_transition}

  @doc """
  Which background stage a resume/retry re-enqueues. Both stages are
  idempotent, so resuming a stage whose job died mid-way is safe.
  """
  def resume_stage(%{status: status}) when status in [:requested, :exporting], do: {:ok, :export}
  def resume_stage(%{status: :failed, failed_stage: "export"}), do: {:ok, :export}
  def resume_stage(%{status: status}) when status in [:approved, :purging], do: {:ok, :purge}
  def resume_stage(%{status: :failed, failed_stage: "purge"}), do: {:ok, :purge}
  def resume_stage(_purge), do: {:error, :invalid_purge_transition}

  @doc """
  The explicit typed confirmation: the approver must retype the organization's
  slug exactly (surrounding whitespace ignored).
  """
  def verify_confirmation(slug, typed) when is_binary(slug) and is_binary(typed) do
    if String.trim(typed) == slug, do: :ok, else: {:error, :purge_confirmation_mismatch}
  end

  def verify_confirmation(_slug, _typed), do: {:error, :purge_confirmation_mismatch}

  @doc "Records whether a second vendor reviewed the purge or the requester self-approved."
  def approval_mode(requested_by, approved_by) when requested_by == approved_by,
    do: "typed_confirmation"

  def approval_mode(_requested_by, _approved_by), do: "second_vendor"

  @doc """
  Guards organization lifecycle changes while a purge is open: an approved or
  running purge cannot be interrupted at all, and an open (not yet approved)
  purge must be cancelled explicitly before the tenant is reactivated.
  """
  def lifecycle_change_allowed(nil, _target_status), do: :ok

  def lifecycle_change_allowed(%{status: status}, _target_status)
      when status in @irreversible_statuses,
      do: {:error, :organization_purge_in_progress}

  def lifecycle_change_allowed(%{status: status}, :active) when status in @open_statuses,
    do: {:error, :organization_purge_in_progress}

  def lifecycle_change_allowed(_purge, _target_status), do: :ok

  @doc "Lifecycle status an organization takes when a purge is requested."
  def requested_lifecycle_status(:active), do: :suspended
  def requested_lifecycle_status(status), do: status

  def step_completed?(steps, name) when is_map(steps),
    do: get_in(steps, [to_string(name), "status"]) == "completed"

  def step_completed?(_steps, _name), do: false

  def put_step(steps, name, result, %DateTime{} = at) when is_map(steps) and is_map(result) do
    Map.put(
      steps,
      to_string(name),
      result
      |> stringify_keys()
      |> Map.put("status", "completed")
      |> Map.put("completed_at", DateTime.to_iso8601(at))
    )
  end

  @doc "Short, PII-free failure reason for the audit record."
  def failure_reason(reason) when is_atom(reason), do: Atom.to_string(reason)

  def failure_reason({reason, _detail}) when is_atom(reason), do: Atom.to_string(reason)
  def failure_reason(%{__struct__: module}), do: inspect(module)
  def failure_reason(_reason), do: "unexpected_failure"

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_map(value) and not is_struct(value) ->
        {to_string(key), stringify_keys(value)}

      {key, value} ->
        {to_string(key), value}
    end)
  end
end
