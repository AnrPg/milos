export const ADMIN_PROFILE_SECTION_REQUEST = "milos:admin-profile-section-request";

export type AdminProfileSectionRequest = CustomEvent<{ section: string }>;

export function openAdminProfileSection(section: string) {
  window.dispatchEvent(
    new CustomEvent(ADMIN_PROFILE_SECTION_REQUEST, { detail: { section } }),
  );
  window.history.replaceState(null, "", `${window.location.pathname}${window.location.search}#${section}`);
  window.requestAnimationFrame(() => {
    document.getElementById(section)?.scrollIntoView({ behavior: "smooth", block: "start" });
  });
}
