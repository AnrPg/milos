/**
 * The places on real screens a walkthrough can point at (ADR-193). A screen
 * marks an element with `{...guideAnchor("shop.newProduct")}` and a guide
 * step names the anchor, never a CSS class or a translated label, so a
 * restyle or a new language cannot break a guide. Each anchor resolves to
 * selectors tried in order: the marked element first, then a fallback for
 * the layouts that render it differently (a tab strip that became a
 * dropdown on a phone).
 */
const ANCHORS = {
  // Κατάστημα (staff shop console).
  "shop.header": [],
  "shop.newProduct": [],
  "shop.pos": [],
  "shop.tabs": [],
  "shop.tab.orders": ['[data-guide="shop.tabs"] [data-segment="orders"]', '[data-guide="shop.tabs"]'],
  "shop.tab.stock": ['[data-guide="shop.tabs"] [data-segment="stock"]', '[data-guide="shop.tabs"]'],
  "shop.tab.analytics": ['[data-guide="shop.tabs"] [data-segment="analytics"]', '[data-guide="shop.tabs"]'],
  "shop.empty": [],
  "shop.products": [],
  "shop.orders": [],
  "shop.stock": [],
  "shop.analytics": [],
  "shop.editor.photos": [],
  "shop.editor.basics": [],
  "shop.editor.price": [],
  "shop.editor.variants": [],
  "shop.editor.selling": [],
  "shop.editor.save": [],
  // Events: the organiser console and the 7-step wizard.
  "events.new": [],
  "events.hostingLink": [],
  "events.hostAs": [],
  "events.tabs": [],
  "events.tab.finances": ['[data-guide="events.tabs"] [data-segment="finances"]', '[data-guide="events.tabs"]'],
  "events.tab.analytics": ['[data-guide="events.tabs"] [data-segment="analytics"]', '[data-guide="events.tabs"]'],
  "events.list": [],
  "events.finances": [],
  "events.analytics": [],
  "events.wizard": [],
  "events.wizard.steps": [],
  "events.wizard.body": [],
  "events.wizard.next": [],
  "events.wizard.close": ['[data-guide="events.wizard"] [data-dialog-close]'],
  // Οικονομικά › Προσφορές and Παραπομπές.
  "finance.tabs": [],
  "finance.tab.promotions": ['[data-guide="finance.tabs"] [data-segment="promotions"]', '[data-guide="finance.tabs"]'],
  "finance.tab.referrals": ['[data-guide="finance.tabs"] [data-segment="referrals"]', '[data-guide="finance.tabs"]'],
  "finance.offers": [],
  "finance.offers.partners": ['[data-guide="finance.offers"] [data-segment="partners"]', '[data-guide="finance.offers"]'],
  "finance.campaigns.new": [],
  "finance.campaigns.list": [],
  "finance.campaign.form": [],
  "finance.campaign.close": ['[data-guide="finance.campaign.form"] [data-dialog-close]'],
  "finance.perks.new": [],
  "finance.perks.list": [],
  "finance.perk.form": [],
  "finance.perk.partner": [],
  "finance.perk.benefit": [],
  "finance.perk.method": [],
  "finance.perk.rules": [],
  "finance.perk.close": ['[data-guide="finance.perk.form"] [data-dialog-close]'],
  "finance.referrals": [],
  "finance.referrals.new": [],
  // A member's own club (a group in the box's club) and own events.
  "club.tabs": [],
  "club.tab.channels": ['[data-guide="club.tabs"] [data-segment="channels"]', '[data-guide="club.tabs"]'],
  "club.groups": [],
  "club.proposeGroup": [],
  "club.groupSheet": [],
  "club.groupSheet.close": ['[data-guide="club.groupSheet"] [data-dialog-close]'],
  "events.page.new": [],
} as const satisfies Record<string, readonly string[]>;

export type GuideAnchor = keyof typeof ANCHORS;

export const GUIDE_ANCHORS = Object.keys(ANCHORS) as GuideAnchor[];

/** Spread on the element a guide may point at: `<button {...guideAnchor("shop.pos")}>`. */
export function guideAnchor(anchor: GuideAnchor) {
  return { "data-guide": anchor } as const;
}

/** The selectors of an anchor, the marked element first. */
export function anchorSelectors(anchor: GuideAnchor): string[] {
  const own = `[data-guide="${anchor}"]`;
  const extra: readonly string[] = ANCHORS[anchor];
  return extra.includes(own) ? [...extra] : [own, ...extra];
}

/** The first visible element of an anchor on the page, or null. */
export function findAnchor(anchor: GuideAnchor, root: ParentNode = document): HTMLElement | null {
  for (const selector of anchorSelectors(anchor)) {
    for (const element of Array.from(root.querySelectorAll<HTMLElement>(selector))) {
      if (isVisible(element)) return element;
    }
  }
  return null;
}

function isVisible(element: HTMLElement) {
  if (!element.isConnected) return false;
  const rect = element.getBoundingClientRect();
  if (rect.width === 0 && rect.height === 0) return false;
  const style = getComputedStyle(element);
  return style.visibility !== "hidden" && style.display !== "none";
}
