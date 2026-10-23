defmodule Palee.Perks.Domain.RedemptionMethod do
  @moduledoc """
  How a member redeems a perk at the partner (ADR-191 §2): a strategy, one
  module per method, so a new kind of agreement is a new module and a line
  in `@methods`, not a schema change.

  Partner-issued (the default family; the partner checks the code in its
  own system):

    * `shared_code` — one code for everyone (`SharedCode`);
    * `code_pool` — a batch of single-use codes, one per claim (`CodePool`);
    * `partner_link` — an online store link with the code applied
      (`PartnerLink`);
    * `show_membership` — no code: the member shows their membership
      (`ShowMembership`).

  Palee-issued:

    * `personal_qr` — a personal single-use QR (and short code) the
      partner verifies with a signed link, no account (`PersonalQr`).

  Each strategy answers, purely:

    * `validate/1` — the errors of its settings (`[{field, message}]`);
    * `issue/0` — where a claim's code comes from: `:shared` (the
      settings), `:pool` (the next free pool code) or `:reference` (a short
      code Palee makes);
    * `verifiable?/0` — whether a signed partner link verifies claims;
    * `ready/1` — `:ok` or why it can't go live (`%{free_codes: n}`);
    * `reveal/2` — what the member sees for a claim's code.
  """

  @type settings :: %{optional(atom()) => term()}

  @callback key() :: String.t()
  @callback validate(settings()) :: [{atom(), String.t()}]
  @callback issue() :: :shared | :pool | :reference
  @callback verifiable?() :: boolean()
  @callback ready(%{free_codes: non_neg_integer()}) :: :ok | {:error, atom()}
  @callback reveal(settings(), String.t()) :: %{
              code: String.t() | nil,
              url: String.t() | nil,
              show_membership: boolean()
            }

  alias Palee.Perks.Domain.Methods.{CodePool, PartnerLink, PersonalQr, SharedCode, ShowMembership}

  @methods [SharedCode, CodePool, PartnerLink, ShowMembership, PersonalQr]
  @by_key Map.new(@methods, &{&1.key(), &1})

  @doc "Every method key, the default first."
  def keys, do: Enum.map(@methods, & &1.key())

  @doc "The default method: partner-issued shared code."
  def default, do: SharedCode.key()

  @doc "The strategy of a key, or `{:error, :invalid_redemption_method}`."
  def fetch(key) when is_map_key(@by_key, key), do: {:ok, Map.fetch!(@by_key, key)}
  def fetch(_key), do: {:error, :invalid_redemption_method}

  def fetch!(key), do: Map.fetch!(@by_key, key)

  def validate(key, settings), do: with({:ok, m} <- fetch(key), do: m.validate(settings))
  def issue(key), do: fetch!(key).issue()
  def verifiable?(key), do: fetch!(key).verifiable?()
  def ready(key, facts), do: fetch!(key).ready(facts)
  def reveal(key, settings, code), do: fetch!(key).reveal(settings, code)
end
