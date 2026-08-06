export type AccountSurfaceUser = {
  vendor?: boolean | null;
};

export function showsTenantSelfServiceSurfaces(user: AccountSurfaceUser | null | undefined) {
  return !user?.vendor;
}
