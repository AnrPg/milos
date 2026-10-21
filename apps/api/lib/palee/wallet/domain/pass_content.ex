defmodule Palee.Wallet.Domain.PassContent do
  @moduledoc """
  What a Wallet card says, independent of Apple or Google (ADR-155): the box,
  the member, the barcode, the next booking and the box's locations. Built
  by the application layer; the platform modules turn it into a pass.json or
  a Google pass object. The copy follows the member's language (Greek or
  English).
  """

  @enforce_keys [:serial, :box, :member, :barcode]
  defstruct [
    :serial,
    :box,
    :member,
    :barcode,
    :next_booking,
    :updated_at,
    locale: "el",
    locations: [],
    revoked?: false
  ]

  @type t :: %__MODULE__{
          serial: String.t(),
          box: %{name: String.t(), slug: String.t(), primary_color: String.t() | nil},
          member: %{name: String.t()},
          barcode: String.t(),
          next_booking:
            %{name: String.t(), starts_at: DateTime.t(), place: String.t() | nil} | nil,
          updated_at: DateTime.t() | nil,
          locale: String.t(),
          locations: [%{latitude: float(), longitude: float(), name: String.t() | nil}],
          revoked?: boolean()
        }

  @copy %{
    "el" => %{
      member: "Μέλος",
      next: "Επόμενη κράτηση",
      class: "Μάθημα",
      none: "Καμία κράτηση",
      description: "Κάρτα check-in",
      how: "Δείξε τον κωδικό στην είσοδο. Η κάρτα ενημερώνεται όταν κλείνεις ή ακυρώνεις θέση.",
      how_label: "Check-in",
      revoked: "Η κάρτα ανακλήθηκε",
      near: "Είσαι κοντά στο box"
    },
    "en" => %{
      member: "Member",
      next: "Next booking",
      class: "Class",
      none: "No booking",
      description: "Check-in card",
      how: "Show the code at the entrance. The card updates when you book or cancel.",
      how_label: "Check-in",
      revoked: "This card was revoked",
      near: "You're near the box"
    }
  }

  @doc "The card's copy in its language (Greek or English)."
  def copy(%__MODULE__{locale: locale}), do: Map.get(@copy, language(locale), @copy["en"])

  defp language("el" <> _rest), do: "el"
  defp language(_locale), do: "en"

  @doc "`#RRGGBB` as `rgb(r, g, b)`, or nil."
  def rgb(nil), do: nil

  def rgb("#" <> hex) when byte_size(hex) == 6 do
    case Integer.parse(hex, 16) do
      {value, ""} ->
        <<r, g, b>> = <<value::24>>
        "rgb(#{r}, #{g}, #{b})"

      _invalid ->
        nil
    end
  end

  def rgb(_color), do: nil

  @doc "Black or white text, whichever reads better on the colour."
  def foreground(nil), do: "rgb(255, 255, 255)"

  def foreground("#" <> hex) when byte_size(hex) == 6 do
    case Integer.parse(hex, 16) do
      {value, ""} ->
        <<r, g, b>> = <<value::24>>
        if r * 299 + g * 587 + b * 114 > 150_000, do: "rgb(0, 0, 0)", else: "rgb(255, 255, 255)"

      _invalid ->
        foreground(nil)
    end
  end

  def foreground(_color), do: foreground(nil)
end
