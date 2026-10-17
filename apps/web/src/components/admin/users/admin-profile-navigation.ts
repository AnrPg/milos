import { SECTION_TAB } from "@/components/admin/users/member-profile-tabs";

export const ADMIN_PROFILE_SECTION_REQUEST = "milos:admin-profile-section-request";

export type AdminProfileSectionRequest = CustomEvent<{ section: string }>;

/** Opens a section of the member profile: its tab (`?tab=`), then the section. */
export function openAdminProfileSection(section: string) {
  window.dispatchEvent(
    new CustomEvent(ADMIN_PROFILE_SECTION_REQUEST, { detail: { section } }),
  );
  const params = new URLSearchParams(window.location.search);
  const tab = SECTION_TAB[section];
  if (tab) params.set("tab", tab);
  const query = params.toString();
  window.history.replaceState(null, "", `${window.location.pathname}${query ? `?${query}` : ""}#${section}`);
  window.requestAnimationFrame(() => {
    document.getElementById(section)?.scrollIntoView({ behavior: "smooth", block: "start" });
  });
}
