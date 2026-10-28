defmodule Palee.Email.Templates.LinkEmailsTest do
  # ADR-210: :owner_invitation and :share_link render in every locale, with
  # escaped input and no raw invitation code.
  use ExUnit.Case, async: true

  alias Palee.Email.Templates.{OwnerInvitation, ShareLink}

  @locales ~w(ar bg de el en es fr he it nl pt_PT ru)

  test "every locale has every string of both domains" do
    for domain <- ~w(owner_invitations share_links) do
      msgids =
        Regex.scan(~r/^msgid "(.+)"$/m, File.read!("priv/gettext/#{domain}.pot"),
          capture: :all_but_first
        )
        |> List.flatten()

      assert msgids != []

      for dir <- @locales do
        po = File.read!(Path.join(["priv/gettext", dir, "LC_MESSAGES", "#{domain}.po"]))

        for msgid <- msgids do
          assert po =~ ~s(msgid "#{msgid}"\nmsgstr "), "#{dir} lacks #{msgid}"
          refute po =~ ~s(msgid "#{msgid}"\nmsgstr ""\n), "#{dir} leaves #{msgid} untranslated"
        end
      end
    end
  end

  describe "owner invitation" do
    @assigns %{
      business: "Iron <Gym>",
      role: :owner,
      url: "https://palee.test/set-admin?token=abc"
    }

    test "Greek, with the business quoted and escaped, the link and no setup code" do
      assert OwnerInvitation.category() == :account
      assert OwnerInvitation.subject(@assigns, "el") =~ "ιδιοκτήτη"
      assert OwnerInvitation.subject(@assigns, "el") =~ "«Iron <Gym>»"

      html = OwnerInvitation.html(@assigns, "el")
      assert html =~ "Iron &lt;Gym&gt;"
      refute html =~ "Iron <Gym>"
      assert html =~ "set-admin?token=abc"
      refute html =~ ~r/setup code|κωδικ/i

      text = OwnerInvitation.text(@assigns, "el")
      assert text =~ "https://palee.test/set-admin?token=abc"
    end

    test "an admin invitation says admin" do
      assigns = %{@assigns | role: :admin}
      assert OwnerInvitation.subject(assigns, "en") == "Set up your admin account for Iron <Gym>"
    end

    test "renders in every locale" do
      for locale <- ["pt-PT" | @locales -- ["pt_PT"]] do
        assert OwnerInvitation.subject(@assigns, locale) =~ "Iron <Gym>"
        assert OwnerInvitation.text(@assigns, locale) =~ @assigns.url
      end
    end
  end

  describe "share link" do
    test "names the sender, warns strangers and carries the link" do
      for link <- [:guest_pass, :buddy_invite, :referral] do
        assigns = %{link: link, name: "Maria <b>", url: "https://palee.test/r/ABC"}

        assert ShareLink.subject(assigns, "en") =~ "Maria <b>"
        text = ShareLink.text(assigns, "en")
        assert text =~ "If you don't know them, ignore this email."
        assert text =~ "https://palee.test/r/ABC"

        html = ShareLink.html(assigns, "el")
        assert html =~ "Maria &lt;b&gt;"
        assert html =~ "Αν δεν γνωρίζεις αυτό το άτομο"
      end
    end

    test "is transactional and throttled per recipient" do
      assert ShareLink.category() == :transactional
      assert %{max_per_day: 5} = ShareLink.throttle()
    end
  end
end
