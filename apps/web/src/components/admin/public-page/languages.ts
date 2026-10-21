// Every ISO 639-1 code; names come from Intl.DisplayNames in the viewer's
// language, and each language is also shown by its own name (endonym).
export const ISO_639_1 = (
  "aa ab ae af ak am an ar as av ay az ba be bg bi bm bn bo br bs ca ce ch co cr cs cu cv cy da de dv dz ee el en eo es et eu " +
  "fa ff fi fj fo fr fy ga gd gl gn gu gv ha he hi ho hr ht hu hy hz ia id ie ig ii ik io is it iu ja jv ka kg ki kj kk kl km kn " +
  "ko kr ks ku kv kw ky la lb lg li ln lo lt lu lv mg mh mi mk ml mn mr ms mt my na nb nd ne ng nl nn no nr nv ny oc oj om or os " +
  "pa pi pl ps pt qu rm rn ro ru rw sa sc sd se sg si sk sl sm sn so sq sr ss st su sv sw ta te tg th ti tk tl tn to tr ts tt tw " +
  "ty ug uk ur uz ve vi vo wa wo xh yi yo za zh zu"
).split(" ");

/** Shown first (board 3b Q6): the languages most asked for in Greek gyms. */
export const COMMON_LANGUAGES = ["el", "en", "de", "fr", "it", "ru", "uk", "bg", "ro", "sq", "ar", "es"];

export function languageNames(locale: string) {
  let inViewer: Intl.DisplayNames | null = null;
  try {
    inViewer = new Intl.DisplayNames([locale], { type: "language" });
  } catch {
    inViewer = null;
  }
  return (code: string) => {
    let own = code;
    try {
      own = new Intl.DisplayNames([code], { type: "language" }).of(code) ?? code;
    } catch {
      own = code;
    }
    const viewer = inViewer?.of(code) ?? own;
    const english = new Intl.DisplayNames(["en"], { type: "language" }).of(code) ?? code;
    return { own: own.charAt(0).toLocaleUpperCase(code) + own.slice(1), viewer, english };
  };
}
