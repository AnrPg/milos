defmodule Palee.FakeWorldGazetteerSource do
  @moduledoc "Test stand-in for the GeoNames dump: a few towns, one a curated twin, one bad line."

  @behaviour Palee.Places.Ports.WorldGazetteerSource

  @places [
    "264371\tAthens\tAthens\tAtene,Athen,Αθήνα\t37.98376\t23.72784\tP\tPPLC\tGR\t\tESYE31\t\t\t\t664046\t\t70\tEurope/Athens\t2024-01-01",
    "4180386\tAthens\tAthens\tAthens\t33.96095\t-83.37794\tP\tPPLA2\tUS\t\tGA\t059\t\t\t127315\t\t194\tAmerica/New_York\t2024-01-01",
    "4505542\tAthens\tAthens\t\t39.32924\t-82.10126\tP\tPPLA2\tUS\t\tOH\t009\t\t\t24806\t\t211\tAmerica/New_York\t2024-01-01",
    "2867714\tMunich\tMunich\tMuenchen,München,Μόναχο\t48.13743\t11.57549\tP\tPPLA\tDE\t\t02\t091\t09162\t09162000\t1260391\t\t524\tEurope/Berlin\t2024-01-01",
    "6545310\tKreuzberg\tKreuzberg\t\t52.49973\t13.40338\tP\tPPLX\tDE\t\t16\t00\t11000\t11000000\t147227\t\t46\tEurope/Berlin\t2024-01-01",
    "1\tOld Town\tOld Town\t\t10.0\t10.0\tP\tPPLH\tZZ\t\t\t\t\t\t900\t\t\t\t2024-01-01",
    "broken line"
  ]

  @admin1 [
    "GR.ESYE31\tAttica\tAttica\t6692632",
    "US.GA\tGeorgia\tGeorgia\t4197000",
    "US.OH\tOhio\tOhio\t5165418",
    "DE.02\tBavaria\tBavaria\t2951839",
    "DE.16\tBerlin\tBerlin\t2950157"
  ]

  @countries [
    "# ISO\tISO3\tISO-Numeric\tfips\tCountry",
    "GR\tGRC\t300\tGR\tGreece",
    "US\tUSA\t840\tUS\tUnited States",
    "DE\tDEU\t276\tGM\tGermany"
  ]

  @impl true
  def fetch do
    case Process.get(:world_gazetteer_source) do
      :down -> {:error, :source_unavailable}
      _up -> {:ok, %{places: @places, admin1: @admin1, countries: @countries}}
    end
  end
end
