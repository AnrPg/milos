defmodule Palee.Infrastructure.Fiscal.SandboxBusinessRegistry do
  @moduledoc """
  The sandbox of `Fiscal.Ports.BusinessRegistry` (ADR-265): no network, no
  credentials. Every tax ID with a valid check digit is a made-up active
  business, the same one every time, so pilots and demos can try
  «Συμπλήρωση από το ΑΦΜ». Tax IDs ending in `0000` are not found;
  `000000000` is not a valid ΑΦΜ and never reaches an adapter.
  """

  @behaviour Palee.Fiscal.Ports.BusinessRegistry

  @impl true
  def lookup(_connection, tax_id, _as_on) do
    if String.ends_with?(tax_id, "0000") do
      {:error, :not_found}
    else
      {:ok,
       %{
         tax_id: tax_id,
         legal_name: "ΔΟΚΙΜΑΣΤΙΚΗ ΑΘΛΗΤΙΚΗ Ι.Κ.Ε.",
         trade_name: "ΔΟΚΙΜΑΣΤΙΚΟ BOX",
         tax_office: "Ζ' ΑΘΗΝΩΝ",
         tax_office_code: "1118",
         street: "ΦΩΚΙΩΝΟΣ ΝΕΓΡΗ",
         building_number: "12",
         postal_code: "11361",
         city: "ΑΘΗΝΑ",
         activity_code: "93130000",
         activity_description: "ΥΠΗΡΕΣΙΕΣ ΓΥΜΝΑΣΤΗΡΙΩΝ",
         activities: [
           %{code: "93130000", description: "ΥΠΗΡΕΣΙΕΣ ΓΥΜΝΑΣΤΗΡΙΩΝ", main: true},
           %{
             code: "47641000",
             description: "ΛΙΑΝΙΚΟ ΕΜΠΟΡΙΟ ΕΙΔΩΝ ΓΥΜΝΑΣΤΙΚΗΣ",
             main: false
           }
         ],
         active: true,
         legal_status: "ΙΚΕ",
         vat_registered: true
       }}
    end
  end
end
