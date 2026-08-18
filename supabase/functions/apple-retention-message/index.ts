import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";
import { decodeJwt } from "npm:jose@6.1.0";
import { APPLE_ROOT_CERTIFICATES } from "./apple-root-certificates.ts";

const APPLE_APP_ID = 6763945657;
const BUNDLE_ID = "com.jackwallner.baseball";
const YEARLY_PRODUCT_ID = "com.jackwallner.baseball.pro.yearly";
const MONTHLY_PRODUCT_ID = "com.jackwallner.baseball.pro.monthly";

const sandboxVerifier = new SignedDataVerifier(
  APPLE_ROOT_CERTIFICATES,
  false,
  Environment.SANDBOX,
  BUNDLE_ID,
  APPLE_APP_ID,
);
const productionVerifier = new SignedDataVerifier(
  APPLE_ROOT_CERTIFICATES,
  false,
  Environment.PRODUCTION,
  BUNDLE_ID,
  APPLE_APP_ID,
);

export interface DecodedRealtimeRequest {
  appAppleId?: number;
  bundleId?: string;
  environment?: string;
  userLocale?: string;
  originalTransactionId?: string;
  productId?: string;
  requestIdentifier?: string;
  signedDate?: number;
}

export interface MessageConfiguration {
  default?: string | null;
  monthly?: string | null;
  yearly?: string | null;
}

function nonEmpty(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

export function messageConfiguration(): MessageConfiguration {
  return {
    default: nonEmpty(Deno.env.get("APPLE_RETENTION_MESSAGE_ID_DEFAULT")),
    monthly: nonEmpty(Deno.env.get("APPLE_RETENTION_MESSAGE_ID_MONTHLY")),
    yearly: nonEmpty(Deno.env.get("APPLE_RETENTION_MESSAGE_ID_YEARLY")),
  };
}

export function selectMessageIdentifier(
  productId: string | undefined,
  configuration: MessageConfiguration,
): string | null {
  if (productId === YEARLY_PRODUCT_ID) {
    return configuration.yearly ?? configuration.default ?? null;
  }

  if (productId === MONTHLY_PRODUCT_ID) {
    return configuration.monthly ?? configuration.default ?? null;
  }

  return (
    configuration.default ??
      configuration.yearly ??
      configuration.monthly ??
      null
  );
}

export async function verifySignedPayload(
  signedPayload: string,
): Promise<DecodedRealtimeRequest> {
  const unverified = decodeJwt(signedPayload) as { environment?: string };
  const verifier = unverified.environment === Environment.PRODUCTION
    ? productionVerifier
    : sandboxVerifier;
  const decoded = await verifier.verifyAndDecodeRealtimeRequest(signedPayload);
  if (decoded.appAppleId !== APPLE_APP_ID) {
    throw new Error(`Unexpected app Apple ID: ${decoded.appAppleId}`);
  }

  return {
    appAppleId: decoded.appAppleId,
    environment: decoded.environment,
    originalTransactionId: decoded.originalTransactionId,
    productId: decoded.productId,
    requestIdentifier: decoded.requestIdentifier,
    signedDate: decoded.signedDate,
    userLocale: decoded.userLocale,
  };
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

export async function handleRetentionRequest(
  request: Request,
  configuration = messageConfiguration(),
): Promise<Response> {
  if (request.method === "GET") {
    return jsonResponse({ service: "apple-retention-message", status: "ok" });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  try {
    const body = await request.json();
    const signedPayload = body?.signedPayload;
    if (typeof signedPayload !== "string" || !signedPayload) {
      return jsonResponse({ error: "signedPayload_required" }, 400);
    }

    const decodedRequest = await verifySignedPayload(signedPayload);

    const messageIdentifier = selectMessageIdentifier(
      decodedRequest.productId,
      configuration,
    );
    if (!messageIdentifier) {
      throw new Error("No approved retention message is configured");
    }

    return jsonResponse({ message: { messageIdentifier } });
  } catch (error) {
    console.error("Apple retention message request failed", {
      error: error instanceof Error ? error.message : String(error),
    });
    return jsonResponse({ error: "retention_message_unavailable" }, 500);
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleRetentionRequest(request));
}
