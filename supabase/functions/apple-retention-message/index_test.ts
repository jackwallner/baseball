import { handleRetentionRequest, selectMessageIdentifier } from "./index.ts";

const configuration = {
  default: "default-message",
  monthly: "monthly-message",
  yearly: "yearly-message",
};

Deno.test("selects the yearly message for yearly subscriptions", () => {
  const actual = selectMessageIdentifier(
    "com.jackwallner.baseball.pro.yearly",
    configuration,
  );
  if (actual !== "yearly-message") {
    throw new Error(`Expected yearly message, got ${actual}`);
  }
});

Deno.test("selects the monthly message for monthly subscriptions", () => {
  const actual = selectMessageIdentifier(
    "com.jackwallner.baseball.pro.monthly",
    configuration,
  );
  if (actual !== "monthly-message") {
    throw new Error(`Expected monthly message, got ${actual}`);
  }
});

Deno.test("uses the default message for an unknown product", () => {
  const actual = selectMessageIdentifier("unknown", configuration);
  if (actual !== "default-message") {
    throw new Error(`Expected default message, got ${actual}`);
  }
});

Deno.test("exposes a health response without Apple credentials", async () => {
  const response = await handleRetentionRequest(
    new Request("https://example.com", { method: "GET" }),
    configuration,
  );
  if (response.status !== 200) {
    throw new Error(`Expected 200, got ${response.status}`);
  }
});

Deno.test("rejects an unsigned Apple payload", async () => {
  const response = await handleRetentionRequest(
    new Request("https://example.com", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ signedPayload: "not-a-jws" }),
    }),
    configuration,
  );
  if (response.status !== 500) {
    throw new Error(`Expected 500, got ${response.status}`);
  }
});
