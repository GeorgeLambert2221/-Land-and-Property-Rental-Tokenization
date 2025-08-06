;; Property Insurance Management Contract
;; Manages insurance policies, premiums, claims, and coverage for rental properties

;; Define constants
(define-constant INSURANCE_POOL (as-contract tx-sender))
(define-constant MIN_COVERAGE_AMOUNT u10000)
(define-constant MAX_CLAIM_AMOUNT u1000000)
(define-constant CLAIM_PROCESSING_FEE u100)
(define-constant POLICY_ADMIN_FEE u50)

;; Error codes
(define-constant ERR_UNAUTHORIZED u500)
(define-constant ERR_POLICY_NOT_FOUND u501)
(define-constant ERR_POLICY_EXPIRED u502)
(define-constant ERR_INVALID_COVERAGE u503)
(define-constant ERR_INSUFFICIENT_PREMIUM u504)
(define-constant ERR_CLAIM_NOT_FOUND u505)
(define-constant ERR_CLAIM_ALREADY_PROCESSED u506)
(define-constant ERR_INVALID_CLAIM_AMOUNT u507)
(define-constant ERR_COVERAGE_EXCEEDED u508)
(define-constant ERR_INVALID_RISK_ASSESSMENT u509)
(define-constant ERR_POLICY_ACTIVE u510)

;; Data structures for insurance policies
(define-map insurance-policies
    principal  ;; property address
    {policy-id: (string-ascii 20),
     coverage-amount: uint,
     premium-amount: uint,
     start-date: uint,
     expiry-date: uint,
     policy-type: (string-ascii 15), ;; "comprehensive", "basic", "premium"
     deductible: uint,
     active: bool,
     owner: principal})

;; Claims tracking
(define-map insurance-claims
    {property: principal, claim-id: uint}
    {claimant: principal,
     claim-amount: uint,
     claim-type: (string-ascii 20),
     description: (string-utf8 200),
     submission-date: uint,
     status: (string-ascii 15), ;; "pending", "investigating", "approved", "rejected", "paid"
     assessor: (optional principal),
     settlement-amount: uint,
     evidence-hash: (optional (buff 32))})

;; Premium payment tracking
(define-map premium-payments
    {property: principal, period: uint}
    {amount-paid: uint,
     payment-date: uint,
     payment-method: (string-ascii 10),
     late-fee: uint})

;; Risk assessment data
(define-map property-risk-profiles
    principal
    {risk-score: uint, ;; 1-100, higher = riskier
     location-risk: uint,
     property-age: uint,
     safety-features: uint,
     last-assessment: uint,
     assessor: principal})

;; Insurance adjusters and assessors
(define-map authorized-assessors
    principal
    {qualification: (string-ascii 30),
     license-number: (string-ascii 20),
     authorized-date: uint,
     active: bool})

;; Coverage types and rates
(define-map coverage-rates
    (string-ascii 15) ;; policy type
    {base-rate: uint,    ;; rate per 1000 coverage units
     risk-multiplier: uint,
     min-coverage: uint,
     max-coverage: uint})

;; Claim counter for unique IDs
(define-map claim-counters principal uint)

;; Pool funds tracking
(define-map insurance-pool-balance uint uint) ;; stores total pool balance

;; Initialize coverage rates for different policy types
(define-public (initialize-coverage-rates)
    (begin
        (map-set coverage-rates "basic" 
            {base-rate: u50, risk-multiplier: u10, min-coverage: u10000, max-coverage: u100000})
        (map-set coverage-rates "comprehensive"
            {base-rate: u75, risk-multiplier: u15, min-coverage: u20000, max-coverage: u500000})
        (map-set coverage-rates "premium"
            {base-rate: u100, risk-multiplier: u20, min-coverage: u50000, max-coverage: u1000000})
        (ok true)))

;; Create insurance policy for a property
(define-public (create-policy (property principal) 
                             (policy-id (string-ascii 20))
                             (coverage-amount uint)
                             (policy-type (string-ascii 15))
                             (duration uint))
    (let ((sender tx-sender)
          (rates (unwrap! (map-get? coverage-rates policy-type) (err ERR_INVALID_COVERAGE)))
          (risk-data (map-get? property-risk-profiles property))
          (base-premium (* (/ coverage-amount u1000) (get base-rate rates)))
          (risk-multiplier (match risk-data
                           some-risk (+ u100 (* (get risk-score some-risk) (get risk-multiplier rates)))
                           u100))
          (total-premium (/ (* base-premium risk-multiplier) u100))
          (start-date stacks-block-height)
          (expiry-date (+ start-date duration)))
        
        (asserts! (>= coverage-amount (get min-coverage rates)) (err ERR_INVALID_COVERAGE))
        (asserts! (<= coverage-amount (get max-coverage rates)) (err ERR_INVALID_COVERAGE))
        (asserts! (is-none (map-get? insurance-policies property)) (err ERR_POLICY_ACTIVE))
        
        ;; Transfer premium payment to insurance pool
        (try! (stx-transfer? (+ total-premium POLICY_ADMIN_FEE) sender INSURANCE_POOL))
        
        (ok (map-set insurance-policies property
            {policy-id: policy-id,
             coverage-amount: coverage-amount,
             premium-amount: total-premium,
             start-date: start-date,
             expiry-date: expiry-date,
             policy-type: policy-type,
             deductible: (/ coverage-amount u20), ;; 5% deductible
             active: true,
             owner: sender}))))

;; Submit insurance claim
(define-public (submit-claim (property principal)
                           (claim-amount uint)
                           (claim-type (string-ascii 20))
                           (description (string-utf8 200))
                           (evidence-hash (buff 32)))
    (let ((sender tx-sender)
          (policy (unwrap! (map-get? insurance-policies property) (err ERR_POLICY_NOT_FOUND)))
          (current-counter (default-to u0 (map-get? claim-counters property)))
          (new-claim-id (+ current-counter u1)))
        
        (asserts! (get active policy) (err ERR_POLICY_EXPIRED))
        (asserts! (> (get expiry-date policy) stacks-block-height) (err ERR_POLICY_EXPIRED))
        (asserts! (<= claim-amount (get coverage-amount policy)) (err ERR_COVERAGE_EXCEEDED))
        (asserts! (>= claim-amount u1) (err ERR_INVALID_CLAIM_AMOUNT))
        
        ;; Only policy owner or authorized tenant can submit claims
        (asserts! (or (is-eq sender (get owner policy))
                     (is-tenant-authorized sender property)) (err ERR_UNAUTHORIZED))
        
        (map-set claim-counters property new-claim-id)
        (ok (map-set insurance-claims 
            {property: property, claim-id: new-claim-id}
            {claimant: sender,
             claim-amount: claim-amount,
             claim-type: claim-type,
             description: description,
             submission-date: stacks-block-height,
             status: "pending",
             assessor: none,
             settlement-amount: u0,
             evidence-hash: (some evidence-hash)}))))

;; Assign assessor to claim
(define-public (assign-assessor (property principal) (claim-id uint) (assessor principal))
    (let ((claim-data (unwrap! (map-get? insurance-claims {property: property, claim-id: claim-id}) (err ERR_CLAIM_NOT_FOUND)))
          (assessor-data (unwrap! (map-get? authorized-assessors assessor) (err ERR_UNAUTHORIZED))))
        
        (asserts! (get active assessor-data) (err ERR_UNAUTHORIZED))
        (asserts! (is-eq (get status claim-data) "pending") (err ERR_CLAIM_ALREADY_PROCESSED))
        
        (ok (map-set insurance-claims
            {property: property, claim-id: claim-id}
            (merge claim-data {status: "investigating", assessor: (some assessor)})))))

;; Process claim decision
(define-public (process-claim (property principal) 
                            (claim-id uint) 
                            (approved bool) 
                            (settlement-amount uint))
    (let ((sender tx-sender)
          (claim-data (unwrap! (map-get? insurance-claims {property: property, claim-id: claim-id}) (err ERR_CLAIM_NOT_FOUND)))
          (policy (unwrap! (map-get? insurance-policies property) (err ERR_POLICY_NOT_FOUND))))
        
        (asserts! (is-eq (some sender) (get assessor claim-data)) (err ERR_UNAUTHORIZED))
        (asserts! (is-eq (get status claim-data) "investigating") (err ERR_CLAIM_ALREADY_PROCESSED))
        
        (if approved
            (begin
                (asserts! (<= settlement-amount (get claim-amount claim-data)) (err ERR_INVALID_CLAIM_AMOUNT))
                (asserts! (>= settlement-amount (get deductible policy)) (err ERR_INVALID_CLAIM_AMOUNT))
                
                ;; Transfer settlement from insurance pool to claimant
                (try! (as-contract (stx-transfer? settlement-amount tx-sender (get claimant claim-data))))
                
                (ok (map-set insurance-claims
                    {property: property, claim-id: claim-id}
                    (merge claim-data {status: "approved", settlement-amount: settlement-amount}))))
            
            (ok (map-set insurance-claims
                {property: property, claim-id: claim-id}
                (merge claim-data {status: "rejected", settlement-amount: u0}))))))

;; Conduct property risk assessment
(define-public (conduct-risk-assessment (property principal)
                                      (risk-score uint)
                                      (location-risk uint)
                                      (property-age uint)
                                      (safety-features uint))
    (let ((sender tx-sender))
        (asserts! (is-some (map-get? authorized-assessors sender)) (err ERR_UNAUTHORIZED))
        (asserts! (<= risk-score u100) (err ERR_INVALID_RISK_ASSESSMENT))
        (asserts! (<= location-risk u100) (err ERR_INVALID_RISK_ASSESSMENT))
        (asserts! (<= safety-features u100) (err ERR_INVALID_RISK_ASSESSMENT))
        
        (ok (map-set property-risk-profiles property
            {risk-score: risk-score,
             location-risk: location-risk,
             property-age: property-age,
             safety-features: safety-features,
             last-assessment: stacks-block-height,
             assessor: sender}))))

;; Register insurance assessor
(define-public (register-assessor (qualification (string-ascii 30)) (license-number (string-ascii 20)))
    (let ((sender tx-sender))
        (ok (map-set authorized-assessors sender
            {qualification: qualification,
             license-number: license-number,
             authorized-date: stacks-block-height,
             active: true}))))

;; Pay insurance premium
(define-public (pay-premium (property principal) (payment-method (string-ascii 10)))
    (let ((sender tx-sender)
          (policy (unwrap! (map-get? insurance-policies property) (err ERR_POLICY_NOT_FOUND)))
          (current-period (/ stacks-block-height u1440)) ;; daily periods
          (premium-amount (get premium-amount policy)))
        
        (asserts! (is-eq sender (get owner policy)) (err ERR_UNAUTHORIZED))
        (asserts! (get active policy) (err ERR_POLICY_EXPIRED))
        
        (try! (stx-transfer? premium-amount sender INSURANCE_POOL))
        
        (ok (map-set premium-payments
            {property: property, period: current-period}
            {amount-paid: premium-amount,
             payment-date: stacks-block-height,
             payment-method: payment-method,
             late-fee: u0}))))

;; Renew insurance policy
(define-public (renew-policy (property principal) (new-duration uint))
    (let ((sender tx-sender)
          (policy (unwrap! (map-get? insurance-policies property) (err ERR_POLICY_NOT_FOUND)))
          (new-expiry (+ stacks-block-height new-duration)))
        
        (asserts! (is-eq sender (get owner policy)) (err ERR_UNAUTHORIZED))
        (asserts! (get active policy) (err ERR_POLICY_EXPIRED))
        
        ;; Calculate renewal premium
        (try! (stx-transfer? (get premium-amount policy) sender INSURANCE_POOL))
        
        (ok (map-set insurance-policies property
            (merge policy {expiry-date: new-expiry})))))

;; Cancel insurance policy
(define-public (cancel-policy (property principal))
    (let ((sender tx-sender)
          (policy (unwrap! (map-get? insurance-policies property) (err ERR_POLICY_NOT_FOUND))))
        
        (asserts! (is-eq sender (get owner policy)) (err ERR_UNAUTHORIZED))
        
        (ok (map-set insurance-policies property
            (merge policy {active: false})))))

;; Helper function to check if tenant is authorized (simplified check)
(define-private (is-tenant-authorized (tenant principal) (property principal))
    true) ;; This would integrate with the main rental contract

;; Read-only functions
(define-read-only (get-policy-details (property principal))
    (map-get? insurance-policies property))

(define-read-only (get-claim-details (property principal) (claim-id uint))
    (map-get? insurance-claims {property: property, claim-id: claim-id}))

(define-read-only (get-risk-profile (property principal))
    (map-get? property-risk-profiles property))

(define-read-only (get-premium-payment (property principal) (period uint))
    (map-get? premium-payments {property: property, period: period}))

(define-read-only (is-policy-active (property principal))
    (let ((policy (map-get? insurance-policies property)))
        (match policy
            some-policy (and (get active some-policy)
                           (> (get expiry-date some-policy) stacks-block-height))
            false)))

(define-read-only (calculate-premium-quote (coverage-amount uint) 
                                         (policy-type (string-ascii 15)) 
                                         (property principal))
    (let ((rates (unwrap! (map-get? coverage-rates policy-type) (err ERR_INVALID_COVERAGE)))
          (risk-data (map-get? property-risk-profiles property))
          (base-premium (* (/ coverage-amount u1000) (get base-rate rates)))
          (risk-multiplier (match risk-data
                           some-risk (+ u100 (* (get risk-score some-risk) (get risk-multiplier rates)))
                           u100)))
        (ok (/ (* base-premium risk-multiplier) u100))))

(define-read-only (get-coverage-rates (policy-type (string-ascii 15)))
    (map-get? coverage-rates policy-type))

(define-read-only (is-assessor-authorized (assessor principal))
    (let ((assessor-data (map-get? authorized-assessors assessor)))
        (match assessor-data
            some-data (get active some-data)
            false)))


