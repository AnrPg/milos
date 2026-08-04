export type AccountSurfaceUser = {
  platform_owner?: boolean | null;
};

export function showsTenantSelfServiceSurfaces(user: AccountSurfaceUser | null | undefined) {
  return !user?.platform_owner;
}
