;; Land and Property Rental Tokenization Contract

;; Define the token
(define-fungible-token rental-token)

;; Data maps
(define-map properties 
    principal 
    {owner: principal, 
     total-tokens: uint,
     price-per-token: uint,
     available-tokens: uint})

(define-map tenant-holdings
    {property: principal, tenant: principal}
    uint)

;; Public functions
(define-public (register-property (total-tokens uint) (price-per-token uint))
    (let ((sender tx-sender))
        (ok (map-set properties 
            sender
            {owner: sender,
             total-tokens: total-tokens,
             price-per-token: price-per-token,
             available-tokens: total-tokens}))))

(define-public (purchase-tokens (property principal) (token-amount uint))
    (let ((sender tx-sender)
          (property-data (unwrap! (map-get? properties property) (err u1)))
          (purchase-cost (* token-amount (get price-per-token property-data))))
        (asserts! (<= token-amount (get available-tokens property-data)) (err u2))
        (try! (stx-transfer? purchase-cost sender property))
        (try! (ft-mint? rental-token token-amount sender))
        (map-set properties 
            property
            (merge property-data 
                   {available-tokens: (- (get available-tokens property-data) token-amount)}))
        (map-set tenant-holdings
            {property: property, tenant: sender}
            token-amount)
        (ok true)))

;; Read-only functions
(define-read-only (get-property-details (property principal))
    (map-get? properties property))

(define-read-only (get-tenant-tokens (property principal) (tenant principal))
    (map-get? tenant-holdings {property: property, tenant: tenant}))

(define-map maintenance-funds principal uint)

(define-public (add-maintenance-fund (property principal) (amount uint))
    (let ((sender tx-sender))
        (try! (stx-transfer? amount sender property))
        (ok (map-set maintenance-funds 
            property 
            (+ (default-to u0 (map-get? maintenance-funds property)) amount)))))

(define-public (transfer-rental-tokens (recipient principal) (property principal) (amount uint))
    (let ((sender tx-sender)
          (sender-balance (default-to u0 (map-get? tenant-holdings {property: property, tenant: sender}))))
        (asserts! (>= sender-balance amount) (err u6))
        (try! (ft-transfer? rental-token amount sender recipient))
        (map-set tenant-holdings {property: property, tenant: sender} (- sender-balance amount))
        (map-set tenant-holdings 
            {property: property, tenant: recipient} 
            (+ (default-to u0 (map-get? tenant-holdings {property: property, tenant: recipient})) amount))
        (ok true)))

(define-map rental-duration
    {property: principal, tenant: principal}
    {start-time: uint, end-time: uint})

(define-public (set-rental-period (property principal) (duration uint))
    (let ((sender tx-sender)
          (start-time stacks-block-height))
        (ok (map-set rental-duration
            {property: property, tenant: sender}
            {start-time: start-time, 
             end-time: (+ start-time duration)}))))

(define-map income-distribution principal uint)

(define-public (distribute-income (property principal))
    (let ((total-income (default-to u0 (map-get? income-distribution property)))
          (property-data (unwrap! (map-get? properties property) (err u8))))
        (try! (stx-transfer? total-income property (get owner property-data)))
        (ok (map-set income-distribution property u0))))

(define-map property-expiry principal uint) ;; Unix timestamp

(define-read-only (is-property-owner (address principal))
    (let ((property-data (map-get? properties address)))
        (and (is-some property-data)
             (is-eq address (get owner (unwrap-panic property-data))))))

(define-public (set-property-expiry (expiry-date uint))
    (let ((sender tx-sender))
        (asserts! (is-property-owner sender) (err u3))
        (ok (map-set property-expiry sender expiry-date))))

(define-read-only (is-listing-active (property principal))
    (let ((expiry (default-to u0 (map-get? property-expiry property))))
        (< stacks-block-height expiry)))

(define-read-only (has-rented-property (tenant principal) (property principal))
    (is-some (map-get? tenant-holdings {property: property, tenant: tenant})))

(define-map property-ratings 
    {property: principal, rater: principal}
    uint)

(define-public (rate-property (property principal) (rating uint))
    (let ((sender tx-sender))
        (asserts! (<= rating u5) (err u4))
        (asserts! (has-rented-property sender property) (err u5))
        (ok (map-set property-ratings {property: property, rater: sender} rating))))

(define-map property-details 
    principal 
    {description: (string-utf8 500), 
     location: (string-utf8 100)})

(define-public (set-property-details (description (string-utf8 500)) (location (string-utf8 100)))
    (let ((sender tx-sender))
        (asserts! (is-property-owner sender) (err u7))
        (ok (map-set property-details 
            sender 
            {description: description, 
             location: location}))))


;; Feature 1: Update rental token price
(define-public (update-price-per-token (property principal) (new-price uint))
    (let (
          (property-data (unwrap! (map-get? properties property) (err u9)))
          (sender tx-sender))
      (asserts! (is-eq sender (get owner property-data)) (err u10))
      (map-set properties property (merge property-data {price-per-token: new-price}))
      (ok true)))

;; Feature 2: Cancel a property listing by burning remaining tokens
(define-public (cancel-property-listing (property principal))
    (let ((property-data (unwrap! (map-get? properties property) (err u11)))
          (sender tx-sender)
          (remaining-tokens (get available-tokens property-data)))
      (asserts! (is-eq sender (get owner property-data)) (err u12))
      ;; Assuming ft-burn? is available to burn tokens
      (try! (ft-burn? rental-token remaining-tokens sender))
      (map-set properties property (merge property-data {available-tokens: u0}))
      (ok true)))

;; Feature 3: Track rental history (log the timestamp of a rental)
(define-map rental-history {tenant: principal, property: principal} uint)

(define-public (log-rental-history (property principal))
    (let ((sender tx-sender)
          (current-time stacks-block-height))
        (map-set rental-history {tenant: sender, property: property} current-time)
        (ok true)))

(define-read-only (get-rental-history (tenant principal) (property principal))
    (map-get? rental-history {tenant: tenant, property: property}))

;; Feature 4: Dispute resolution between tenant and property owner
(define-map dispute-requests {property: principal, tenant: principal} {timestamp: uint, description: (string-utf8 200)})

(define-public (file-dispute (property principal) (description (string-utf8 200)))
    (let ((sender tx-sender)
          (timestamp stacks-block-height))
        (asserts! (has-rented-property sender property) (err u13))
        (map-set dispute-requests {property: property, tenant: sender} {timestamp: timestamp, description: description})
        (ok true)))

(define-public (resolve-dispute (property principal) (tenant principal))
    (let ((sender tx-sender)
          (property-data (unwrap! (map-get? properties property) (err u14))))
        (asserts! (is-eq sender (get owner property-data)) (err u15))
        (map-delete dispute-requests {property: property, tenant: tenant})
        (ok true)))

;; Feature 5: Installment rent payments (allow tenants to pay rent in installments)
(define-map installment-payments {tenant: principal, property: principal} uint)

(define-public (pay-installment (property principal) (amount uint))
    (let ((sender tx-sender)
          (current-installments (default-to u0 (map-get? installment-payments {tenant: sender, property: property}))))
        (try! (stx-transfer? amount sender property))
        (map-set installment-payments {tenant: sender, property: property} (+ current-installments amount))
        (ok true)))

(define-read-only (get-installment-payments (tenant principal) (property principal))
    (map-get? installment-payments {tenant: tenant, property: property}))

;; Feature 6: Maintenance scheduling (property tenants can request and complete maintenance tasks)
(define-map maintenance-schedule {property: principal, maintenance-id: uint} {scheduled-date: uint, description: (string-utf8 200), completed: bool})
(define-map maintenance-counter principal uint)

(define-public (schedule-maintenance (property principal) (scheduled-date uint) (description (string-utf8 200)))
    (let ((sender tx-sender)
          (counter (default-to u0 (map-get? maintenance-counter property))))
        (asserts! (has-rented-property sender property) (err u16))
        (let ((new-id (+ counter u1)))
            (map-set maintenance-counter property new-id)
            (map-set maintenance-schedule {property: property, maintenance-id: new-id} {scheduled-date: scheduled-date, description: description, completed: false})
            (ok new-id))))

(define-public (complete-maintenance (property principal) (maintenance-id uint))
    (let ((sender tx-sender)
          (schedule (unwrap! (map-get? maintenance-schedule {property: property, maintenance-id: maintenance-id}) (err u17))))
        (asserts! (has-rented-property sender property) (err u18))
        (map-set maintenance-schedule {property: property, maintenance-id: maintenance-id} (merge schedule {completed: true}))
        (ok true)))

(define-read-only (get-maintenance-schedule (property principal) (maintenance-id uint))
    (map-get? maintenance-schedule {property: property, maintenance-id: maintenance-id}))

;; Feature 7: Get rental period info (returns start and end times for a tenant/property rental)
(define-read-only (get-rental-period (property principal) (tenant principal))
    (map-get? rental-duration {property: property, tenant: tenant}))


(define-map referral-rewards 
    {referrer: principal, property: principal} 
    uint)

(define-map referral-codes 
    (string-ascii 10) 
    {creator: principal, property: principal})

(define-public (create-referral-code (property principal) (code (string-ascii 10)))
    (let ((sender tx-sender))
        (asserts! (is-property-owner sender) (err u20))
        (ok (map-set referral-codes 
            code 
            {creator: sender, 
             property: property}))))

(define-public (rent-with-referral (property principal) (token-amount uint) (ref-code (string-ascii 10)))
    (let ((sender tx-sender)
          (ref-data (unwrap! (map-get? referral-codes ref-code) (err u21)))
          (reward-amount u100))
        (try! (purchase-tokens property token-amount))
        (try! (stx-transfer? reward-amount property (get creator ref-data)))
        (map-set referral-rewards 
            {referrer: (get creator ref-data), property: property}
            (+ (default-to u0 (map-get? referral-rewards {referrer: (get creator ref-data), property: property})) 
               reward-amount))
        (ok true)))


(define-map property-occupancy
    principal
    {total-days: uint,
     occupied-days: uint,
     last-updated: uint})

(define-public (initialize-occupancy (property principal))
    (let ((sender tx-sender))
        (asserts! (is-property-owner sender) (err u22))
        (ok (map-set property-occupancy
            property
            {total-days: u0,
             occupied-days: u0,
             last-updated: stacks-block-height}))))

(define-public (update-occupancy (property principal) (is-occupied bool))
    (let ((sender tx-sender)
          (current-data (unwrap! (map-get? property-occupancy property) (err u23)))
          (days-since-update (- stacks-block-height (get last-updated current-data))))
        (asserts! (is-property-owner sender) (err u24))
        (ok (map-set property-occupancy
            property
            {total-days: (+ (get total-days current-data) days-since-update),
             occupied-days: (+ (get occupied-days current-data) 
                             (if is-occupied days-since-update u0)),
             last-updated: stacks-block-height}))))

(define-read-only (get-occupancy-rate (property principal))
    (let ((data (unwrap! (map-get? property-occupancy property) (err u25))))
        (ok (/ (* (get occupied-days data) u100) (get total-days data)))))

(define-map payment-schedules
    principal
    {interval: uint,
     amount: uint,
     next-due: uint})

(define-map payment-history
    {property: principal, tenant: principal}
    (list 10 {timestamp: uint, amount: uint}))

(define-public (set-payment-schedule (property principal) (interval uint) (amount uint))
    (let ((sender tx-sender))
        (asserts! (is-property-owner sender) (err u100))
        (ok (map-set payment-schedules 
            property 
            {interval: interval,
             amount: amount,
             next-due: (+ stacks-block-height interval)}))))

(define-public (make-scheduled-payment (property principal))
    (let ((sender tx-sender)
          (schedule (unwrap! (map-get? payment-schedules property) (err u101)))
          (current-history (default-to (list) (map-get? payment-history {property: property, tenant: sender}))))
        (try! (stx-transfer? (get amount schedule) sender property))
        (map-set payment-schedules property 
            (merge schedule {next-due: (+ (get next-due schedule) (get interval schedule))}))
        (ok (map-set payment-history 
            {property: property, tenant: sender}
            (unwrap-panic (as-max-len? (append current-history {timestamp: stacks-block-height, amount: (get amount schedule)}) u10))))))




(define-map access-permissions
    {property: principal, tenant: principal}
    {active: bool, 
     start-time: uint,
     end-time: uint,
     access-level: uint})

(define-public (grant-access (property principal) (tenant principal) (duration uint) (level uint))
    (let ((sender tx-sender))
        (asserts! (is-property-owner sender) (err u200))
        (ok (map-set access-permissions
            {property: property, tenant: tenant}
            {active: true,
             start-time: stacks-block-height,
             end-time: (+ stacks-block-height duration),
             access-level: level}))))

(define-read-only (check-access (property principal) (tenant principal))
    (let ((access-data (unwrap! (map-get? access-permissions {property: property, tenant: tenant}) (err u201))))
        (ok (and 
            (get active access-data)
            (>= (get end-time access-data) stacks-block-height)
            (>= stacks-block-height (get start-time access-data))))))


(define-map rent-collection-settings
    principal
    {monthly-rent: uint,
     due-day: uint,
     late-fee-rate: uint,
     grace-period: uint})

(define-map tenant-rent-status
    {property: principal, tenant: principal}
    {last-payment: uint,
     amount-due: uint,
     late-fees: uint,
     payment-status: (string-ascii 10)})

(define-map rent-payment-ledger
    {property: principal, tenant: principal, month: uint}
    {amount-paid: uint,
     payment-date: uint,
     late-fee-charged: uint})

(define-public (setup-rent-collection (property principal) (monthly-rent uint) (due-day uint) (late-fee-rate uint) (grace-period uint))
    (let ((sender tx-sender))
        (asserts! (is-property-owner sender) (err u300))
        (asserts! (<= due-day u30) (err u301))
        (asserts! (<= late-fee-rate u50) (err u302))
        (ok (map-set rent-collection-settings
            property
            {monthly-rent: monthly-rent,
             due-day: due-day,
             late-fee-rate: late-fee-rate,
             grace-period: grace-period}))))

(define-public (calculate-rent-due (property principal) (tenant principal))
    (let ((settings (unwrap! (map-get? rent-collection-settings property) (err u303)))
          (current-month (/ stacks-block-height u144))
          (current-status (default-to 
            {last-payment: u0, amount-due: u0, late-fees: u0, payment-status: "current"}
            (map-get? tenant-rent-status {property: property, tenant: tenant})))
          (days-late (if (> stacks-block-height (+ (get last-payment current-status) (get grace-period settings)))
                        (- stacks-block-height (+ (get last-payment current-status) (get grace-period settings)))
                        u0))
          (late-fee (if (> days-late u0)
                       (/ (* (get monthly-rent settings) (get late-fee-rate settings)) u100)
                       u0))
          (total-due (+ (get monthly-rent settings) late-fee (get amount-due current-status))))
        (map-set tenant-rent-status
            {property: property, tenant: tenant}
            {last-payment: (get last-payment current-status),
             amount-due: total-due,
             late-fees: (+ (get late-fees current-status) late-fee),
             payment-status: (if (> days-late u0) "late" "current")})
        (ok total-due)))

(define-public (pay-rent (property principal))
    (let ((sender tx-sender)
          (settings (unwrap! (map-get? rent-collection-settings property) (err u304)))
          (current-month (/ stacks-block-height u144))
          (rent-status (unwrap! (map-get? tenant-rent-status {property: property, tenant: sender}) (err u305)))
          (amount-to-pay (get amount-due rent-status)))
        (asserts! (has-rented-property sender property) (err u306))
        (asserts! (> amount-to-pay u0) (err u307))
        (try! (stx-transfer? amount-to-pay sender property))
        (map-set tenant-rent-status
            {property: property, tenant: sender}
            {last-payment: stacks-block-height,
             amount-due: u0,
             late-fees: u0,
             payment-status: "current"})
        (map-set rent-payment-ledger
            {property: property, tenant: sender, month: current-month}
            {amount-paid: amount-to-pay,
             payment-date: stacks-block-height,
             late-fee-charged: (get late-fees rent-status)})
        (ok true)))

(define-public (process-monthly-charges (property principal))
    (let ((sender tx-sender)
          (settings (unwrap! (map-get? rent-collection-settings property) (err u308))))
        (asserts! (is-property-owner sender) (err u309))
        (ok true)))

(define-read-only (get-rent-status (property principal) (tenant principal))
    (map-get? tenant-rent-status {property: property, tenant: tenant}))

(define-read-only (get-payment-history (property principal) (tenant principal) (month uint))
    (map-get? rent-payment-ledger {property: property, tenant: tenant, month: month}))

(define-read-only (get-rent-settings (property principal))
    (map-get? rent-collection-settings property))

(define-public (waive-late-fees (property principal) (tenant principal))
    (let ((sender tx-sender)
          (current-status (unwrap! (map-get? tenant-rent-status {property: property, tenant: tenant}) (err u310))))
        (asserts! (is-property-owner sender) (err u311))
        (ok (map-set tenant-rent-status
            {property: property, tenant: tenant}
            (merge current-status {late-fees: u0})))))

(define-public (update-rent-amount (property principal) (new-rent uint))
    (let ((sender tx-sender)
          (current-settings (unwrap! (map-get? rent-collection-settings property) (err u312))))
        (asserts! (is-property-owner sender) (err u313))
        (asserts! (> new-rent u0) (err u314))
        (ok (map-set rent-collection-settings
            property
            (merge current-settings {monthly-rent: new-rent})))))


(define-map authorized-validators principal uint)
(define-map validator-stakes principal uint)
(define-constant VALIDATOR_STAKE_REQUIRED u1000000)

(define-map property-certifications 
    principal 
    {certified: bool,
     validator: principal,
     certification-date: uint,
     expiry-date: uint,
     cert-type: (string-ascii 20),
     cert-hash: (buff 32)})

(define-map certification-requests
    {property: principal, request-id: uint}
    {owner: principal,
     validator: principal,
     request-date: uint,
     status: (string-ascii 10),
     cert-type: (string-ascii 20)})

(define-map request-counter principal uint)

(define-public (register-validator)
    (let ((sender tx-sender))
        (try! (stx-transfer? VALIDATOR_STAKE_REQUIRED sender (as-contract tx-sender)))
        (map-set validator-stakes sender VALIDATOR_STAKE_REQUIRED)
        (ok (map-set authorized-validators sender stacks-block-height))))

(define-public (request-certification (property principal) (cert-type (string-ascii 20)) (validator principal))
    (let ((sender tx-sender)
          (current-counter (default-to u0 (map-get? request-counter property)))
          (new-request-id (+ current-counter u1)))
        (asserts! (is-property-owner property) (err u400))
        (asserts! (is-some (map-get? authorized-validators validator)) (err u401))
        (map-set request-counter property new-request-id)
        (ok (map-set certification-requests
            {property: property, request-id: new-request-id}
            {owner: sender,
             validator: validator,
             request-date: stacks-block-height,
             status: "pending",
             cert-type: cert-type}))))

(define-public (approve-certification (property principal) (request-id uint) (cert-hash (buff 32)) (validity-period uint))
    (let ((sender tx-sender)
          (request-data (unwrap! (map-get? certification-requests {property: property, request-id: request-id}) (err u402))))
        (asserts! (is-some (map-get? authorized-validators sender)) (err u403))
        (asserts! (is-eq sender (get validator request-data)) (err u404))
        (asserts! (is-eq (get status request-data) "pending") (err u405))
        (map-set certification-requests
            {property: property, request-id: request-id}
            (merge request-data {status: "approved"}))
        (ok (map-set property-certifications
            property
            {certified: true,
             validator: sender,
             certification-date: stacks-block-height,
             expiry-date: (+ stacks-block-height validity-period),
             cert-type: (get cert-type request-data),
             cert-hash: cert-hash}))))

(define-public (revoke-certification (property principal))
    (let ((sender tx-sender)
          (cert-data (unwrap! (map-get? property-certifications property) (err u406))))
        (asserts! (is-some (map-get? authorized-validators sender)) (err u407))
        (asserts! (is-eq sender (get validator cert-data)) (err u408))
        (ok (map-set property-certifications
            property
            (merge cert-data {certified: false})))))

(define-read-only (is-property-certified (property principal))
    (let ((cert-data (map-get? property-certifications property)))
        (match cert-data
            some-cert (and 
                      (get certified some-cert)
                      (> (get expiry-date some-cert) stacks-block-height))
            false)))

(define-read-only (get-certification-details (property principal))
    (map-get? property-certifications property))

(define-read-only (get-certification-request (property principal) (request-id uint))
    (map-get? certification-requests {property: property, request-id: request-id}))

(define-read-only (is-validator (address principal))
    (is-some (map-get? authorized-validators address)))

(define-public (withdraw-validator-stake)
    (let ((sender tx-sender)
          (stake-amount (unwrap! (map-get? validator-stakes sender) (err u409))))
        (map-delete authorized-validators sender)
        (map-delete validator-stakes sender)
        (ok (try! (as-contract (stx-transfer? stake-amount tx-sender sender))))))