/**
 * The notification inbox deliberately spans organizations (F-28): a member
 * should never miss a notification because they had a different gym selected.
 * The trade-off is that an item's origin is no longer implied by context, so
 * anything raised outside the active organization has to say so.
 */

export type OrganizationRef = {
  id: string;
  name: string;
  brandColor?: string | null;
};

export type NotificationOrigin = {
  name: string;
  color: string | null;
};

/**
 * Returns the badge to render for a notification, or null when it belongs to
 * the organization the user is already looking at (the common case, which
 * should stay visually quiet).
 *
 * Colour comes from the originating organization's own brand colour where it
 * has one, so repeat notifications from the same gym stay recognisable.
 */
export function notificationOrigin(
  notificationOrganizationId: string | null | undefined,
  activeOrganizationId: string | null | undefined,
  organizations: OrganizationRef[],
  unknownLabel: string,
): NotificationOrigin | null {
  if (!notificationOrganizationId) return null;
  // Until the active organization resolves there is nothing to compare
  // against; badging everything would be worse than badging nothing.
  if (!activeOrganizationId) return null;
  if (notificationOrganizationId === activeOrganizationId) return null;

  const organization = organizations.find((entry) => entry.id === notificationOrganizationId);

  // An organization the user can no longer see (membership revoked, say) still
  // warrants the badge — "somewhere else" is the safe read, not "here".
  if (!organization) return { name: unknownLabel, color: null };

  return { name: organization.name, color: organization.brandColor?.trim() || null };
}
