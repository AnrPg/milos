defmodule Palee.Email.Templates.OrganizationInvitationTest do
  use ExUnit.Case, async: true

  alias Palee.Email.Templates.OrganizationInvitation

  @locales ~w(ar bg de el en es fr he it nl pt_PT ru)
  @po_dir Path.expand("../../../../priv/gettext", __DIR__)

  @assigns %{
    business: "Box <Kypseli> & Co",
    inviter: "Apostolos",
    roles: [:coach, :front_desk],
    branches: ["Κηφισιά", "Μαρούσι"],
    expires: "31/12/2026 18:00",
    url: "https://palee.app/invite#token=abc"
  }

  test "every locale translates every string" do
    for locale <- @locales do
      po =
        Expo.PO.parse_file!(Path.join([@po_dir, locale, "LC_MESSAGES", "invitation_emails.po"]))

      translated =
        Map.new(po.messages, fn message ->
          {IO.iodata_to_binary(message.msgid), IO.iodata_to_binary(message.msgstr)}
        end)

      for msgid <- OrganizationInvitation.msgids() do
        assert translated[msgid] not in [nil, ""], "#{locale} lacks #{inspect(msgid)}"
      end
    end
  end

  test "renders roles, branches, the inviter and the link, escaping the business name" do
    html = OrganizationInvitation.html(@assigns, "en")
    text = OrganizationInvitation.text(@assigns, "en")

    assert OrganizationInvitation.subject(@assigns, "en") ==
             "Your invitation to Box <Kypseli> & Co"

    assert html =~ "Box &lt;Kypseli&gt; &amp; Co"
    refute html =~ "<Kypseli>"
    assert text =~ "Apostolos invited you to join Box <Kypseli> & Co"
    assert text =~ "Coach, Front desk"
    assert text =~ "Κηφισιά, Μαρούσι"
    assert text =~ "31/12/2026 18:00"
    assert html =~ "https://palee.app/invite#token=abc"
  end

  test "Greek reads formally, quotes the business and names the client role" do
    assigns = %{@assigns | roles: [:member], branches: nil, inviter: nil}
    text = OrganizationInvitation.text(assigns, "el")

    assert OrganizationInvitation.subject(assigns, "el") =~ "«Box <Kypseli> & Co»"
    assert text =~ "Μέλος box"
    assert text =~ "σε προσκαλεί"
    refute text =~ "Παραρτήματα"
  end

  test "Arabic and Hebrew are laid out right to left" do
    assert OrganizationInvitation.html(@assigns, "ar") =~ ~s(dir="rtl")
    assert OrganizationInvitation.html(@assigns, "he") =~ ~s(dir="rtl")
  end

  test "is transactional mail with its own throttle" do
    assert OrganizationInvitation.category() == :transactional
    assert %{min_interval_seconds: 120, max_per_day: 5} = OrganizationInvitation.throttle()
  end
end
