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



;; Add to data map
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


