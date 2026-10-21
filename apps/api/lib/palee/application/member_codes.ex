defmodule Palee.Application.MemberCodes do
  @moduledoc """
  The member's personal check-in code (ADR-155; board 10, Q5). The owner's
  `member_code_mode` decides what it is (`MemberCodePolicy`):

    * `rotating` - `MemberCode`, changes every 30 seconds, no Wallet card;
    * `static` - one persistent code per member and box
      (`facility_member_codes` + `StaticMemberCode`), issued the first time
      it is needed, shown in the app and carried by the Wallet cards.

  `reset/2` (the member) and `revoke/4` (staff) end a static code and void
  the cards that carry it; `revoke_all/2` runs when the box goes back to
  rotating codes. `resolve/3` turns a code the desk scanned into a member.
  """

  alias Palee.Application.CheckInKeys
  alias Palee.{Facility, Wallet}
  alias Palee.Facility.Domain.{MemberCode, MemberCodePolicy, StaticMemberCode}
  alias Palee.Workers.WalletPushJob

  @doc "The member's QR now, in the box's mode."
  def current(
        %{organization_id: organization_id, user_id: user_id} = context,
        now \\ DateTime.utc_now()
      ) do
    rules = Facility.check_in_rules(context)
    key = CheckInKeys.member_key(organization_id)

    case MemberCodePolicy.presented_kind(rules) do
      :rotating ->
        {:ok,
         key
         |> MemberCode.current(user_id, now)
         |> Map.merge(%{mode: "rotating", wallet_available: false, issued_at: nil})}

      :static ->
        with {:ok, code} <- ensure(context, user_id) do
          {:ok,
           %{
             mode: "static",
             code: StaticMemberCode.sign(key, code.serial, :app),
             rotation_seconds: nil,
             seconds_until_rotation: nil,
             expires_at: nil,
             wallet_available: true,
             issued_at: code.inserted_at
           }}
        end
    end
  end

  @doc "The member's active static code, issued now if they have none."
  def ensure(context, user_id) do
    case Facility.get_active_member_code(context, user_id) do
      nil -> Facility.issue_member_code(context, user_id)
      code -> {:ok, code}
    end
  end

  @doc "The Wallet barcode of a static code."
  def wallet_barcode(%{organization_id: organization_id}, code),
    do: StaticMemberCode.sign(CheckInKeys.member_key(organization_id), code.serial, :wallet)

  @doc "The member resets their static code: the old one and its cards stop, a new one is issued."
  def reset(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    with :ok <- static_mode(context),
         {:ok, _revoked} <- revoke(context, user_id, "reset", now) do
      current(context, now)
    end
  end

  @doc "Ends a member's static code and voids its cards (`reason`: reset or staff)."
  def revoke(context, user_id, reason, now \\ DateTime.utc_now()) do
    codes = Facility.revoke_member_codes(context, %{user_id: user_id}, reason, now)
    {:ok, void(context, codes, now)}
  end

  @doc "The box went back to rotating codes: every static code and card stops."
  def revoke_all(context, now \\ DateTime.utc_now()) do
    codes = Facility.revoke_member_codes(context, %{}, "mode_rotating", now)
    {:ok, void(context, codes, now)}
  end

  defp void(%{organization_id: organization_id} = context, codes, now) do
    passes = Wallet.revoke_code_passes(context, Enum.map(codes, & &1.id), now)
    Enum.each(passes, &WalletPushJob.schedule(organization_id, &1.id))
    %{revoked_codes: length(codes), revoked_passes: length(passes)}
  end

  @doc """
  The member behind a scanned personal code: `{:ok, user_id, method}`, where
  method is `member_qr` (the app) or `wallet` (a Wallet card).
  """
  def resolve(%{organization_id: organization_id} = context, code, now)
      when is_binary(code) do
    rules = Facility.check_in_rules(context)
    kind = MemberCodePolicy.kind(code)
    key = CheckInKeys.member_key(organization_id)

    with :ok <- MemberCodePolicy.accept(rules, kind),
         {:ok, user_id} <- member(context, key, kind, code, now) do
      {:ok, user_id, MemberCodePolicy.method(kind)}
    end
  end

  def resolve(_context, _code, _now), do: {:error, :invalid_member_code}

  defp member(_context, key, :rotating, code, now), do: MemberCode.verify(key, code, now)

  defp member(context, key, _static, code, _now) do
    with {:ok, serial, _channel} <- StaticMemberCode.verify(key, code) do
      case Facility.get_member_code_by_serial(context, serial) do
        %{revoked_at: nil, user_id: user_id} -> {:ok, user_id}
        %{} -> {:error, :member_code_revoked}
        nil -> {:error, :invalid_member_code}
      end
    end
  end

  defp static_mode(context) do
    if MemberCodePolicy.mode(Facility.check_in_rules(context)) == "static",
      do: :ok,
      else: {:error, :member_code_not_static}
  end
end
