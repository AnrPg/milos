defmodule Palee.Imports.Domain.Presets do
  @moduledoc """
  ADR-254: the column names of the systems boxes move from. Pure.

  **These are best guesses.** None of these vendors publishes a stable
  export format; the names below come from their help pages, screenshots
  and the files of boxes that moved before, and they change between
  versions and languages. They only *propose* a mapping; the person
  importing always sees and can change it, and every preset also accepts
  the generic English and Greek names (`excel`).

  `date_order` is the order the vendor most often writes dates in (the US
  vendors write month first); it too is only the proposal.
  """

  @generic %{
    "full_name" => [
      "name",
      "full name",
      "client name",
      "member name",
      "customer name",
      "athlete name",
      "ονοματεπωνυμο",
      "ονομα και επωνυμο",
      "πελατης",
      "μελος"
    ],
    "first_name" => ["first name", "firstname", "given name", "first", "ονομα"],
    "last_name" => ["last name", "lastname", "surname", "family name", "last", "επωνυμο"],
    "email" => [
      "email",
      "e mail",
      "email address",
      "e mail address",
      "mail",
      "ηλεκτρονικο ταχυδρομειο",
      "διευθυνση email"
    ],
    "phone" => [
      "phone",
      "mobile",
      "mobile phone",
      "cell",
      "cell phone",
      "phone number",
      "telephone",
      "τηλεφωνο",
      "κινητο",
      "κινητο τηλεφωνο",
      "τηλ"
    ],
    "role" => ["role", "type", "member type", "ρολος", "ιδιοτητα"],
    "joined_on" => [
      "join date",
      "joined",
      "joined on",
      "member since",
      "start date",
      "created",
      "created date",
      "sign up date",
      "registration date",
      "ημερομηνια εγγραφης",
      "εγγραφη",
      "μελος απο"
    ],
    "membership_status" => ["status", "member status", "membership status", "κατασταση"],
    "notes" => ["notes", "note", "comments", "σημειωσεις", "σχολια"],
    "external_id" => ["id", "member id", "client id", "customer id", "κωδικος", "αριθμος μελους"],
    "package_name" => [
      "membership",
      "membership name",
      "plan",
      "plan name",
      "package",
      "subscription",
      "πακετο",
      "πακετο συνδρομης",
      "συνδρομη"
    ],
    "package_price" => ["price", "membership price", "plan price", "τιμη", "κοστος"],
    "package_starts_on" => [
      "membership start",
      "membership start date",
      "plan start",
      "plan start date",
      "εναρξη",
      "ημερομηνια εναρξης",
      "εναρξη συνδρομης"
    ],
    "package_ends_on" => [
      "membership end",
      "membership end date",
      "plan end",
      "plan end date",
      "end date",
      "expiry",
      "expiry date",
      "expires",
      "ληξη",
      "ημερομηνια ληξης",
      "ληξη συνδρομης"
    ],
    "credit_balance" => [
      "balance",
      "credit",
      "account balance",
      "credit balance",
      "υπολοιπο",
      "πιστωση"
    ],
    "payment_amount" => ["amount", "payment amount", "paid", "total", "ποσο", "πληρωμη"],
    "payment_date" => [
      "payment date",
      "paid on",
      "transaction date",
      "date paid",
      "ημερομηνια πληρωμης"
    ],
    "payment_method" => [
      "payment method",
      "method",
      "payment type",
      "tender",
      "τροπος πληρωμης"
    ],
    "payment_note" => ["description", "memo", "payment note", "περιγραφη", "αιτιολογια"],
    "visit_date" => [
      "visit date",
      "check in date",
      "checkin date",
      "check in",
      "attendance date",
      "class date",
      "επισκεψη",
      "ημερομηνια επισκεψης",
      "παρουσια"
    ]
  }

  @presets [
    %{
      key: "wodify",
      name: "Wodify",
      date_order: "mdy",
      headers: %{
        "first_name" => ["client first name", "athlete first name"],
        "last_name" => ["client last name", "athlete last name"],
        "full_name" => ["client", "athlete"],
        "email" => ["client email", "athlete email", "email address"],
        "phone" => ["mobile phone", "cell phone", "phone"],
        "membership_status" => ["client status", "athlete status"],
        "joined_on" => ["member since date", "client since", "athlete since", "created on"],
        "external_id" => ["client user id number", "client id", "athlete id"],
        "package_name" => ["membership", "membership name", "current membership"],
        "package_starts_on" => ["membership start date", "membership start"],
        "package_ends_on" => ["membership end date", "membership end"],
        "payment_amount" => ["amount paid", "transaction amount"],
        "payment_date" => ["transaction date", "payment date"],
        "payment_method" => ["payment method", "tender type"],
        "visit_date" => ["sign in date", "class date"]
      }
    },
    %{
      key: "pushpress",
      name: "PushPress",
      date_order: "mdy",
      headers: %{
        "first_name" => ["first_name", "first name"],
        "last_name" => ["last_name", "last name"],
        "email" => ["email"],
        "phone" => ["phone", "phone_number"],
        "membership_status" => ["status", "customer status"],
        "joined_on" => ["member_since", "member since", "created_at"],
        "external_id" => ["customer_id", "customer id"],
        "package_name" => ["plan", "plan_name", "plan name"],
        "package_price" => ["plan_price", "plan price"],
        "package_starts_on" => ["plan_start_date", "plan start date"],
        "package_ends_on" => ["plan_end_date", "plan end date"],
        "payment_amount" => ["amount", "charge amount"],
        "payment_date" => ["charge date", "date"],
        "payment_method" => ["payment method", "method"],
        "visit_date" => ["checkin date", "check in date", "checkin_date"]
      }
    },
    %{
      key: "zen_planner",
      name: "Zen Planner",
      date_order: "mdy",
      headers: %{
        "first_name" => ["first name"],
        "last_name" => ["last name"],
        "email" => ["email", "primary email"],
        "phone" => ["mobile phone", "home phone", "work phone"],
        "membership_status" => ["member status", "status"],
        "joined_on" => ["join date", "created date"],
        "external_id" => ["person id", "member id"],
        "package_name" => ["membership label", "membership", "membership name"],
        "package_price" => ["membership price", "price"],
        "package_starts_on" => ["begin date", "membership begin date"],
        "package_ends_on" => ["end date", "membership end date"],
        "payment_amount" => ["payment amount", "amount"],
        "payment_date" => ["payment date"],
        "payment_method" => ["payment type", "payment method"],
        "visit_date" => ["attendance date", "date attended"]
      }
    },
    %{
      key: "arbox",
      name: "Arbox",
      date_order: "dmy",
      headers: %{
        "first_name" => ["first name"],
        "last_name" => ["last name"],
        "email" => ["email"],
        "phone" => ["phone", "mobile"],
        "membership_status" => ["status", "member status"],
        "joined_on" => ["registration date", "join date"],
        "external_id" => ["member id", "id"],
        "package_name" => ["membership type", "membership", "plan"],
        "package_price" => ["price", "membership price"],
        "package_starts_on" => ["start", "start date", "membership start"],
        "package_ends_on" => ["end", "end date", "membership end"],
        "credit_balance" => ["balance", "debt"],
        "payment_amount" => ["amount", "paid amount"],
        "payment_date" => ["payment date", "date"],
        "payment_method" => ["payment method"],
        "visit_date" => ["check in date", "last entrance", "entrance date"]
      }
    },
    %{key: "excel", name: "Excel", date_order: "dmy", headers: %{}}
  ]

  @keys Enum.map(@presets, & &1.key)

  def keys, do: @keys

  @doc "Every preset with its headers (the vendor's first, then the generic ones)."
  def all, do: Enum.map(@presets, &with_generic/1)

  def fetch(key) do
    case Enum.find(@presets, &(&1.key == key)) do
      nil -> :error
      preset -> {:ok, with_generic(preset)}
    end
  end

  def public(preset), do: Map.take(preset, [:key, :name, :date_order])

  @doc "The normalized names only this vendor uses (not among the generic ones)."
  def distinctive_names(key) do
    generic = @generic |> Map.values() |> List.flatten() |> MapSet.new(&normalize/1)

    case Enum.find(@presets, &(&1.key == key)) do
      nil ->
        MapSet.new()

      preset ->
        preset.headers
        |> Map.values()
        |> List.flatten()
        |> MapSet.new(&normalize/1)
        |> MapSet.difference(generic)
    end
  end

  defp with_generic(preset) do
    headers =
      Map.merge(@generic, preset.headers, fn _field, generic, own -> own ++ generic end)
      |> Map.new(fn {field, names} -> {field, names |> Enum.map(&normalize/1) |> Enum.uniq()} end)

    %{preset | headers: headers}
  end

  @doc "A header as presets compare it: lower case, no accents, words only."
  def normalize(header) when is_binary(header) do
    header
    |> Palee.Imports.Domain.Values.fold()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end
end
