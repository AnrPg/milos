defmodule MilosTraining.Organizations.OrganizationPurge do
  @moduledoc """
  Platform-level audit record of one reviewed tenant export/purge (ADR-099).

  The row intentionally has no foreign key to `organizations` or `users`: it
  must survive the purge it describes. It holds identifiers, counts, policies
  and object keys only - never tenant PII.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Organizations.Domain.PurgePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "organization_purges" do
    field :organization_id, :binary_id
    field :organization_slug, :string
    field :status, Ecto.Enum, values: PurgePolicy.statuses(), default: :requested
    field :failed_stage, :string
    field :failure_reason, :string
    field :requested_by_user_id, :binary_id
    field :requested_at, :utc_datetime_usec
    field :export_started_at, :utc_datetime_usec
    field :export_completed_at, :utc_datetime_usec
    field :export_key, :string
    field :export_byte_size, :integer
    field :export_sha256, :string
    field :retained_archive_key, :string
    field :retention_review, {:array, :map}, default: []
    field :approved_by_user_id, :binary_id
    field :approval_mode, :string
    field :approved_at, :utc_datetime_usec
    field :purge_started_at, :utc_datetime_usec
    field :steps, :map, default: %{}
    field :completed_at, :utc_datetime_usec
    field :cancelled_by_user_id, :binary_id
    field :cancelled_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @request_fields [:organization_id, :organization_slug, :requested_by_user_id, :requested_at]

  def request_changeset(params) do
    %__MODULE__{}
    |> cast(params, @request_fields)
    |> validate_required(@request_fields)
    |> put_change(:status, :requested)
    |> unique_constraint(:organization_id,
      name: :organization_purges_one_open_per_organization,
      message: "already has an open purge request"
    )
  end

  @progress_fields [
    :status,
    :failed_stage,
    :failure_reason,
    :export_started_at,
    :export_completed_at,
    :export_key,
    :export_byte_size,
    :export_sha256,
    :retained_archive_key,
    :retention_review,
    :approved_by_user_id,
    :approval_mode,
    :approved_at,
    :purge_started_at,
    :steps,
    :completed_at,
    :cancelled_by_user_id,
    :cancelled_at
  ]

  def progress_changeset(%__MODULE__{} = purge, params) do
    purge
    |> cast(params, @progress_fields)
    |> validate_required([:status])
    |> validate_length(:failure_reason, max: 255)
  end
end
