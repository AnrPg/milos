defmodule PaleeWeb.ShareLinkEmailControllerTest do
  @moduledoc """
  ADR-210: "Send by email" of a guest pass, a check-in buddy invite link and
  «Φέρε φίλο»: only the sender's own live links, from a verified sender,
  within the daily limit, never from a mock person or a demo business.
  """

  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.EmailCase
  import Palee.TestFixtures

  alias Palee.{Identity, Organizations, Repo}
  alias Palee.Application.EventInvites
  alias Palee.Email.Domain.ShareLinkPolicy

  @path "/api/me/share-links/email"

  setup %{conn: conn} do
    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Share Gym #{System.unique_integer([:positive])}"
      })

    member = member!(organization, %{display_name: "Μαρία Π.", preferred_locale: "el"})
    :ok = Identity.mark_email_verified(member.login_id, member.email)

    %{
      organization: organization,
      member: member,
      as: fn user -> put_bearer_token(conn, user) end,
      me: "/api/org/#{organization.slug}/me"
    }
  end

  defp member!(organization, attrs) do
    user = user_fixture(attrs)

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    user
  end

  defp send_link(ctx, user, body) do
    ctx.as.(user)
    |> put_req_header("content-type", "application/json")
    |> post(@path, Jason.encode!(body))
  end

  defp guest_pass(ctx, user \\ nil),
    do:
      EventInvites.sign(
        %{id: Ecto.UUID.generate(), organization_id: ctx.organization.id},
        (user || ctx.member).id
      )

  defp referral_code(ctx, user),
    do: ctx.as.(user) |> get("#{ctx.me}/referrals") |> json_response(200) |> Map.fetch!("code")

  test "emails the member's «Φέρε φίλο» link in their language, once per address", ctx do
    code = referral_code(ctx, ctx.member)
    body = %{link: "referral", token: code, to: "Friend@Example.test"}

    assert %{"delivery" => %{"id" => id, "status" => "queued"}} =
             ctx |> send_link(ctx.member, body) |> json_response(202)

    message = assert_email_enqueued(kind: :share_link, to: "friend@example.test")
    assert message.id == id
    assert message.category == "transactional"
    assert message.organization_id == ctx.organization.id
    assert message.locale == "el"
    assert message.subject =~ "Μαρία Π."
    assert message.text =~ "/r/#{code}"
    assert message.text =~ "Αν δεν γνωρίζεις αυτό το άτομο"

    assert String.starts_with?(
             message.idempotency_key,
             ShareLinkPolicy.sender_prefix(ctx.member.id)
           )

    # The same link to the same address is not sent twice.
    assert %{"delivery" => %{"id" => ^id}} =
             ctx |> send_link(ctx.member, body) |> json_response(202)

    assert [_one] = enqueued_emails(kind: :share_link)
  end

  test "emails a guest pass and a check-in buddy invite link", ctx do
    token = guest_pass(ctx)

    ctx
    |> send_link(ctx.member, %{link: "guest_pass", token: token, to: "guest@example.test"})
    |> json_response(202)

    assert assert_email_enqueued(kind: :share_link, to: "guest@example.test").text =~
             "?invite=#{URI.encode_www_form(token)}"

    %{"token" => buddy_token} =
      ctx.as.(ctx.member) |> post("/api/me/buddies/invite-links") |> json_response(201)

    ctx
    |> send_link(ctx.member, %{link: "buddy_invite", token: buddy_token, to: "buddy@example.test"})
    |> json_response(202)

    message = assert_email_enqueued(kind: :share_link, to: "buddy@example.test")
    assert message.text =~ "/buddy-invite/#{buddy_token}"
    assert message.organization_id == nil
  end

  test "only the sender's own links", ctx do
    other = member!(ctx.organization, %{})
    :ok = Identity.mark_email_verified(other.login_id, other.email)

    for body <- [
          %{link: "referral", token: referral_code(ctx, other), to: "x@example.test"},
          %{link: "guest_pass", token: guest_pass(ctx, other), to: "x@example.test"},
          %{link: "guest_pass", token: "forged", to: "x@example.test"},
          %{link: "owner_invitation", token: "anything", to: "x@example.test"}
        ] do
      assert %{"code" => "share_link_invalid"} =
               ctx |> send_link(ctx.member, body) |> json_response(404)
    end

    refute_email_enqueued(kind: :share_link)
  end

  test "an unverified sender is asked to confirm their own email first", ctx do
    unverified = member!(ctx.organization, %{})
    body = %{link: "guest_pass", token: guest_pass(ctx, unverified), to: "x@example.test"}

    assert %{"code" => "share_link_sender_unverified"} =
             ctx |> send_link(unverified, body) |> json_response(403)

    refute_email_enqueued(kind: :share_link)
  end

  test "a mock person and a demo business never send", ctx do
    n = System.unique_integer([:positive])

    {:ok, mock} =
      Identity.register_demo_person(ctx.organization.id, %{
        nickname: "mock_#{n}",
        password: "S3cur3P@ss!42",
        role: :member,
        email: "mock_#{n}@placeholder.invalid"
      })

    :ok = Identity.mark_email_verified(mock.login_id, mock.email)

    body = %{link: "guest_pass", token: guest_pass(ctx, mock), to: "x@example.test"}

    assert %{"code" => "business_not_activated"} =
             ctx |> send_link(mock, body) |> json_response(403)

    Repo.update_all(
      from(organization in "organizations",
        where: organization.id == type(^ctx.organization.id, :binary_id)
      ),
      set: [activation: "demo"]
    )

    body = %{link: "guest_pass", token: guest_pass(ctx), to: "x@example.test"}

    assert %{"code" => "business_not_activated"} =
             ctx |> send_link(ctx.member, body) |> json_response(403)

    refute_email_enqueued(kind: :share_link)
  end

  test "a suppressed or malformed recipient is refused", ctx do
    {:ok, _suppression} = Palee.Email.suppress("bounced@example.test", :bounce)

    assert %{"code" => "suppressed"} =
             ctx
             |> send_link(ctx.member, %{
               link: "guest_pass",
               token: guest_pass(ctx),
               to: "bounced@example.test"
             })
             |> json_response(422)

    assert %{"code" => "invalid_address"} =
             ctx
             |> send_link(ctx.member, %{
               link: "guest_pass",
               token: guest_pass(ctx),
               to: "Jo <jo@example.test>"
             })
             |> json_response(422)
  end

  test "ten a day per sender", ctx do
    for n <- 1..ShareLinkPolicy.daily_limit() do
      ctx
      |> send_link(ctx.member, %{
        link: "guest_pass",
        token: guest_pass(ctx),
        to: "friend#{n}@example.test"
      })
      |> json_response(202)
    end

    assert %{"code" => "share_link_daily_limit"} =
             ctx
             |> send_link(ctx.member, %{
               link: "guest_pass",
               token: guest_pass(ctx),
               to: "one-more@example.test"
             })
             |> json_response(429)
  end
end
