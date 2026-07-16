import { apiRequest } from "@/api/client";

export type ProfileUpdate = {
  nickname?: string;
  current_password?: string;
  password?: string;
  avatar_url?: string | null;
  preferred_locale?: string;
};

export type ProfileUser = {
  id: string;
  nickname: string;
  role: string;
  avatar_url?: string | null;
  preferred_locale: string;
};

export async function updateProfile(token: string, payload: ProfileUpdate) {
  return apiRequest<{ user: ProfileUser }>("/me/profile", {
    method: "PATCH",
    token,
    body: payload,
  });
}

export async function getAvatarUploadUrl(token: string) {
  return apiRequest<{ upload_url: string; public_url: string; key: string }>(
    "/me/avatar/upload-url",
    { method: "POST", token },
  );
}

export async function updateAvatar(token: string, avatar_url: string | null) {
  return apiRequest<{ user: { id: string; avatar_url: string | null } }>("/me/avatar", {
    method: "PATCH",
    token,
    body: { avatar_url },
  });
}

export async function searchAllUsers(token: string, query: string) {
  return apiRequest<{ users: Array<{ id: string; nickname: string; role: string }> }>(
    `/me/search/users?q=${encodeURIComponent(query)}`,
    { token },
  );
}
