defmodule Palee.Wallet.Domain.GooglePass do
  @moduledoc """
  A Google Wallet generic pass (ADR-155, decision 5): the class shared by
  every Palee card of an issuer, the member's object, and the claims of the
  signed «Save to Google Wallet» JWT. The adapter signs the claims with the
  issuer's service-account key and patches the object through the REST API
  when the card changes. Pure.
  """

  alias Palee.BrandPalette
  alias Palee.Wallet.Domain.PassContent

  @class_suffix "milos_member_card"
  @save_url "https://pay.google.com/gp/v/save/"

  def save_url(jwt), do: @save_url <> jwt

  def class_id(issuer_id), do: "#{issuer_id}.#{@class_suffix}"
  def object_id(issuer_id, serial), do: "#{issuer_id}.#{serial}"

  def generic_class(issuer_id), do: %{"id" => class_id(issuer_id)}

  @doc "The member's pass object. `logo_url` is the box's public logo, if any."
  def generic_object(%PassContent{} = content, issuer_id, logo_url \\ nil) do
    copy = PassContent.copy(content)
    language = if String.starts_with?(content.locale || "", "el"), do: "el", else: "en"

    %{
      "id" => object_id(issuer_id, content.serial),
      "classId" => class_id(issuer_id),
      "state" => if(content.revoked?, do: "INACTIVE", else: "ACTIVE"),
      "cardTitle" => localized(content.box.name, language),
      "subheader" => localized(copy.member, language),
      "header" => localized(content.member.name, language),
      "barcode" => %{"type" => "QR_CODE", "value" => content.barcode},
      "textModulesData" => [
        %{"id" => "next", "header" => copy.next, "body" => next_text(content, copy)},
        %{"id" => "how", "header" => copy.how_label, "body" => copy.how}
      ]
    }
    |> Map.put("hexBackgroundColor", BrandPalette.colour(:deep))
    |> put_logo(logo_url)
  end

  @doc "Claims of the «Save to Google Wallet» JWT (signed with RS256 by the adapter)."
  def save_claims(%PassContent{} = content, google, %DateTime{} = now) do
    %{
      "iss" => google.service_account_email,
      "aud" => "google",
      "typ" => "savetowallet",
      "iat" => DateTime.to_unix(now),
      "origins" => List.wrap(google[:origins]),
      "payload" => %{
        "genericClasses" => [generic_class(google.issuer_id)],
        "genericObjects" => [generic_object(content, google.issuer_id, google[:logo_url])]
      }
    }
  end

  defp next_text(%{next_booking: nil}, copy), do: copy.none

  defp next_text(%{next_booking: booking}, _copy) do
    [booking[:label] || DateTime.to_iso8601(booking.starts_at), booking.name, booking[:place]]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp localized(value, language),
    do: %{"defaultValue" => %{"language" => language, "value" => value}}

  defp put_logo(object, url) when is_binary(url) and url != "",
    do: Map.put(object, "logo", %{"sourceUri" => %{"uri" => url}})

  defp put_logo(object, _url), do: object
end
