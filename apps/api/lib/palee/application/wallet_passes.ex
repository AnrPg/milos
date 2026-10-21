defmodule Palee.Application.WalletPasses do
  @moduledoc """
  Wallet cards (ADR-155, decision 5).

    * `add/3` - Box › Check-in «Πρόσθεσε στο Wallet»: the member's card at
      this box for a platform (one active card per platform; adding again
      returns the same card). Apple: a short-lived `download_url` the phone
      opens without a bearer header (Safari hands the `.pkpass` to Wallet).
      Google: the «Save to Google Wallet» `save_url`.
    * `download/1` - the `.pkpass` behind a download link.
    * `revoke/3` - Εγώ › Συνδεδεμένες συσκευές: the card stops scanning now,
      and the platform is told (the Apple pass turns void, the Google object
      inactive). Its barcode is the member's static code, so the code is
      reset too: every card carrying it is voided and the app shows a new
      code.
    * `touch/2` + `push/2` - a booking or check-in changed the member's next
      booking: the card is marked updated and each platform is told, in a
      background job.
    * PassKit web service (`register_device/5`, `unregister_device/4`,
      `updated_serials/3`, `latest/4`): Apple devices ask for updates with the
      pass's `authenticationToken`, derived from the Wallet key and the
      serial and checked against its stored SHA-256.

  Wallet cards exist only when the owner keeps static personal codes
  (board 10, Q5): in `rotating` mode `add/3` answers
  `wallet_requires_static_code`. A card carries the member's static code
  (`MemberCodes.wallet_barcode/2`, the `W1` form), and belongs to that code:
  resetting or revoking the code voids the card. The desk scans it like the
  in-app QR (method `wallet`).
  """

  require Logger

  alias Palee.Application.{
    CheckInActions,
    CheckInFacts,
    CheckInKeys,
    MemberCodes,
    PublicURL,
    SignedToken
  }

  alias Palee.{Facility, Identity, Organizations, Scheduling, Wallet}
  alias Palee.Facility.Domain.MemberCodePolicy
  alias Palee.Wallet.Domain.{PassContent, PassImage}
  alias Palee.Workers.WalletPushJob

  @download_salt "wallet-download-v1"
  @download_seconds 600
  @next_booking_days 30

  # ---------------------------------------------------------------- member

  def add(%{organization_id: _, user_id: user_id} = context, platform, now \\ DateTime.utc_now()) do
    with :ok <- valid_platform(platform),
         :ok <- MemberCodePolicy.wallet_allowed(Facility.check_in_rules(context)),
         true <- Wallet.configured?(platform) || {:error, :wallet_not_configured},
         {:ok, code} <- MemberCodes.ensure(context, user_id),
         {:ok, pass} <- active_or_new(context, user_id, code, platform, now) do
      case platform do
        "apple" ->
          {:ok, %{pass: present(pass), download_url: download_url(pass), save_url: nil}}

        "google" ->
          with {:ok, %{kind: :save_link, url: url}} <- build(context, pass, now) do
            {:ok, %{pass: present(pass), download_url: nil, save_url: url}}
          end
      end
    end
  end

  def download(token, now \\ DateTime.utc_now()) do
    with {:ok, %{"s" => serial}} <-
           verify(SignedToken.verify(@download_salt, token, max_age: @download_seconds)),
         {:ok, context, pass} <- pass_for_serial(serial),
         true <- is_nil(pass.revoked_at) || {:error, :pass_revoked},
         {:ok, %{kind: :pkpass, body: body}} <- build(context, pass, now) do
      {:ok, %{body: body, filename: "palee-#{pass.serial}.pkpass"}}
    end
  end

  # The card's barcode is the member's static code, so a card stops
  # scanning only when that code ends: revoking a card resets the code,
  # which voids every card carrying it (a new code is issued lazily).
  def revoke(%{user_id: user_id}, pass_id, now \\ DateTime.utc_now()) do
    with %{} = pass <-
           %{user_id: user_id}
           |> Wallet.list_user_passes()
           |> Enum.find(&(&1.id == pass_id)) || {:error, :not_found},
         context = %{organization_id: pass.organization_id, user_id: user_id},
         {:ok, revoked} <- Wallet.revoke_pass(context, pass.id, now),
         {:ok, _counts} <- MemberCodes.revoke(context, user_id, "reset", now) do
      WalletPushJob.schedule(pass.organization_id, pass.id)
      {:ok, present(Map.merge(pass, revoked))}
    end
  end

  @doc "The person's cards at every box, for Συνδεδεμένες συσκευές."
  def mine(%{user_id: _} = context) do
    context
    |> Wallet.list_user_passes()
    |> Enum.map(fn pass ->
      pass
      |> present()
      |> Map.put(:box, %{
        organization_id: pass.organization_id,
        slug: pass.organization_slug,
        name: pass.organization_name
      })
    end)
  end

  @doc "Which platforms can issue cards now."
  def availability, do: Map.new(Wallet.platforms(), &{&1, Wallet.configured?(&1)})

  # ---------------------------------------------------------------- updates

  @doc "The member's next booking changed at this box: mark their cards and tell the platforms."
  def touch(%{organization_id: organization_id} = context, user_id, now \\ DateTime.utc_now()) do
    context
    |> Wallet.touch_user_passes(user_id, now)
    |> Enum.each(&WalletPushJob.schedule(organization_id, &1.id))

    :ok
  end

  @doc "Tells the platform of one pass that it changed (the push job)."
  def push(organization_id, pass_id, now \\ DateTime.utc_now()) do
    context = %{organization_id: organization_id}

    with %{} = pass <- Wallet.get_pass(context, pass_id) || {:error, :not_found} do
      updater = Wallet.updater(pass.platform)

      case pass.platform do
        "apple" ->
          push_apple(context, updater, pass)

        "google" ->
          with {:ok, content} <- content(context, pass, now) do
            updater.update(%{content: content, logo_url: logo_url(context)})
          end
      end
      |> case do
        {:error, :wallet_not_configured} -> :ok
        {:ok, _result} -> :ok
        error -> error
      end
    end
  end

  defp push_apple(context, updater, pass) do
    case Wallet.push_tokens(context, pass.id) do
      [] ->
        {:ok, %{gone: []}}

      tokens ->
        with {:ok, result} <- updater.update(%{push_tokens: tokens}) do
          Enum.each(Map.get(result, :gone, []), &Wallet.forget_push_token(context, &1))
          {:ok, result}
        end
    end
  end

  # ---------------------------------------------------------------- PassKit web service

  def register_device(device, pass_type, serial, auth, push_token) do
    with {:ok, context, pass} <- authorized(pass_type, serial, auth),
         true <- (is_binary(push_token) and push_token != "") || {:error, :bad_request} do
      Wallet.register_device(context, pass.id, device, push_token)
    end
  end

  def unregister_device(device, pass_type, serial, auth) do
    with {:ok, context, pass} <- authorized(pass_type, serial, auth) do
      Wallet.unregister_device(context, pass.id, device)
    end
  end

  @doc "`{:ok, %{serials, last_updated}}` or `:none` when nothing changed."
  def updated_serials(device, pass_type, since_tag) do
    with :ok <- pass_type(pass_type) do
      since = parse_tag(since_tag)

      case Wallet.device_serials(device, since) do
        [] ->
          :none

        rows ->
          latest = rows |> Enum.map(&elem(&1, 1)) |> Enum.max(DateTime)
          {:ok, %{serials: Enum.map(rows, &elem(&1, 0)), last_updated: tag(latest)}}
      end
    end
  end

  @doc "The latest `.pkpass`, or `:not_modified` when it hasn't changed since `since`."
  def latest(pass_type, serial, auth, since, now \\ DateTime.utc_now()) do
    with {:ok, context, pass} <- authorized(pass_type, serial, auth) do
      last_modified = DateTime.truncate(pass.last_updated_at, :second)

      if since && DateTime.compare(last_modified, since) != :gt do
        :not_modified
      else
        with {:ok, %{kind: :pkpass, body: body}} <- build(context, pass, now) do
          {:ok, %{body: body, last_modified: last_modified}}
        end
      end
    end
  end

  defp authorized(pass_type, serial, auth) do
    with :ok <- pass_type(pass_type),
         {:ok, context, pass} <- pass_for_serial(serial),
         true <- pass.platform == "apple" || {:error, :unauthorized},
         true <- valid_auth?(pass, auth) || {:error, :unauthorized} do
      {:ok, context, pass}
    else
      {:error, :not_found} -> {:error, :unauthorized}
      error -> error
    end
  end

  defp pass_type(pass_type) do
    case Wallet.apple_pass_type_identifier() do
      ^pass_type when is_binary(pass_type) -> :ok
      _other -> {:error, :not_found}
    end
  end

  defp valid_auth?(pass, "ApplePass " <> token),
    do: Plug.Crypto.secure_compare(:crypto.hash(:sha256, token), pass.auth_token_hash)

  defp valid_auth?(_pass, _auth), do: false

  # ---------------------------------------------------------------- building

  defp active_or_new(context, user_id, code, platform, now) do
    case Wallet.get_active_pass(context, user_id, platform) do
      %{member_code_id: code_id} = pass when code_id == code.id ->
        {:ok, pass}

      # A card of an older code (revocation reaches cards too, so this is
      # only a safety net): replace it.
      %{} = stale ->
        {:ok, _revoked} = Wallet.revoke_pass(context, stale.id, now)
        WalletPushJob.schedule(context.organization_id, stale.id)
        active_or_new(context, user_id, code, platform, now)

      nil ->
        serial = Ecto.UUID.generate()

        case Wallet.create_pass(context, %{
               user_id: user_id,
               member_code_id: code.id,
               platform: platform,
               serial: serial,
               auth_token_hash: :crypto.hash(:sha256, auth_token(serial)),
               last_updated_at: now
             }) do
          {:ok, pass} ->
            {:ok, pass}

          # A concurrent add won the one-active-card index.
          {:error, %Ecto.Changeset{}} ->
            case Wallet.get_active_pass(context, user_id, platform) do
              nil -> {:error, :wallet_pass_conflict}
              pass -> {:ok, pass}
            end
        end
    end
  end

  defp build(context, pass, now) do
    with {:ok, content} <- content(context, pass, now) do
      pass.platform
      |> Wallet.builder()
      |> apply(:build, [content, build_opts(context, pass, content, now)])
    end
  end

  defp build_opts(context, %{platform: "apple"} = pass, content, now) do
    %{
      authentication_token: auth_token(pass.serial),
      web_service_url: PublicURL.base_url() <> "/api/wallet/apple",
      images: images(context, content),
      now: now
    }
  end

  defp build_opts(context, _pass, _content, now), do: %{logo_url: logo_url(context), now: now}

  defp content(context, pass, now) do
    person = Identity.find_by_id(pass.user_id)
    box = box(context)
    code = Facility.get_member_code(context, pass.member_code_id)

    {:ok,
     %PassContent{
       serial: pass.serial,
       box: box,
       member: %{name: CheckInActions.display_name(person) || ""},
       barcode: if(code, do: MemberCodes.wallet_barcode(context, code), else: ""),
       next_booking: next_booking(context, pass.user_id, now),
       updated_at: pass.last_updated_at,
       locale: (person && person.preferred_locale) || "el",
       locations: locations(context),
       revoked?: not is_nil(pass.revoked_at) or is_nil(code) or not is_nil(code.revoked_at)
     }}
  end

  defp box(%{organization_id: organization_id}) do
    case Organizations.brand_summary(organization_id) do
      nil -> %{name: "", slug: nil, primary_color: nil, logo_url: nil}
      summary -> summary
    end
  end

  defp logo_url(context), do: box(context).logo_url

  defp images(context, content) do
    logo =
      case logo_url(context) do
        url when is_binary(url) and url != "" ->
          case Wallet.image_source().fetch(url) do
            {:ok, bytes} -> bytes
            {:error, _reason} -> nil
          end

        _none ->
          nil
      end

    PassImage.images(content.box.primary_color, logo)
  end

  defp next_booking(context, user_id, now) do
    zone = Organizations.organization_timezone(context.organization_id)
    locations = context |> Facility.list_locations() |> Map.new(&{&1.id, &1.name})

    context
    |> Map.put(:user_id, user_id)
    |> Scheduling.list_member_slots(user_id, now, DateTime.add(now, @next_booking_days, :day))
    |> Enum.find(fn slot ->
      to_string(slot.user_booking.status) in ["approved", "pending"] and
        is_nil(slot.user_booking.guest_name)
    end)
    |> case do
      nil ->
        nil

      slot ->
        %{
          name: CheckInFacts.class_name(slot),
          starts_at: slot.scheduled_at,
          place: Map.get(locations, Map.get(slot, :location_id)),
          label: local_label(slot.scheduled_at, zone)
        }
    end
  end

  defp local_label(at, zone) do
    case DateTime.shift_zone(at, zone) do
      {:ok, local} -> Calendar.strftime(local, "%d/%m %H:%M")
      _error -> Calendar.strftime(at, "%d/%m %H:%M")
    end
  end

  defp locations(context) do
    context
    |> Facility.list_locations()
    |> Enum.map(&%{latitude: &1.latitude, longitude: &1.longitude, name: &1.name})
  end

  defp download_url(pass) do
    token = SignedToken.sign(@download_salt, %{"s" => pass.serial})
    PublicURL.base_url() <> "/api/wallet/passes/" <> token
  end

  defp pass_for_serial(serial) when is_binary(serial) do
    with {:ok, _uuid} <- Ecto.UUID.cast(serial),
         organization_id when is_binary(organization_id) <- Wallet.pass_organization(serial),
         context = %{organization_id: organization_id},
         %{} = pass <- Wallet.get_pass_by_serial(context, serial) do
      {:ok, context, pass}
    else
      _missing -> {:error, :not_found}
    end
  end

  defp pass_for_serial(_serial), do: {:error, :not_found}

  @doc false
  def auth_token(serial),
    do:
      :crypto.mac(:hmac, :sha256, CheckInKeys.wallet_key(), "passkit-auth|" <> serial)
      |> Base.url_encode64(padding: false)

  defp present(pass) do
    %{
      id: pass.id,
      platform: pass.platform,
      added_at: pass.inserted_at,
      last_updated_at: pass.last_updated_at,
      revoked_at: pass.revoked_at,
      active: is_nil(pass.revoked_at)
    }
  end

  defp valid_platform(platform) when platform in ["apple", "google"], do: :ok
  defp valid_platform(_platform), do: {:error, :invalid_wallet_platform}

  defp verify({:ok, payload}), do: {:ok, payload}
  defp verify({:error, _reason}), do: {:error, :invalid_download_link}

  defp tag(%DateTime{} = at), do: at |> DateTime.to_unix(:microsecond) |> Integer.to_string()

  defp parse_tag(nil), do: nil
  defp parse_tag(""), do: nil

  defp parse_tag(tag) do
    case Integer.parse(tag) do
      {micro, ""} -> DateTime.from_unix!(micro, :microsecond)
      _invalid -> nil
    end
  end

  @doc false
  def log(logs) when is_list(logs) do
    logs |> Enum.take(50) |> Enum.each(&Logger.info("passkit_log #{inspect(&1)}"))
    :ok
  end

  def log(_logs), do: :ok
end
