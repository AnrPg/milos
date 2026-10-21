defmodule Palee.Workouts.Domain.AssignmentAudiencePolicy do
  @moduledoc """
  ADR-125: who a workout assignment may target, and what a class variant is.

  Pure rules over already-resolved facts (tenant membership roles, the optional
  source slot). Assignee roles always come from the membership in the acting
  organization, never from the global account role (F-29).

  - Athletes and members are valid assignees; staff and non-members are not.
  - A class variant (an assignment with a source slot) targets exactly one
    member — it is that member's version of a class they booked.
  - Members receive personal programming only through an explicit package
    grant; athletes keep the rollout-governed ADR-040 behaviour.
  """

  @assignee_roles [:athlete, :member]
  @member_modes %{
    "class_workout" => :class_workout,
    "class_variant" => :class_variant,
    "personal" => :personal
  }

  @type classified :: %{athletes: [String.t()], members: [String.t()]}

  @doc """
  Splits assignee ids into athletes and members using `roles_by_user`
  (user id => tenant membership role, or nil). Any id that is not an active
  athlete or member of the tenant rejects the whole selection.
  """
  @spec classify([String.t()], %{optional(String.t()) => atom() | nil}) ::
          {:ok, classified()} | {:error, :invalid_athletes}
  def classify(assignee_ids, roles_by_user) when is_list(assignee_ids) do
    ids = Enum.uniq(assignee_ids)

    if Enum.all?(ids, &(Map.get(roles_by_user, &1) in @assignee_roles)) do
      {:ok,
       %{
         athletes: Enum.filter(ids, &(Map.get(roles_by_user, &1) == :athlete)),
         members: Enum.filter(ids, &(Map.get(roles_by_user, &1) == :member))
       }}
    else
      {:error, :invalid_athletes}
    end
  end

  @doc "A class variant must target exactly one member and nobody else."
  @spec validate_class_variant(String.t() | nil, classified()) ::
          :ok | {:error, :class_variant_requires_single_member}
  def validate_class_variant(nil, _classified), do: :ok
  def validate_class_variant(_slot_id, %{athletes: [], members: [_member]}), do: :ok

  def validate_class_variant(_slot_id, _classified),
    do: {:error, :class_variant_requires_single_member}

  @doc "Members need an explicit `personal_programming` package grant."
  @spec requires_explicit_entitlement?(atom()) :: boolean()
  def requires_explicit_entitlement?(:member), do: true
  def requires_explicit_entitlement?(_role), do: false

  @doc "Whose tenant role allows starting an assignment addressed to them."
  @spec may_execute_assignment?(atom() | nil) :: boolean()
  def may_execute_assignment?(role), do: role in @assignee_roles

  @doc "The derived assignment kind exposed to clients."
  @spec kind(String.t() | nil) :: String.t()
  def kind(nil), do: "personal"
  def kind(_source_slot_id), do: "class_variant"

  @doc "Whether an assignee link is live (neither rejected nor archived)."
  @spec live_status?(atom() | String.t() | nil) :: boolean()
  def live_status?(status), do: status in [nil, :accepted, "accepted"]

  @doc """
  Parses the member programming mode of the admin profile flow. A missing mode
  keeps the ADR-071 behaviour (replace the booked class's workout).
  """
  @spec member_programming_mode(String.t() | nil) ::
          {:ok, :class_workout | :class_variant | :personal}
          | {:error, :invalid_programming_mode}
  def member_programming_mode(nil), do: {:ok, :class_workout}

  def member_programming_mode(mode) when is_binary(mode) do
    case Map.fetch(@member_modes, mode) do
      {:ok, parsed} -> {:ok, parsed}
      :error -> {:error, :invalid_programming_mode}
    end
  end

  def member_programming_mode(_mode), do: {:error, :invalid_programming_mode}
end
