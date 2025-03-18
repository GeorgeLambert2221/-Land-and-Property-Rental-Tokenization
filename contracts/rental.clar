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

