defmodule MilosTraining.Wallet.Domain.ApplePass do
  @moduledoc """
  The files of an Apple Wallet pass (ADR-155, decision 5), without the
  signature: `pass.json` (a generic pass with a QR barcode, the next booking,
  the box's locations, the PassKit web service that keeps it current) and
  `manifest.json` (the SHA-1 of every file). The infrastructure adapter
  signs the manifest and zips everything into a `.pkpass`. Pure.
  """

  alias MilosTraining.Wallet.Domain.PassContent

  @max_locations 10

  @doc """
  pass.json as a map. `apple` holds `pass_type_identifier`,
  `team_identifier`, `web_service_url` and the pass's `authentication_token`.
  """
  def pass_json(%PassContent{} = content, apple) do
    copy = PassContent.copy(content)

    %{
      "formatVersion" => 1,
      "passTypeIdentifier" => apple.pass_type_identifier,
      "teamIdentifier" => apple.team_identifier,
      "serialNumber" => content.serial,
      "organizationName" => content.box.name,
      "description" => "#{copy.description} · #{content.box.name}",
      "logoText" => content.box.name,
      "backgroundColor" => PassContent.rgb(content.box.primary_color) || "rgb(17, 24, 39)",
      "foregroundColor" => PassContent.foreground(content.box.primary_color),
      "labelColor" => PassContent.foreground(content.box.primary_color),
      "webServiceURL" => apple.web_service_url,
      "authenticationToken" => apple.authentication_token,
      "sharingProhibited" => true,
      "voided" => content.revoked?,
      "barcodes" => [barcode(content)],
      "barcode" => barcode(content),
      "generic" => fields(content, copy)
    }
    |> put_relevance(content, copy)
  end

  defp barcode(content) do
    %{
      "format" => "PKBarcodeFormatQR",
      "message" => content.barcode,
      "messageEncoding" => "iso-8859-1"
    }
  end

  defp fields(content, copy) do
    %{
      "primaryFields" => [
        %{"key" => "member", "label" => copy.member, "value" => content.member.name}
      ],
      "secondaryFields" => next_booking_fields(content.next_booking, copy),
      "auxiliaryFields" => [],
      "backFields" =>
        [
          %{"key" => "how", "label" => copy.how_label, "value" => copy.how},
          content.revoked? && %{"key" => "revoked", "label" => "", "value" => copy.revoked}
        ]
        |> Enum.filter(& &1)
    }
  end

  defp next_booking_fields(nil, copy),
    do: [%{"key" => "next", "label" => copy.next, "value" => copy.none}]

  defp next_booking_fields(booking, copy) do
    [
      %{
        "key" => "next",
        "label" => copy.next,
        "value" => DateTime.to_iso8601(booking.starts_at),
        "dateStyle" => "PKDateStyleShort",
        "timeStyle" => "PKDateStyleShort",
        "changeMessage" => "#{copy.next}: %@"
      },
      %{
        "key" => "class",
        "label" => copy.class,
        "value" => Enum.join(Enum.reject([booking.name, booking.place], &is_nil/1), " · ")
      }
    ]
  end

  defp put_relevance(pass, content, copy) do
    locations =
      content.locations
      |> Enum.filter(&(is_number(&1.latitude) and is_number(&1.longitude)))
      |> Enum.take(@max_locations)
      |> Enum.map(fn location ->
        %{
          "latitude" => location.latitude,
          "longitude" => location.longitude,
          "relevantText" => copy.near
        }
      end)

    pass
    |> then(&if(locations == [], do: &1, else: Map.put(&1, "locations", locations)))
    |> then(fn pass ->
      case content.next_booking do
        %{starts_at: starts_at} -> Map.put(pass, "relevantDate", DateTime.to_iso8601(starts_at))
        nil -> pass
      end
    end)
  end

  @doc """
  The pass's files as `[{name, bytes}]`: pass.json plus the images
  (`%{"icon.png" => bytes, ...}`), sorted by name. Apple needs `icon.png`.
  """
  def files(%PassContent{} = content, apple, images) when is_map(images) do
    [{"pass.json", Jason.encode!(pass_json(content, apple))} | Enum.to_list(images)]
    |> Enum.sort_by(&elem(&1, 0))
  end

  @doc "manifest.json: each file's SHA-1, hex encoded."
  def manifest(files) do
    files
    |> Map.new(fn {name, bytes} ->
      {name, :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower)}
    end)
    |> Jason.encode!()
  end
end
