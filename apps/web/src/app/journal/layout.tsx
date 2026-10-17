import { JournalHeader } from "@/components/member-app/journal/JournalHeader";

// Every Journal segment shares the title and the one write action (brief §7.7).
export default function JournalLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <JournalHeader />
      {children}
    </>
  );
}
