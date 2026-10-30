defmodule Palee.Application.PartnerEligibility do
  @moduledoc """
  Who may take part in Partners (ADR-280): the seam the deck side calls. The
  verification side owns the bodies; until then nobody is verified.
  """

  @type status :: :verified | :needs_verification | :in_review | :rejected | :suspended

  @doc "The viewer's verification state and next step."
  @spec status(map()) :: %{status: status(), method: String.t() | nil, next_step: atom() | nil}
  def status(_context), do: %{status: :needs_verification, method: nil, next_step: :sponsors}

  @doc "`:ok` when the viewer may use Partners."
  @spec require_verified(map()) ::
          :ok | {:error, :partner_verification_required} | {:error, :partner_suspended}
  def require_verified(_context), do: {:error, :partner_verification_required}

  @doc "The ids among `user_ids` that are verified and not suspended."
  @spec verified_user_ids([Ecto.UUID.t()]) :: [Ecto.UUID.t()]
  def verified_user_ids(_user_ids), do: []

  @doc "Per person: how they were verified and the box of an active membership (nil if none)."
  @spec verification_badges([Ecto.UUID.t()]) :: %{
          Ecto.UUID.t() => %{method: String.t(), box_name: String.t() | nil}
        }
  def verification_badges(_user_ids), do: %{}

  @doc "The Palee team suspends a person: verification off, sponsors penalised and told."
  @spec suspend(map(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, %{penalized_sponsor_ids: [Ecto.UUID.t()]}} | {:error, term()}
  def suspend(_platform_context, _user_id, _now), do: {:ok, %{penalized_sponsor_ids: []}}
end
