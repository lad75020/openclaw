import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("./tools/gateway.js", () => ({
  callGatewayTool: vi.fn(async () => ({ ok: true })),
}));

let callGatewayTool: typeof import("./tools/gateway.js").callGatewayTool;
let buildExecApprovalFollowupPrompt: typeof import("./bash-tools.exec-approval-followup.js").buildExecApprovalFollowupPrompt;
let sendExecApprovalFollowup: typeof import("./bash-tools.exec-approval-followup.js").sendExecApprovalFollowup;

beforeEach(async () => {
  vi.resetModules();
  ({ callGatewayTool } = await import("./tools/gateway.js"));
  ({ buildExecApprovalFollowupPrompt, sendExecApprovalFollowup } =
    await import("./bash-tools.exec-approval-followup.js"));
});

afterEach(() => {
  vi.resetAllMocks();
});

describe("exec approval followup", () => {
  it("uses an explicit denial prompt when the command did not run", () => {
    const prompt = buildExecApprovalFollowupPrompt(
      "Exec denied (gateway id=req-1, user-denied): uname -a",
    );

    expect(prompt).toContain("did not run");
    expect(prompt).toContain("Do not mention, summarize, or reuse output");
    expect(prompt).not.toContain("already approved has completed");
  });

  it("tells the agent to continue the task before replying when the command succeeds", () => {
    const prompt = buildExecApprovalFollowupPrompt("Exec finished (gateway id=req-1, code 0)\nok");

    expect(prompt).toContain("continue from this result before replying to the user");
    expect(prompt).toContain("Continue the task if needed, then reply to the user");
  });

  it("keeps followups internal when no external route is available", async () => {
    await sendExecApprovalFollowup({
      approvalId: "req-1",
      sessionKey: "agent:main:main",
      resultText: "Exec completed: echo ok",
    });

    expect(callGatewayTool).toHaveBeenCalledWith(
      "agent",
      expect.any(Object),
      expect.objectContaining({
        sessionKey: "agent:main:main",
        deliver: false,
        channel: undefined,
        to: undefined,
      }),
      { expectFinal: true },
    );
  });

<<<<<<< HEAD
  it("uses external delivery when a deliverable route is available", async () => {
=======
  it.each([
    {
      channel: "slack",
      sessionKey: "agent:main:slack:channel:C123",
      to: "channel:C123",
      accountId: "default",
      threadId: "1712419200.1234",
    },
    {
      channel: "discord",
      sessionKey: "agent:main:discord:channel:123",
      to: "123",
      accountId: "default",
      threadId: "456",
    },
    {
      channel: "telegram",
      sessionKey: "agent:main:telegram:-100123",
      to: "-100123",
      accountId: "default",
      threadId: "789",
    },
  ])("uses agent continuation for $channel followups when a session exists", async (target) => {
>>>>>>> main
    await sendExecApprovalFollowup({
      approvalId: "req-2",
      sessionKey: "agent:main:discord:channel:123",
      turnSourceChannel: "discord",
      turnSourceTo: "123",
      turnSourceAccountId: "default",
      turnSourceThreadId: "456",
      resultText: "Exec completed: echo ok",
    });

    expect(callGatewayTool).toHaveBeenCalledWith(
      "agent",
      expect.any(Object),
      expect.objectContaining({
<<<<<<< HEAD
        sessionKey: "agent:main:discord:channel:123",
        deliver: true,
        bestEffortDeliver: true,
=======
        sessionKey: target.sessionKey,
        deliver: true,
        bestEffortDeliver: true,
        channel: target.channel,
        to: target.to,
        accountId: target.accountId,
        threadId: target.threadId,
        idempotencyKey: `exec-approval-followup:req-${target.channel}`,
      }),
      { expectFinal: true },
    );
    expect(sendMessage).not.toHaveBeenCalled();
  });

  it("falls back to direct external delivery only when no session exists", async () => {
    await sendExecApprovalFollowup({
      approvalId: "req-no-session",
      turnSourceChannel: "discord",
      turnSourceTo: "123",
      turnSourceAccountId: "default",
      turnSourceThreadId: "456",
      resultText: "discord exec approval smoke",
    });

    expect(sendMessage).toHaveBeenCalledWith(
      expect.objectContaining({
>>>>>>> main
        channel: "discord",
        to: "123",
        accountId: "default",
        threadId: "456",
<<<<<<< HEAD
=======
        content: "discord exec approval smoke",
        idempotencyKey: "exec-approval-followup:req-no-session",
>>>>>>> main
      }),
      { expectFinal: true },
    );
  });
});
