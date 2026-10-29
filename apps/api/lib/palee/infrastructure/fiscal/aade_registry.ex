defmodule Palee.Infrastructure.Fiscal.AadeRegistry do
  @moduledoc """
  AADE's registry service «Βασικά στοιχεία μητρώου επιχειρήσεων»
  (RgWsPublic2, ADR-265), the adapter of `Fiscal.Ports.BusinessRegistry`.

  SOAP 1.2 (`application/soap+xml`) to
  `https://www1.gsis.gr/wsaade/RgWsPublic2/RgWsPublic2`, operation
  `rgWsPublic2AfmMethod`, with a WS-Security `UsernameToken` carrying the
  business's own special credentials («ειδικοί κωδικοί», issued by AADE to
  the business for this service). The input is `afm_called_for` (the tax
  ID looked up) and `as_on_date`; `afm_called_by` stays empty (the
  business asks for itself).

  The answer's `basic_rec` gives the name, ΔΟΥ, address and status; the
  `firm_act_tab` items give the activities (ΚΑΔ, `firm_act_kind` 1 = main).
  An `error_rec` code names what went wrong (`RG_WS_PUBLIC_*`).

  The URL comes from `config :palee, :aade_registry, url: ...`; requests
  honour the outbound proxy and test plugs (`Fiscal.Infrastructure.Http`).
  Credentials never reach a log or an error.
  """

  @behaviour Palee.Fiscal.Ports.BusinessRegistry

  alias Palee.Infrastructure.Fiscal.Http

  @url "https://www1.gsis.gr/wsaade/RgWsPublic2/RgWsPublic2"
  @max_response_bytes 262_144

  @credential_errors ~w(
    RG_WS_PUBLIC_TOKEN_USERNAME_NOT_AUTHENTICATED RG_WS_PUBLIC_TOKEN_USERNAME_NOT_ACTIVE
    RG_WS_PUBLIC_TOKEN_USERNAME_NOT_DEFINED RG_WS_PUBLIC_TOKEN_USERNAME_TOO_LONG
    RG_WS_PUBLIC_TOKEN_AFM_NOT_REGISTERED RG_WS_PUBLIC_TOKEN_AFM_BLOCKED
    RG_WS_PUBLIC_TOKEN_AFM_NOT_AUTHORIZED RG_WS_PUBLIC_TOKEN_AFM_NOT_FOUND
    RG_WS_PUBLIC_AFM_CALLED_BY_BLOCKED RG_WS_PUBLIC_AFM_CALLED_BY_NOT_FOUND
  )
  @not_found_errors ~w(RG_WS_PUBLIC_WRONG_AFM RG_WS_PUBLIC_TAXPAYER_NF RG_WS_PUBLIC_EPIT_NF)
  @limit_errors ~w(
    RG_WS_PUBLIC_MONTHLY_LIMIT_EXCEEDED RG_WS_PUBLIC_MAX_DAILY_USERNAME_CALLS_EXCEEDED
    RG_WS_PUBLIC_FAILURES_TOLERATED_EXCEEDED
  )

  @impl true
  def lookup(connection, tax_id, %Date{} = as_on) do
    with :ok <- credentials(connection),
         {:ok, %Req.Response{status: status, body: body}} <-
           Http.request(
             method: :post,
             url: url(),
             body: envelope(connection, tax_id, as_on),
             headers: [{"content-type", "application/soap+xml; charset=utf-8"}],
             decode_body: false
           ) do
      interpret(status, body)
    else
      {:error, :credentials_rejected} = error -> error
      {:error, _transport} -> {:error, :unavailable}
    end
  end

  defp url, do: :palee |> Application.get_env(:aade_registry, []) |> Keyword.get(:url, @url)

  defp credentials(%{user_id: user, subscription_key: password})
       when is_binary(user) and user != "" and is_binary(password) and password != "",
       do: :ok

  defp credentials(_connection), do: {:error, :credentials_rejected}

  @doc false
  # The SOAP request; public for tests (never logged: it holds the password).
  def envelope(connection, tax_id, as_on) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <env:Envelope xmlns:env="http://www.w3.org/2003/05/soap-envelope" \
    xmlns:ns1="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" \
    xmlns:ns2="http://rgwspublic2/RgWsPublic2Service" xmlns:ns3="http://rgwspublic2/RgWsPublic2">\
    <env:Header><ns1:Security><ns1:UsernameToken>\
    <ns1:Username>#{escape(connection.user_id)}</ns1:Username>\
    <ns1:Password>#{escape(connection.subscription_key)}</ns1:Password>\
    </ns1:UsernameToken></ns1:Security></env:Header>\
    <env:Body><ns2:rgWsPublic2AfmMethod><ns2:INPUT_REC>\
    <ns3:afm_called_by/>\
    <ns3:afm_called_for>#{escape(tax_id)}</ns3:afm_called_for>\
    <ns3:as_on_date>#{Date.to_iso8601(as_on)}</ns3:as_on_date>\
    </ns2:INPUT_REC></ns2:rgWsPublic2AfmMethod></env:Body></env:Envelope>\
    """
  end

  @doc false
  # Public for tests: the answer of one call.
  def interpret(status, body) when is_binary(body) and byte_size(body) <= @max_response_bytes do
    case error_code(body) do
      nil when status in 200..299 -> parse(body)
      nil -> {:error, :unavailable}
      code -> {:error, classify(code)}
    end
  end

  def interpret(_status, _body), do: {:error, :unavailable}

  defp error_code(body) do
    case Regex.run(~r/RG_WS_PUBLIC_[A-Z_]+/, body) do
      [code] -> code
      nil -> nil
    end
  end

  defp classify(code) when code in @credential_errors, do: :credentials_rejected
  defp classify(code) when code in @not_found_errors, do: :not_found
  defp classify(code) when code in @limit_errors, do: :limit_reached
  defp classify(_code), do: :unavailable

  defp parse(body) do
    {document, _rest} =
      body
      |> :binary.bin_to_list()
      |> :xmerl_scan.string(allow_entities: false, quiet: true, fetch_fun: &no_fetch/2)

    case xpath(document, "//*[local-name()='basic_rec']") do
      [basic | _] -> {:ok, business(document, basic)}
      [] -> {:error, :not_found}
    end
  catch
    _kind, _reason -> {:error, :unavailable}
  end

  defp business(document, basic) do
    activities =
      document
      |> xpath("//*[local-name()='firm_act_tab']/*[local-name()='item']")
      |> Enum.map(fn item ->
        %{
          code: text(item, "firm_act_code"),
          description: text(item, "firm_act_descr"),
          main: text(item, "firm_act_kind") == "1"
        }
      end)
      |> Enum.reject(&is_nil(&1.code))

    main = Enum.find(activities, & &1.main) || List.first(activities)

    %{
      tax_id: text(basic, "afm"),
      legal_name: text(basic, "onomasia"),
      trade_name: text(basic, "commer_title"),
      tax_office: text(basic, "doy_descr"),
      tax_office_code: text(basic, "doy"),
      street: text(basic, "postal_address"),
      building_number: text(basic, "postal_address_no"),
      postal_code: text(basic, "postal_zip_code"),
      city: text(basic, "postal_area_description"),
      activity_code: main && main.code,
      activity_description: main && main.description,
      activities: activities,
      # 1 = ΕΝΕΡΓΟΣ ΑΦΜ, 2 = ΑΠΕΝΕΡΓΟΠΟΙΗΜΕΝΟΣ ΑΦΜ.
      active: text(basic, "deactivation_flag") != "2" and is_nil(text(basic, "stop_date")),
      legal_status: text(basic, "legal_status_descr"),
      vat_registered: text(basic, "normal_vat_system_flag") == "Y"
    }
  end

  defp no_fetch(_uri, _state), do: {:error, :external_entities_disabled}

  defp xpath(node, path), do: :xmerl_xpath.string(String.to_charlist(path), node)

  defp text(node, name) do
    case xpath(node, "./*[local-name()='#{name}']/text()") do
      [] ->
        nil

      texts ->
        texts
        |> Enum.map(fn {:xmlText, _parents, _pos, _lang, value, _type} -> value end)
        |> IO.chardata_to_string()
        |> String.trim()
        |> case do
          "" -> nil
          value -> value
        end
    end
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
