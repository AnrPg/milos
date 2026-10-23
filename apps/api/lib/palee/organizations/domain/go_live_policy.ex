defmodule Palee.Organizations.Domain.GoLivePolicy do
  @moduledoc """
  ADR-184: what a business in demo mode may not do until the platform team
  activates it. The one place that answers it; every command that goes live
  asks here and refuses with `:business_not_activated`.

  A business is *gated* while it is a gym or an independent coach
  (`provider_kind` gym | coach) in `demo` mode. Organisers (ADR-185) and any
  other kind are never gated: they are people hosting events, not businesses.

  Everything inside the account keeps working with mock data. Only the
  actions that reach real people are refused:

    * `:invite_people` - issuing invitations, opening the join link, event
      guest links;
    * `:join` - anyone redeeming an invitation or joining through a link;
    * `:grant_staff_role` - a staff role for a real account other than the
      acting one (mock people may get any role);
    * `:publish_profile` - publishing the public page;
    * `:take_booking` - a booking, trial, appointment or event place from
      anyone but the business's own staff or its mock people;
    * `:take_payment` - an invoice or a payment for anyone but a mock
      person;
    * `:send_outside` - an email, push or message to anyone outside the
      business's own staff;
    * `:publish_perk` - publishing a partner perk to members (ADR-191);
      drafts stay possible.

  Discovery (Γύρω μου, the public box page, referral invites) is gated in
  the SQL lookups themselves, which answer only for active organizations.
  """

  @gated_kinds ~w(gym coach)
  @actions [
    :invite_people,
    :join,
    :grant_staff_role,
    :publish_profile,
    :take_booking,
    :take_payment,
    :send_outside,
    :publish_perk
  ]

  @type organization :: %{
          optional(:provider_kind) => String.t() | nil,
          optional(:activation) => String.t() | nil,
          optional(any()) => any()
        }
  @type action ::
          :invite_people
          | :join
          | :grant_staff_role
          | :publish_profile
          | :take_booking
          | :take_payment
          | :send_outside
          | :publish_perk

  @doc "The gated actions, for the web and for tests."
  @spec actions() :: [action()]
  def actions, do: @actions

  @doc "The kinds that start in demo mode (ADR-184)."
  @spec gated_kinds() :: [String.t()]
  def gated_kinds, do: @gated_kinds

  @doc "Whether the organization is a business still in demo mode."
  @spec gated?(organization() | nil) :: boolean()
  def gated?(%{activation: "demo"} = organization),
    do: (Map.get(organization, :provider_kind) || "gym") in @gated_kinds

  def gated?(_organization), do: false

  @doc """
  `:ok` when the organization may take the action, else
  `{:error, :business_not_activated}`. `facts` carries what the caller knows
  about the people involved:

    * `:actor_staff?`, `:actor_demo_person?` for `:take_booking`;
    * `:target_self?`, `:target_demo_person?` for `:grant_staff_role`;
    * `:payer_demo_person?` for `:take_payment`.
  """
  @spec check(organization() | nil, action(), map()) :: :ok | {:error, :business_not_activated}
  def check(organization, action, facts \\ %{}) when action in @actions do
    if gated?(organization) and not allowed_in_demo?(action, facts),
      do: {:error, :business_not_activated},
      else: :ok
  end

  defp allowed_in_demo?(:take_booking, facts),
    do: fact?(facts, :actor_staff?) or fact?(facts, :actor_demo_person?)

  defp allowed_in_demo?(:grant_staff_role, facts),
    do: fact?(facts, :target_self?) or fact?(facts, :target_demo_person?)

  defp allowed_in_demo?(:take_payment, facts), do: fact?(facts, :payer_demo_person?)
  defp allowed_in_demo?(_action, _facts), do: false

  defp fact?(facts, key), do: Map.get(facts, key) == true

  @doc "The state the web shows: activation and whether the gate applies."
  @spec status(organization() | nil) :: %{activation: String.t(), gated: boolean()}
  def status(organization) do
    %{
      activation: (organization && Map.get(organization, :activation)) || "active",
      gated: gated?(organization)
    }
  end
end
