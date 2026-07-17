import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { MessageComposer } from "@/components/chat/MessageComposer";

describe("MessageComposer", () => {
  it("keeps Enter in the draft and sends only from the send button", () => {
    const onChange = vi.fn();
    const onSend = vi.fn();

    render(
      <MessageComposer
        value={"first line\nsecond line"}
        onChange={onChange}
        onSend={onSend}
        placeholder="Write a message"
        sendLabel="Send"
      />,
    );

    const composer = screen.getByRole("textbox");
    expect(composer).toHaveValue("first line\nsecond line");

    fireEvent.keyDown(composer, { key: "Enter" });
    expect(onSend).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    expect(onSend).toHaveBeenCalledTimes(1);
  });
});
