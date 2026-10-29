import { ApiError, apiRequest } from "@/api/client";

/**
 * Documents and simple electronic signatures (ADR-252, V3-M8).
 *
 * Staff (`/admin/documents/...`): the box's documents with their versions,
 * which are mandatory («Υποχρεωτικό») or optional («Προαιρετικό»), signature
 * requests, signatures with their PDF certificate, the booking gate settings
 * and health certificates. Clients (`/me/documents/...`): what to sign, the
 * text to read and sign, their signatures and their health certificate.
 *
 * The shapes mirror `PaleeWeb.Schemas.Documents`.
 */

export type DocumentKind = "waiver" | "terms" | "privacy" | "health_certificate" | "other";
export type DocumentRequirement = "mandatory" | "optional";
export type ChangeKind = "major" | "minor";
export type SignatureStatus = "signed" | "unsigned" | "resign_required";
export type HealthStatus = "missing" | "valid" | "expiring" | "expired";
export type RequestAudience = "person" | "all_clients" | "role" | "package";
export type HealthContentType = "application/pdf" | "image/jpeg" | "image/png" | "image/webp";

export const HEALTH_CONTENT_TYPES: HealthContentType[] = ["application/pdf", "image/jpeg", "image/png", "image/webp"];

export type DocumentVersion = {
  id: string;
  template_id: string;
  number: number;
  title: string;
  language: string;
  change_kind: ChangeKind;
  content_hash: string;
  published_by_id: string | null;
  published_at: string;
  body?: string;
};

export type DocumentTemplate = {
  id: string;
  kind: DocumentKind;
  title: string;
  requirement: DocumentRequirement;
  status: "active" | "archived";
  current_version_id: string | null;
  current_version_number: number;
  required_version_number: number;
  archived_at: string | null;
  inserted_at: string;
  updated_at: string;
  versions?: DocumentVersion[];
};

export type StarterDocument = {
  kind: DocumentKind;
  language: string;
  title: string;
  body: string;
  requirement: DocumentRequirement;
  draft: boolean;
  legal_review_required: boolean;
};

export type OutstandingClient = {
  user_id: string;
  display_name: string | null;
  handle: string | null;
  status: "unsigned" | "resign_required";
};

export type OutstandingRow = {
  template_id: string;
  signed: number;
  outstanding: number;
  clients: OutstandingClient[];
};

export type Outstanding = { clients: number; templates: OutstandingRow[] };

export type SignatureRequest = {
  id: string;
  template_id: string;
  user_id: string;
  batch_id: string | null;
  audience: RequestAudience;
  status: "pending" | "signed" | "cancelled";
  requested_by_id: string | null;
  requested_at: string;
  signature_id: string | null;
  closed_at: string | null;
};

export type RequestResult = {
  batch_id: string;
  audience: string;
  recipients: number;
  created: number;
  skipped: number;
  requests: SignatureRequest[];
};

export type Signature = {
  id: string;
  template_id: string;
  version_id: string;
  version_number: number;
  request_id: string | null;
  user_id: string;
  signed_at: string;
  level: "simple" | "advanced" | "qualified";
  provider: string;
  content_hash: string;
  typed_name: string | null;
  ip_address: string | null;
  user_agent: string | null;
  evidence_hash: string;
  evidence_sha256: string;
  evidence_byte_size: number;
  has_drawn_signature: boolean;
  account: { display_name?: string | null; nickname?: string | null; handle?: string | null; email?: string | null; [key: string]: unknown };
};

export type EvidenceLink = { url: string; sha256: string; byte_size: number };

export type DocumentItem = {
  template_id: string;
  kind: DocumentKind;
  title: string;
  requirement: DocumentRequirement;
  current_version_id: string | null;
  current_version_number: number;
  status: SignatureStatus;
  outstanding: boolean;
  requested: boolean;
  signature: { id: string; version_number: number; signed_at: string; content_hash: string } | null;
};

export type HealthCertificate = {
  id: string;
  user_id: string;
  issued_on: string;
  /** The first day it is no longer valid. */
  expires_on: string;
  content_type: HealthContentType;
  byte_size: number;
  uploaded_by_id: string | null;
  inserted_at: string;
};

export type MyDocumentsOverview = {
  documents: DocumentItem[];
  outstanding: number;
  health_certificate: { required: boolean; status: HealthStatus; certificate: HealthCertificate | null };
};

export type MemberDocuments = {
  user_id: string;
  documents: DocumentItem[];
  outstanding: number;
  signatures: Signature[];
  health_certificate_status: HealthStatus;
};

export type HealthRow = {
  user_id: string;
  display_name: string | null;
  handle: string | null;
  status: HealthStatus;
  /** Only for staff who manage health certificates. */
  certificate: HealthCertificate | null;
};

export type HealthList = { health_certificates: HealthRow[]; required: boolean; full_access: boolean };

export type DocumentSettings = {
  block_booking_on_unsigned: boolean;
  health_certificate_required: boolean;
  block_booking_on_health_certificate: boolean;
  health_certificate_validity_months: number;
  health_certificate_reminder_days: number;
};

export type PresignedUpload = {
  upload_url: string;
  method: "PUT";
  required_headers: Record<string, string>;
  file_key: string;
  content_type: HealthContentType;
  max_bytes: number;
};

export type DrawnSignature = { width: number; height: number; strokes: number[][][] };

export type SignInput = {
  version_id: string;
  agreed: boolean;
  typed_name?: string;
  drawn_signature?: DrawnSignature;
};

/** One document the booking gate asks for (409 `documents_required`). */
export type BlockingDocument = { template_id: string; title: string; kind: DocumentKind; reason: string };
export type DocumentsRequired = { documents: BlockingDocument[]; health_certificate: HealthStatus | null };

/** The booking answered 409 `documents_required`: what the client still has to sign or upload. */
export function documentsRequired(error: unknown): DocumentsRequired | null {
  if (!(error instanceof ApiError) || error.status !== 409 || error.payload.code !== "documents_required") return null;
  const params = (error.payload.params ?? {}) as Partial<DocumentsRequired>;
  return {
    documents: Array.isArray(params.documents) ? params.documents : [],
    health_certificate: params.health_certificate ?? null,
  };
}

const ADMIN = "/admin/documents";
const ME = "/me/documents";

// ── Staff ──────────────────────────────────────────────────────────────────

export async function fetchDocumentTemplates(token: string) {
  return (await apiRequest<{ templates: DocumentTemplate[] }>(`${ADMIN}/templates?status=active`, { token })).templates;
}

export async function fetchDocumentTemplate(token: string, id: string) {
  return apiRequest<{ template: DocumentTemplate; current_version: DocumentVersion | null }>(
    `${ADMIN}/templates/${encodeURIComponent(id)}`,
    { token },
  );
}

export async function fetchDocumentVersion(token: string, templateId: string, versionId: string) {
  return (
    await apiRequest<{ version: DocumentVersion }>(
      `${ADMIN}/templates/${encodeURIComponent(templateId)}/versions/${encodeURIComponent(versionId)}`,
      { token },
    )
  ).version;
}

export async function fetchStarterDocuments(token: string, language: "el" | "en") {
  return (await apiRequest<{ starters: StarterDocument[] }>(`${ADMIN}/starters?language=${language}`, { token })).starters;
}

/** Who has not signed each document, and `clients`: how many a new mandatory document would block. */
export async function fetchOutstanding(token: string) {
  return apiRequest<Outstanding>(`${ADMIN}/outstanding`, { token });
}

export type NewDocumentInput = {
  kind: DocumentKind;
  title: string;
  requirement: DocumentRequirement;
  body: string;
  language: string;
};

export async function createDocumentTemplate(token: string, input: NewDocumentInput) {
  return apiRequest<{ template: DocumentTemplate; version: DocumentVersion }>(`${ADMIN}/templates`, {
    method: "POST",
    token,
    body: input,
  });
}

export async function publishDocumentVersion(
  token: string,
  templateId: string,
  input: { title?: string; body: string; change_kind: ChangeKind },
) {
  return apiRequest<{ template: DocumentTemplate; version: DocumentVersion }>(
    `${ADMIN}/templates/${encodeURIComponent(templateId)}/versions`,
    { method: "POST", token, body: input },
  );
}

export async function setDocumentRequirement(token: string, templateId: string, requirement: DocumentRequirement) {
  return (
    await apiRequest<{ template: DocumentTemplate }>(`${ADMIN}/templates/${encodeURIComponent(templateId)}/requirement`, {
      method: "PUT",
      token,
      body: { requirement },
    })
  ).template;
}

export async function archiveDocumentTemplate(token: string, templateId: string) {
  return (
    await apiRequest<{ template: DocumentTemplate }>(`${ADMIN}/templates/${encodeURIComponent(templateId)}/archive`, {
      method: "POST",
      token,
    })
  ).template;
}

export type RequestInput =
  | { audience: "person"; user_id: string }
  | { audience: "all_clients" }
  | { audience: "role"; role: "member" | "athlete" }
  | { audience: "package"; package_id: string };

export async function requestSignatures(token: string, templateId: string, input: RequestInput) {
  return apiRequest<RequestResult>(`${ADMIN}/templates/${encodeURIComponent(templateId)}/requests`, {
    method: "POST",
    token,
    body: input,
  });
}

export async function fetchPendingRequests(token: string, templateId: string) {
  const search = new URLSearchParams({ template_id: templateId, status: "pending", limit: "200" });
  return (await apiRequest<{ requests: SignatureRequest[]; total: number }>(`${ADMIN}/requests?${search}`, { token })).requests;
}

export async function fetchSignatures(token: string, filters: { template_id?: string; user_id?: string }) {
  const search = new URLSearchParams({ limit: "200" });
  if (filters.template_id) search.set("template_id", filters.template_id);
  if (filters.user_id) search.set("user_id", filters.user_id);
  return (await apiRequest<{ signatures: Signature[]; total: number }>(`${ADMIN}/signatures?${search}`, { token })).signatures;
}

export async function fetchSignatureEvidence(token: string, signatureId: string) {
  return apiRequest<EvidenceLink>(`${ADMIN}/signatures/${encodeURIComponent(signatureId)}/evidence`, { token });
}

export async function fetchMemberDocuments(token: string, userId: string) {
  return apiRequest<MemberDocuments>(`${ADMIN}/members/${encodeURIComponent(userId)}`, { token });
}

export async function fetchDocumentSettings(token: string) {
  return (await apiRequest<{ settings: DocumentSettings }>(`${ADMIN}/settings`, { token })).settings;
}

export async function saveDocumentSettings(token: string, changes: Partial<DocumentSettings>) {
  return (await apiRequest<{ settings: DocumentSettings }>(`${ADMIN}/settings`, { method: "PUT", token, body: changes })).settings;
}

export async function fetchHealthCertificates(token: string) {
  return apiRequest<HealthList>(`${ADMIN}/health-certificates`, { token });
}

export async function fetchClientHealthCertificates(token: string, userId: string) {
  return (
    await apiRequest<{ user_id: string; health_certificates: HealthCertificate[] }>(
      `${ADMIN}/health-certificates/members/${encodeURIComponent(userId)}`,
      { token },
    )
  ).health_certificates;
}

export async function fetchClientHealthFile(token: string, certificateId: string) {
  return apiRequest<{ url: string; content_type: string }>(
    `${ADMIN}/health-certificates/${encodeURIComponent(certificateId)}/file`,
    { token },
  );
}

export async function requestClientHealthUpload(token: string, userId: string, contentType: HealthContentType) {
  return apiRequest<PresignedUpload>(`${ADMIN}/health-certificates/uploads`, {
    method: "POST",
    token,
    body: { user_id: userId, content_type: contentType },
  });
}

export async function recordClientHealthCertificate(
  token: string,
  input: { user_id: string; file_key: string; content_type: HealthContentType; issued_on: string },
) {
  return (
    await apiRequest<{ health_certificate: HealthCertificate }>(`${ADMIN}/health-certificates`, {
      method: "POST",
      token,
      body: input,
    })
  ).health_certificate;
}

// ── Client (Box › Έγγραφα) ─────────────────────────────────────────────────

export async function fetchMyDocuments(token: string): Promise<MyDocumentsOverview> {
  // Box renders this on every visit: a partial answer must not break the page.
  const overview = await apiRequest<Partial<MyDocumentsOverview> | null>(ME, { token });
  return {
    documents: Array.isArray(overview?.documents) ? overview.documents : [],
    outstanding: typeof overview?.outstanding === "number" ? overview.outstanding : 0,
    health_certificate: overview?.health_certificate ?? { required: false, status: "missing", certificate: null },
  };
}

export async function fetchMyDocument(token: string, templateId: string) {
  return apiRequest<{ template: DocumentTemplate; version: DocumentVersion; status: SignatureStatus | null }>(
    `${ME}/${encodeURIComponent(templateId)}`,
    { token },
  );
}

export async function signMyDocument(token: string, templateId: string, input: SignInput) {
  return (
    await apiRequest<{ signature: Signature }>(`${ME}/${encodeURIComponent(templateId)}/sign`, {
      method: "POST",
      token,
      body: input,
    })
  ).signature;
}

export async function fetchMySignatures(token: string) {
  return (await apiRequest<{ signatures: Signature[]; total: number }>(`${ME}/signatures`, { token })).signatures;
}

export async function fetchMySignatureEvidence(token: string, signatureId: string) {
  return apiRequest<EvidenceLink>(`${ME}/signatures/${encodeURIComponent(signatureId)}/evidence`, { token });
}

export async function requestMyHealthUpload(token: string, contentType: HealthContentType) {
  return apiRequest<PresignedUpload>(`${ME}/health-certificate/uploads`, {
    method: "POST",
    token,
    body: { content_type: contentType },
  });
}

export async function recordMyHealthCertificate(
  token: string,
  input: { file_key: string; content_type: HealthContentType; issued_on: string },
) {
  return (
    await apiRequest<{ health_certificate: HealthCertificate }>(`${ME}/health-certificate`, {
      method: "POST",
      token,
      body: input,
    })
  ).health_certificate;
}

export async function fetchMyHealthFile(token: string, certificateId: string) {
  return apiRequest<{ url: string; content_type: string }>(`${ME}/health-certificate/${encodeURIComponent(certificateId)}/file`, {
    token,
  });
}
