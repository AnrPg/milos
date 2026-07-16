import {getTranslations} from "next-intl/server";

export function getUiTranslations() {
  return getTranslations("Ui");
}
