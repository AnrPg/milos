export function openEmailAttachmentFallback(subject: string, body: string) {
  const emailUrl = new URL("mailto:");
  emailUrl.searchParams.set("subject", subject);
  emailUrl.searchParams.set("body", body);
  window.location.href = emailUrl.toString();
}
