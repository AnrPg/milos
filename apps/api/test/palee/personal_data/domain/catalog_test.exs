defmodule Palee.PersonalData.Domain.CatalogTest do
  use ExUnit.Case, async: true

  alias Palee.PersonalData.Domain.Catalog

  test "every entry belongs to a known section and scope, each table once" do
    entries = Catalog.entries()

    assert Enum.all?(entries, &(&1.section in Catalog.sections()))
    assert Enum.all?(entries, &(&1.scope in [:account, :tenant]))

    assert entries |> Enum.map(& &1.table) |> Enum.frequencies() |> Map.values() |> Enum.max() ==
             1

    by_scope = Catalog.entries(:account) ++ Catalog.entries(:tenant)
    assert Enum.sort_by(by_scope, & &1.table) == Enum.sort_by(entries, & &1.table)
  end

  test "every section the task names is there" do
    tables = Map.new(Catalog.entries(), &{&1.table, &1.section})

    assert tables["users"] == "profile"
    assert tables["bookings"] == "bookings"
    assert tables["journal_notes"] == "training"
    assert tables["wellness_entries"] == "wellness"
    assert tables["device_connections"] == "devices"
    assert tables["person_messages"] == "messages"
    assert tables["payment_intents"] == "payments"
    assert tables["fiscal_documents"] == "fiscal_documents"
    assert tables["document_signatures"] == "signatures"
  end

  test "messages are only the ones the person wrote" do
    for table <- ~w(person_messages buddy_messages messaging_messages partner_messages) do
      entry = Enum.find(Catalog.entries(), &(&1.table == table))
      assert match?({:eq, column} when column in ["author_id", "sender_id"], entry.subject)
    end
  end

  test "secrets, staff and other people never leave" do
    connections = Enum.find(Catalog.entries(), &(&1.table == "device_connections"))

    row = %{
      "id" => "c1",
      "provider" => "garmin",
      "access_token" => "secret",
      "refresh_token" => "secret",
      "pkce_verifier" => "secret",
      "oauth_state_hash" => "secret",
      "provider_user_id" => "garmin-123"
    }

    assert Catalog.strip(connections, row) == %{"id" => "c1", "provider" => "garmin"}

    messages = Enum.find(Catalog.entries(), &(&1.table == "person_messages"))

    assert Catalog.strip(messages, %{"body" => "hi", "user_a_id" => "a", "user_b_id" => "b"}) ==
             %{"body" => "hi"}

    logins = Enum.find(Catalog.entries(), &(&1.table == "logins"))

    assert Catalog.strip(logins, %{
             "email" => "e",
             "password_hash" => "h",
             "security_version" => 1
           }) ==
             %{"email" => "e"}

    bookings = Enum.find(Catalog.entries(), &(&1.table == "bookings"))

    assert Catalog.strip(bookings, %{"status" => "booked", "marked_by_id" => "staff"}) ==
             %{"status" => "booked"}

    methods = Enum.find(Catalog.entries(), &(&1.table == "payment_methods"))

    assert Catalog.strip(methods, %{"brand" => "visa", "token" => "tok", "token_digest" => "d"}) ==
             %{"brand" => "visa"}
  end

  test "a receipt is found through the person's payments and invoices" do
    documents = Enum.find(Catalog.entries(), &(&1.table == "fiscal_documents"))

    assert Catalog.tables(documents) == [
             "fiscal_documents",
             "payment_intents",
             "finance_invoices",
             "membership_payments",
             "memberships"
           ]
  end
end
