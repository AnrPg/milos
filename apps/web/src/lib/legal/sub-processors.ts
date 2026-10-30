// ADR-267: who processes personal data for Palee, as the code really uses
// them. Names and hosts stay as they are in every language; only the
// purpose (a key of the `legal` namespace) is translated. Keep this list in
// step with the adapters: a new outside service gets a row here.

export type SubProcessorPurpose =
  | "purposeHosting"
  | "purposeEmail"
  | "purposeSms"
  | "purposeAi"
  | "purposePush"
  | "purposeNetwork"
  | "purposePlaces"
  | "purposeMaps"
  | "purposePayments"
  | "purposeFiscalSigning"
  | "purposeTaxAuthority";

export type SubProcessor = {
  id: string;
  name: string;
  /** Where the service runs, as its operator states it; a placeholder until checked. */
  host: string;
  purpose: SubProcessorPurpose;
  /** Used only when the box turns it on (payments, fiscal documents). */
  boxFeature?: boolean;
};

/** "[…]" marks what Palee's legal adviser fills in before publication. */
export const HOSTING_PLACEHOLDER = "[…]";

export const SUB_PROCESSORS: readonly SubProcessor[] = [
  { id: "hosting", name: HOSTING_PLACEHOLDER, host: HOSTING_PLACEHOLDER, purpose: "purposeHosting" },
  { id: "brevo", name: "Brevo (Sendinblue SAS)", host: "brevo.com", purpose: "purposeEmail" },
  // ADR-280: SMS codes for the Partners phone check (`BrevoSmsSender`).
  { id: "brevo-sms", name: "Brevo (Sendinblue SAS)", host: "brevo.com", purpose: "purposeSms" },
  { id: "gemini", name: "Google Gemini API (Google)", host: "generativelanguage.googleapis.com", purpose: "purposeAi" },
  { id: "anthropic", name: "Anthropic API (Anthropic PBC)", host: "api.anthropic.com", purpose: "purposeAi" },
  { id: "apns", name: "Apple Push Notification service (Apple)", host: "api.push.apple.com", purpose: "purposePush" },
  { id: "fcm", name: "Firebase Cloud Messaging (Google)", host: "fcm.googleapis.com", purpose: "purposePush" },
  { id: "cloudflare", name: "Cloudflare", host: "cloudflare.com", purpose: "purposeNetwork" },
  { id: "photon", name: "Photon (komoot GmbH)", host: "photon.komoot.io", purpose: "purposePlaces" },
  { id: "openfreemap", name: "OpenFreeMap", host: "tiles.openfreemap.org", purpose: "purposeMaps" },
  { id: "stripe", name: "Stripe", host: "stripe.com", purpose: "purposePayments", boxFeature: true },
  { id: "viva", name: "Viva (Viva Payments)", host: "viva.com", purpose: "purposePayments", boxFeature: true },
  { id: "fiskaly", name: "fiskaly", host: "fiskaly.com", purpose: "purposeFiscalSigning", boxFeature: true },
  { id: "mydata", name: "AADE myDATA", host: "mydatapi.aade.gr", purpose: "purposeTaxAuthority", boxFeature: true },
];

/** Garmin is not Palee's processor: when you connect it, Garmin and Palee each decide for their own part. */
export const SEPARATE_CONTROLLERS = [{ id: "garmin", name: "Garmin Connect (Garmin Ltd.)", host: "connect.garmin.com" }] as const;
