defmodule Palee.BusinessAccounts.BusinessRequest do
  @moduledoc """
  ADR-184: a person's request to the platform team: turn a plain account into
  a business (`conversion`), or activate a demo business (`activation`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.BusinessAccounts.Domain.BusinessRequestPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "business_requests" do
    field :user_id, :binary_id
    field :kind, :string
    field :business_kind, :string
    field :business_name, :string
    field :city, :string
    field :phone, :string
    field :message, :string
    field :organization_id, :binary_id
    field :status, :string, default: "pending"
    field :decided_by_id, :binary_id
    field :decided_at, :utc_datetime_usec
    field :decision_note, :string

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :user_id,
      :kind,
      :business_kind,
      :business_name,
      :city,
      :phone,
      :message,
      :organization_id
    ])
    |> validate_required([:user_id, :kind, :business_kind, :business_name])
    |> validate_inclusion(:kind, BusinessRequestPolicy.kinds())
    |> validate_inclusion(:business_kind, BusinessRequestPolicy.business_kinds())
    |> validate_length(:business_name, min: 2, max: 120)
    |> validate_length(:city, max: 80)
    |> validate_length(:phone, max: 40)
    |> validate_length(:message, max: 1000)
    |> unique_constraint([:user_id, :kind], name: :business_requests_one_pending_index)
  end

  def cancel_changeset(request, at),
    do: change(request, status: "cancelled", updated_at: at)

  def decide_changeset(request, attrs) do
    request
    |> cast(attrs, [:status, :decided_by_id, :decided_at, :decision_note, :organization_id])
    |> validate_required([:status, :decided_at])
    |> validate_inclusion(:status, BusinessRequestPolicy.statuses())
    |> validate_length(:decision_note, max: 500)
  end
end
