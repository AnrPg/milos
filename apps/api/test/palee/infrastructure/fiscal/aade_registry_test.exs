defmodule Palee.Infrastructure.Fiscal.AadeRegistryTest do
  @moduledoc "ADR-265: the RgWsPublic2 adapter's SOAP request and how answers are read (Req.Test stub)."

  use ExUnit.Case, async: false

  alias Palee.Infrastructure.Fiscal.AadeRegistry

  @connection %{environment: "production", user_id: "BOXUSER", subscription_key: "s3cr<et>&"}

  @found """
  <?xml version="1.0" encoding="UTF-8"?>
  <env:Envelope xmlns:env="http://www.w3.org/2003/05/soap-envelope"><env:Header/><env:Body>
  <srvc:rgWsPublic2AfmMethodResponse xmlns:srvc="http://rgwspublic2/RgWsPublic2Service" xmlns="http://rgwspublic2/RgWsPublic2">
  <srvc:result><rg_ws_public2_result_rtType>
  <call_seq_id>48812345</call_seq_id>
  <error_rec><error_code/><error_descr/></error_rec>
  <basic_rec>
    <afm>090000045</afm><doy>1118</doy><doy_descr>Ζ' ΑΘΗΝΩΝ</doy_descr>
    <i_ni_flag_descr>ΜΗ ΦΠ</i_ni_flag_descr><deactivation_flag>1</deactivation_flag>
    <deactivation_flag_descr>ΕΝΕΡΓΟΣ ΑΦΜ</deactivation_flag_descr>
    <firm_flag_descr>ΕΠΙΤΗΔΕΥΜΑΤΙΑΣ</firm_flag_descr>
    <onomasia>ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ ΙΔΙΩΤΙΚΗ ΚΕΦΑΛΑΙΟΥΧΙΚΗ ΕΤΑΙΡΕΙΑ</onomasia>
    <commer_title>ΚΥΨΕΛΗ STRONG</commer_title><legal_status_descr>ΙΚΕ</legal_status_descr>
    <postal_address>ΦΩΚΙΩΝΟΣ ΝΕΓΡΗ</postal_address><postal_address_no>12</postal_address_no>
    <postal_zip_code>11361</postal_zip_code><postal_area_description>ΑΘΗΝΑ</postal_area_description>
    <regist_date>2019-03-01</regist_date><stop_date/><normal_vat_system_flag>Y</normal_vat_system_flag>
  </basic_rec>
  <firm_act_tab>
    <item><firm_act_code>47641000</firm_act_code><firm_act_descr>ΛΙΑΝΙΚΟ ΕΜΠΟΡΙΟ ΕΙΔΩΝ ΓΥΜΝΑΣΤΙΚΗΣ</firm_act_descr><firm_act_kind>2</firm_act_kind><firm_act_kind_descr>ΔΕΥΤΕΡΕΥΟΥΣΑ</firm_act_kind_descr></item>
    <item><firm_act_code>93130000</firm_act_code><firm_act_descr>ΥΠΗΡΕΣΙΕΣ ΓΥΜΝΑΣΤΗΡΙΩΝ</firm_act_descr><firm_act_kind>1</firm_act_kind><firm_act_kind_descr>ΚΥΡΙΑ</firm_act_kind_descr></item>
  </firm_act_tab>
  </rg_ws_public2_result_rtType></srvc:result></srvc:rgWsPublic2AfmMethodResponse>
  </env:Body></env:Envelope>
  """

  defp failure(code) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <env:Envelope xmlns:env="http://www.w3.org/2003/05/soap-envelope"><env:Body>
    <srvc:rgWsPublic2AfmMethodResponse xmlns:srvc="http://rgwspublic2/RgWsPublic2Service">
    <srvc:result><rg_ws_public2_result_rtType>
    <error_rec><error_code>#{code}</error_code><error_descr>…</error_descr></error_rec>
    </rg_ws_public2_result_rtType></srvc:result></srvc:rgWsPublic2AfmMethodResponse>
    </env:Body></env:Envelope>
    """
  end

  defp stub(status, body) do
    test_pid = self()

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      {:ok, request, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request, conn, request})

      conn
      |> Plug.Conn.put_resp_content_type("application/soap+xml")
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  test "asks with a WS-Security UsernameToken and reads the registry details" do
    stub(200, @found)

    assert {:ok, business} = AadeRegistry.lookup(@connection, "090000045", ~D[2027-02-21])

    assert_received {:request, conn, request}
    assert conn.method == "POST"
    assert conn.request_path == "/wsaade/RgWsPublic2/RgWsPublic2"
    assert [content_type] = Plug.Conn.get_req_header(conn, "content-type")
    assert content_type =~ "application/soap+xml"
    assert request =~ "<ns1:Username>BOXUSER</ns1:Username>"
    # The password is escaped, never raw XML.
    assert request =~ "<ns1:Password>s3cr&lt;et&gt;&amp;</ns1:Password>"
    assert request =~ "<ns3:afm_called_for>090000045</ns3:afm_called_for>"
    assert request =~ "<ns3:as_on_date>2027-02-21</ns3:as_on_date>"

    assert business == %{
             tax_id: "090000045",
             legal_name: "ΚΥΨΕΛΗ ΑΘΛΗΤΙΚΗ ΙΔΙΩΤΙΚΗ ΚΕΦΑΛΑΙΟΥΧΙΚΗ ΕΤΑΙΡΕΙΑ",
             trade_name: "ΚΥΨΕΛΗ STRONG",
             tax_office: "Ζ' ΑΘΗΝΩΝ",
             tax_office_code: "1118",
             street: "ΦΩΚΙΩΝΟΣ ΝΕΓΡΗ",
             building_number: "12",
             postal_code: "11361",
             city: "ΑΘΗΝΑ",
             activity_code: "93130000",
             activity_description: "ΥΠΗΡΕΣΙΕΣ ΓΥΜΝΑΣΤΗΡΙΩΝ",
             activities: [
               %{code: "47641000", description: "ΛΙΑΝΙΚΟ ΕΜΠΟΡΙΟ ΕΙΔΩΝ ΓΥΜΝΑΣΤΙΚΗΣ", main: false},
               %{code: "93130000", description: "ΥΠΗΡΕΣΙΕΣ ΓΥΜΝΑΣΤΗΡΙΩΝ", main: true}
             ],
             active: true,
             legal_status: "ΙΚΕ",
             vat_registered: true
           }
  end

  test "the authority's error codes become the port's reasons" do
    for {code, reason} <- [
          {"RG_WS_PUBLIC_TOKEN_USERNAME_NOT_AUTHENTICATED", :credentials_rejected},
          {"RG_WS_PUBLIC_TOKEN_AFM_NOT_REGISTERED", :credentials_rejected},
          {"RG_WS_PUBLIC_WRONG_AFM", :not_found},
          {"RG_WS_PUBLIC_TAXPAYER_NF", :not_found},
          {"RG_WS_PUBLIC_MONTHLY_LIMIT_EXCEEDED", :limit_reached},
          {"RG_WS_PUBLIC_SERVICE_NOT_ACTIVE", :unavailable}
        ] do
      stub(200, failure(code))
      assert AadeRegistry.lookup(@connection, "090000045", ~D[2027-02-21]) == {:error, reason}
    end
  end

  test "server errors and broken answers are unavailable; missing credentials never call" do
    stub(500, "<html>down</html>")
    assert AadeRegistry.lookup(@connection, "090000045", ~D[2027-02-21]) == {:error, :unavailable}

    stub(200, "<not-xml")
    assert AadeRegistry.lookup(@connection, "090000045", ~D[2027-02-21]) == {:error, :unavailable}

    stub(200, @found)

    assert AadeRegistry.lookup(%{@connection | subscription_key: nil}, "090000045", ~D[2027-02-21]) ==
             {:error, :credentials_rejected}

    refute_received {:request, _conn, _body}
  end
end
