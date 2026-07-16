import { apiRequest } from "@/api/client";

export type ProfileUpdate = {
  nickname?: string;
  current_password?: string;
  password?: string;
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

export async function getAvatarUploadUrl(token: string, file: File) {
  return apiRequest<{
    upload_url: string;
    key: string;
    required_headers: Record<string, string>;
    expires_in: number;
    max_bytes: number;
  }>(
    "/me/avatar/upload-url",
    {
      method: "POST",
      token,
      body: { content_type: file.type, byte_size: file.size },
    },
  );
}

export async function updateAvatar(token: string, avatarKey: string | null) {
  return apiRequest<{ user: { id: string; avatar_url: string | null } }>("/me/avatar", {
    method: "PATCH",
    token,
    body: { avatar_key: avatarKey },
  });
}

export async function searchAllUsers(token: string, query: string) {
  return apiRequest<{ users: Array<{ id: string; nickname: string; role: string }> }>(
    `/me/search/users?q=${encodeURIComponent(query)}`,
    { token },
  );
}
