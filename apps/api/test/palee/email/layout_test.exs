defmodule Palee.Email.LayoutTest do
  use ExUnit.Case, async: true

  alias Palee.Email.Layout

  @url "https://palee.app/verify?token=a&b=<c>"

  defp render(locale) do
    {
      Layout.html(locale, [
        Layout.heading("Hi <script>"),
        Layout.paragraph("Tom & \"Jerry\""),
        Layout.button(Layout.t(locale, "Hello,"), @url),
        Layout.fallback_link(locale, @url)
      ]),
      Layout.text(locale, ["Hi <script>", Layout.text_button("Open", @url)])
    }
  end

  test "English: theme colours, escaped values, product name and the footer reason" do
    {html, text} = render("en")

    assert html =~ ~s(<html lang="en" dir="ltr">)
    assert html =~ Palee.BrandPalette.colour(:primary)
    assert html =~ "Hi &lt;script&gt;"
    assert html =~ "Tom &amp; &quot;Jerry&quot;"
    assert html =~ ~s(href="https://palee.app/verify?token=a&amp;b=&lt;c&gt;")
    refute html =~ "<script>"
    assert html =~ "If the button doesn&#39;t work, copy this link into your browser:"
    assert html =~ "You&#39;re receiving this email because you have a Palee account."
    assert html =~ "This email was sent automatically by Palee."

    assert text =~ "Hi <script>\n\nOpen:\n#{@url}"
    assert text =~ "-- \nYou're receiving this email because you have a Palee account."
    refute html =~ ~r/milos/i
    refute text =~ ~r/milos/i
  end

  test "Greek: the strings come from the emails domain" do
    {html, text} = render("el")

    assert html =~ ~s(<html lang="el" dir="ltr">)
    assert html =~ "Γεια σας,"
    assert html =~ "Αν το κουμπί δεν λειτουργεί, αντιγράψτε αυτόν τον σύνδεσμο"
    assert text =~ "Λαμβάνετε αυτό το email επειδή έχετε λογαριασμό στο Palee."
    assert text =~ "Αυτό το email στάλθηκε αυτόματα από το Palee."
  end

  test "Arabic and Hebrew are right to left; a business reason names the business" do
    html = Layout.html("he", [], reason: Layout.reason("he", {:business, "Box <Kypseli>"}))
    assert html =~ ~s(dir="rtl")
    assert html =~ "Box &lt;Kypseli&gt;"
    assert Layout.html("ar", []) =~ ~s(<html lang="ar" dir="rtl">)
    assert Layout.html("pt_PT", []) =~ ~s(lang="pt-PT")
  end

  test "every locale has every emails string" do
    msgids =
      "priv/gettext/emails.pot"
      |> File.read!()
      |> then(&Regex.scan(~r/^msgid "(.+)"$/m, &1))
      |> Enum.map(&List.last/1)

    for dir <- File.ls!("priv/gettext"), File.dir?(Path.join("priv/gettext", dir)) do
      po = File.read!(Path.join(["priv/gettext", dir, "LC_MESSAGES", "emails.po"]))

      for msgid <- msgids do
        assert po =~ ~s(msgid "#{msgid}"\nmsgstr "), "#{dir} lacks #{msgid}"
        refute po =~ ~s(msgid "#{msgid}"\nmsgstr ""\n), "#{dir} leaves #{msgid} untranslated"
      end
    end
  end
end
