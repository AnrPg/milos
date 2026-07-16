import type { paths } from "@/api/generated/schema";
import { apiRequest } from "@/api/client";

export type RegisterRequest =
  NonNullable<
    paths["/api/auth/register"]["post"]["requestBody"]
  >["content"]["application/json"];
export type LoginRequest =
  NonNullable<
    paths["/api/auth/login"]["post"]["requestBody"]
  >["content"]["application/json"];
export type AuthTokens =
  paths["/api/auth/login"]["post"]["responses"]["200"]["content"]["application/json"];
export type CurrentUser =
  paths["/api/auth/me"]["get"]["responses"]["200"]["content"]["application/json"];

export function registerUser(payload: RegisterRequest) {
  return apiRequest<AuthTokens>("/auth/register", { method: "POST", body: payload });
}

export function loginUser(payload: LoginRequest) {
  return apiRequest<AuthTokens>("/auth/login", { method: "POST", body: payload });
}

export function refreshSession() {
  return apiRequest<AuthTokens>("/auth/refresh", { method: "POST" }, false);
}

export function logoutSession() {
  return apiRequest<void>("/auth/logout", { method: "POST" }, false);
}

export function signOutAllDevices(token: string) {
  return apiRequest<void>("/auth/sign-out-all", { method: "POST", token }, false);
}

export function fetchCurrentUser(token: string) {
  return apiRequest<CurrentUser>("/auth/me", { token });
}

export function checkNicknameAvailable(nickname: string) {
  return apiRequest<{ available: boolean }>(
    `/auth/nickname-available?nickname=${encodeURIComponent(nickname)}`,
  );
}
