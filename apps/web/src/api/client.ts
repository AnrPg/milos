const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "/api";

export type ApiErrorPayload = {
  error?: string;
  errors?: Record<string, string[]>;
};

export class ApiError extends Error {
  status: number;
  payload: ApiErrorPayload;

  constructor(status: number, message: string, payload: ApiErrorPayload) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.payload = payload;
  }
}

type ApiRequestOptions = {
  method?: "GET" | "POST" | "PATCH" | "PUT";
  token?: string | null;
  body?: unknown;
};

export async function apiRequest<T>(path: string, options: ApiRequestOptions = {}): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: options.method ?? "GET",
    headers: {
      "Content-Type": "application/json",
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  const payload = (await response.json().catch(() => ({}))) as T | ApiErrorPayload;

  if (!response.ok) {
    const message =
      typeof payload === "object" && payload !== null && "error" in payload && typeof payload.error === "string"
        ? payload.error
        : typeof payload === "object" &&
            payload !== null &&
            "errors" in payload &&
            payload.errors &&
            Object.keys(payload.errors).length > 0
          ? formatFieldErrors(payload.errors)
        : `Request failed with status ${response.status}`;

    throw new ApiError(response.status, message, (payload as ApiErrorPayload) ?? {});
  }

  return payload as T;
}

function formatFieldErrors(errors: Record<string, string[]>) {
  return Object.entries(errors)
    .map(([field, messages]) => `${field}: ${messages.join(", ")}`)
    .join(" | ");
}
