import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

describe("rental contract", () => {
    const accounts = simnet.getAccounts();
    const owner = accounts.get("wallet_1")!;
    const tenant = accounts.get("wallet_2")!;
    const tenant2 = accounts.get("wallet_3")!;

    // Test constants
    const totalTokens = 100;
    const pricePerToken = 10;
    const purchaseAmount = 5;

    beforeEach(() => {
        // Reset contract state before each test
        simnet.mineEmptyBlock();
    });

    describe("property registration", () => {
        it("successfully registers a new property", () => {
            const registerCall = simnet.callPublicFn(
                "rental",
                "register-property",
                [Cl.uint(totalTokens), Cl.uint(pricePerToken)],
                owner
            );
            expect(registerCall.result).toBeOk(Cl.bool(true));

            const propertyDetails = simnet.callReadOnlyFn(
                "rental",
                "get-property-details",
                [Cl.principal(owner)],
                owner
            );
            
            expect(propertyDetails.result).toStrictEqual(
              Cl.some(
                  Cl.tuple({
                      owner: Cl.principal(owner),
                      'total-tokens': Cl.uint(totalTokens),
                      'price-per-token': Cl.uint(pricePerToken),
                      'available-tokens': Cl.uint(totalTokens)
                  })
              )
          );
          
        });
    });

    describe("token purchase", () => {
        it("allows tenant to purchase tokens", () => {
            // First register property
            simnet.callPublicFn(
                "rental",
                "register-property",
                [Cl.uint(totalTokens), Cl.uint(pricePerToken)],
                owner
            );

            const purchaseCall = simnet.callPublicFn(
                "rental",
                "purchase-tokens",
                [Cl.principal(owner), Cl.uint(purchaseAmount)],
                tenant
            );
            expect(purchaseCall.result).toBeOk(Cl.bool(true));

            const tenantTokens = simnet.callReadOnlyFn(
                "rental",
                "get-tenant-tokens",
                [Cl.principal(owner), Cl.principal(tenant)],
                tenant
            );
            expect(tenantTokens.result).toStrictEqual(Cl.some(Cl.uint(purchaseAmount)));

          });
    });

    describe("maintenance funds", () => {
        it("allows adding maintenance funds", () => {
            const fundAmount = 1000;
            const addFundsCall = simnet.callPublicFn(
                "rental",
                "add-maintenance-fund",
                [Cl.principal(owner), Cl.uint(fundAmount)],
                tenant
            );
            expect(addFundsCall.result).toBeOk(Cl.bool(true));
        });
    });

    describe("token transfers", () => {
        it("allows transfer between tenants", () => {
            // Setup: Register property and purchase tokens
            simnet.callPublicFn(
                "rental",
                "register-property",
                [Cl.uint(totalTokens), Cl.uint(pricePerToken)],
                owner
            );

            simnet.callPublicFn(
                "rental",
                "purchase-tokens",
                [Cl.principal(owner), Cl.uint(purchaseAmount)],
                tenant
            );

            const transferAmount = 2;
            const transferCall = simnet.callPublicFn(
                "rental",
                "transfer-rental-tokens",
                [Cl.principal(tenant2), Cl.principal(owner), Cl.uint(transferAmount)],
                tenant
            );
            expect(transferCall.result).toBeOk(Cl.bool(true));

            const recipient_balance = simnet.callReadOnlyFn(
                "rental",
                "get-tenant-tokens",
                [Cl.principal(owner), Cl.principal(tenant2)],
                tenant2
            );

        expect(recipient_balance.result).toStrictEqual(Cl.some(Cl.uint(transferAmount)));
        });
    });

    describe("property details", () => {
      it("allows setting property details", () => {
          // First register the property to establish ownership
          simnet.callPublicFn(
              "rental",
              "register-property",
              [Cl.uint(totalTokens), Cl.uint(pricePerToken)],
              owner
          );
  
          const description = "Luxury Apartment";
          const location = "New York";
          
          const setDetailsCall = simnet.callPublicFn(
              "rental",
              "set-property-details",
              [Cl.stringUtf8(description), Cl.stringUtf8(location)],
              owner
          );
          expect(setDetailsCall.result).toBeOk(Cl.bool(true));
      });
  });
  

    describe("property rating", () => {
        it("allows rating by tenants", () => {
            // Setup: Register and purchase to become tenant
            simnet.callPublicFn(
                "rental",
                "register-property",
                [Cl.uint(totalTokens), Cl.uint(pricePerToken)],
                owner
            );

            simnet.callPublicFn(
                "rental",
                "purchase-tokens",
                [Cl.principal(owner), Cl.uint(purchaseAmount)],
                tenant
            );

            const ratingCall = simnet.callPublicFn(
                "rental",
                "rate-property",
                [Cl.principal(owner), Cl.uint(5)],
                tenant
            );
            expect(ratingCall.result).toBeOk(Cl.bool(true));
        });
    });

    describe("rental duration", () => {
        it("sets rental period correctly", () => {
            const duration = 100; // blocks
            const setPeriodCall = simnet.callPublicFn(
                "rental",
                "set-rental-period",
                [Cl.principal(owner), Cl.uint(duration)],
                tenant
            );
            expect(setPeriodCall.result).toBeOk(Cl.bool(true));
        });
    });
});
