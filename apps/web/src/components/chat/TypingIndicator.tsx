interface TypingUser {
  user_id: string;
  nickname: string;
}

interface TypingIndicatorProps {
  typingUsers: TypingUser[];
}

export function TypingIndicator({ typingUsers }: TypingIndicatorProps) {
  if (typingUsers.length === 0) return null;

  const label =
    typingUsers.length === 1
      ? `${typingUsers[0]!.nickname} is typing…`
      : `${typingUsers.map((u) => u.nickname).join(", ")} are typing…`;

  return (
    <div className="flex items-center gap-2 px-1 py-0.5">
      <div className="flex gap-0.5">
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="block w-1.5 h-1.5 rounded-full"
            style={{
              background: "#7755aa",
              animation: `bounce 1.2s ease-in-out ${i * 0.2}s infinite`,
            }}
          />
        ))}
      </div>
      <span className="text-[11px]" style={{ color: "#8888aa" }}>
        {label}
      </span>
    </div>
  );
}
