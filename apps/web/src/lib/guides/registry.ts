import type { Guide, GuideId } from "./types";

/**
 * Every walkthrough (ADR-193). Steps point at anchors on the real screens
 * (lib/guides/anchors); copy is under `Guides.<id>` in messages. Bump a
 * guide's `version` when its steps change enough to offer it again to
 * people who finished it.
 */
export const GUIDES: readonly Guide[] = [
  {
    id: "shop_staff",
    version: 1,
    audience: "staff",
    home: { path: "/admin/shop", admin: true },
    minutes: 2,
    requires: (can) => can.staff,
    steps: [
      { id: "welcome", chapter: "setup" },
      { id: "newProduct", chapter: "setup", labels: { label: "ShopConsole.newProduct" }, anchor: "shop.newProduct", action: { target: "shop.newProduct", until: "shop.editor.photos" } },
      { id: "photos", chapter: "setup", anchor: "shop.editor.photos" },
      { id: "price", chapter: "setup", anchor: "shop.editor.price", tip: true },
      { id: "selling", chapter: "setup", anchor: "shop.editor.selling" },
      { id: "save", chapter: "setup", anchor: "shop.editor.save", tip: true },
      {
        id: "ordersTab",
        chapter: "sell",
        labels: { label: "ShopConsole.tabs.orders" },
        route: { path: "/admin/shop", admin: true },
        anchor: "shop.tab.orders",
        action: { target: "shop.tab.orders", until: "shop.orders" },
      },
      { id: "orders", chapter: "sell", anchor: "shop.orders", tip: true },
      { id: "pos", chapter: "sell", anchor: "shop.pos" },
      { id: "stock", chapter: "track", route: { path: "/admin/shop", admin: true, query: { tab: "stock" } }, anchor: "shop.stock" },
      { id: "analytics", chapter: "track", route: { path: "/admin/shop", admin: true, query: { tab: "analytics" } }, anchor: "shop.analytics", tip: true },
      { id: "done" },
    ],
  },
  {
    id: "events_organising",
    version: 1,
    audience: "staff",
    home: { path: "/events/hosting" },
    minutes: 2,
    requires: (can) => can.staff || can.hosts,
    steps: [
      { id: "welcome", chapter: "plan" },
      { id: "new", chapter: "plan", labels: { label: "Events.newEvent" }, anchor: "events.new", action: { target: "events.new", until: "events.wizard.steps" } },
      { id: "steps", chapter: "plan", anchor: "events.wizard.steps" },
      { id: "screen", chapter: "plan", anchor: "events.wizard.body", tip: true },
      { id: "next", chapter: "plan", anchor: "events.wizard.next" },
      { id: "cohosts", chapter: "plan", labels: { label: "EventWizard.step_capacityCohosts" }, tip: true, leave: "events.wizard.close" },
      { id: "manage", chapter: "run", route: { path: "/events/hosting" }, anchor: "events.list" },
      { id: "finances", chapter: "run", labels: { label: "EventsHosting.tab_finances" }, anchor: "events.tab.finances", action: { target: "events.tab.finances", until: "events.finances" } },
      { id: "analytics", chapter: "run", labels: { label: "EventsHosting.tab_analytics" }, anchor: "events.tab.analytics", action: { target: "events.tab.analytics", until: "events.analytics" }, tip: true },
      { id: "done" },
    ],
  },
  {
    id: "finance_offers",
    version: 1,
    audience: "staff",
    home: { path: "/admin/finance", admin: true, query: { tab: "promotions" } },
    minutes: 3,
    requires: (can) => can.manager,
    demoSection: "finance",
    steps: [
      { id: "welcome", chapter: "campaigns" },
      {
        id: "campaignNew",
        chapter: "campaigns",
        labels: { label: "Ui.newCampaignb18ba62" },
        route: { path: "/admin/finance", admin: true, query: { tab: "promotions" } },
        anchor: "finance.campaigns.new",
        action: { target: "finance.campaigns.new", until: "finance.campaign.form" },
      },
      { id: "campaignForm", chapter: "campaigns", anchor: "finance.campaign.form", leave: "finance.campaign.close" },
      { id: "coupons", chapter: "campaigns", anchor: "finance.campaigns.list", tip: true },
      {
        id: "partners",
        chapter: "partners",
        labels: { label: "PerksAdmin.segmentPartners" },
        anchor: "finance.offers.partners",
        action: { target: "finance.offers.partners", until: "finance.perks.list" },
      },
      { id: "perkNew", chapter: "partners", labels: { label: "PerksAdmin.new" }, anchor: "finance.perks.new", action: { target: "finance.perks.new", until: "finance.perk.form" } },
      { id: "perkPartner", chapter: "partners", anchor: "finance.perk.partner" },
      { id: "perkBenefit", chapter: "partners", anchor: "finance.perk.benefit" },
      { id: "perkMethod", chapter: "partners", anchor: "finance.perk.method", tip: true },
      { id: "perkRules", chapter: "partners", anchor: "finance.perk.rules", leave: "finance.perk.close" },
      {
        id: "referrals",
        chapter: "referrals",
        route: { path: "/admin/finance", admin: true, query: { tab: "referrals" } },
        anchor: "finance.referrals.new",
      },
      { id: "referralsFlow", chapter: "referrals", anchor: "finance.referrals", tip: true },
      { id: "done" },
    ],
  },
  {
    id: "member_club_event",
    version: 1,
    audience: "member",
    home: { path: "/events" },
    minutes: 2,
    requires: () => true,
    steps: [
      { id: "welcome", chapter: "club" },
      {
        id: "channels",
        chapter: "club",
        labels: { label: "Clubs.tabChannels" },
        requires: "inGymClub",
        route: { path: "/clubs/:gymClub" },
        anchor: "club.tab.channels",
        action: { target: "club.tab.channels", until: "club.groups" },
      },
      { id: "groups", chapter: "club", requires: "inGymClub", anchor: "club.groups" },
      { id: "propose", chapter: "club", labels: { label: "Clubs.proposeTitle" }, requires: "inGymClub", anchor: "club.proposeGroup", action: { target: "club.proposeGroup", until: "club.groupSheet" } },
      { id: "groupSheet", chapter: "club", requires: "inGymClub", anchor: "club.groupSheet", tip: true, leave: "club.groupSheet.close" },
      { id: "noBox", chapter: "club", unless: "inGymClub" },
      {
        id: "eventNew",
        chapter: "event",
        labels: { label: "Events.newEvent" },
        route: { path: "/events" },
        anchor: "events.page.new",
        action: { target: "events.page.new", until: "events.wizard.steps" },
      },
      { id: "hostAs", chapter: "event", labels: { label: "Events.hostSelf" }, anchor: "events.hostAs", tip: true },
      { id: "alone", chapter: "event", anchor: "events.wizard.body" },
      { id: "withBox", chapter: "event", labels: { label: "EventWizard.step_capacityCohosts" }, tip: true, leave: "events.wizard.close" },
      { id: "hosting", chapter: "event", labels: { label: "Events.hostingConsole" }, route: { path: "/events" }, anchor: "events.hostingLink" },
      { id: "done" },
    ],
  },
];

const IDS = new Set<string>(GUIDES.map((guide) => guide.id));

export function isGuideId(id: string): id is GuideId {
  return IDS.has(id);
}

export function guideById(id: GuideId): Guide {
  return GUIDES.find((guide) => guide.id === id)!;
}
