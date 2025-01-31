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
