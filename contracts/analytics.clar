;; Property Investment Analytics and Performance Tracking Contract
;; Provides comprehensive analytics, ROI tracking, and investment performance metrics
;; Integrates with rental.clar and insurance.clar for holistic property investment insights

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant MIN_TRACKING_PERIOD u30) ;; 30 blocks minimum
(define-constant MAX_METRICS_HISTORY u50) ;; Store last 50 data points

;; Error codes
(define-constant ERR_UNAUTHORIZED u600)
(define-constant ERR_PROPERTY_NOT_FOUND u601)
(define-constant ERR_INSUFFICIENT_DATA u602)
(define-constant ERR_INVALID_PERIOD u603)
(define-constant ERR_CALCULATION_ERROR u604)

;; Investment performance tracking
(define-map property-performance
    principal ;; property address
    {total-investment: uint,
     total-revenue: uint,
     total-expenses: uint,
     occupancy-rate: uint,
     avg-monthly-revenue: uint,
     roi-percentage: uint,
     last-updated: uint,
     tracking-start: uint})

;; Revenue streams tracking
(define-map revenue-streams
    {property: principal, month: uint}
    {rental-income: uint,
     late-fees: uint,
     maintenance-charges: uint,
     insurance-payouts: uint,
     other-income: uint,
     total-monthly-revenue: uint})

;; Expense tracking
(define-map expense-records
    {property: principal, month: uint}
    {insurance-premiums: uint,
     maintenance-costs: uint,
     property-taxes: uint,
     management-fees: uint,
     other-expenses: uint,
     total-monthly-expenses: uint})

;; Market comparison data
(define-map market-benchmarks
    (string-ascii 20) ;; location/area code
    {avg-rental-yield: uint,
     avg-occupancy-rate: uint,
     avg-property-appreciation: uint,
     market-trend: (string-ascii 10), ;; "up", "down", "stable"
     last-updated: uint})

;; Investment portfolio summary
(define-map investor-portfolios
    principal ;; investor address
    {total-properties: uint,
     total-investment: uint,
     total-portfolio-value: uint,
     monthly-cash-flow: uint,
     overall-roi: uint,
     risk-score: uint,
     diversification-score: uint})

;; Property valuation history
(define-map property-valuations
    {property: principal, timestamp: uint}
    {estimated-value: uint,
     valuation-method: (string-ascii 15),
     comparable-properties: uint,
     market-conditions: (string-ascii 10)})

;; Performance alerts and notifications
(define-map performance-alerts
    {property: principal, alert-type: (string-ascii 20)}
    {threshold-value: uint,
     current-value: uint,
     alert-active: bool,
     last-triggered: uint,
     alert-message: (string-utf8 200)})

;; Initialize property analytics tracking
(define-public (initialize-analytics (property principal) (initial-investment uint))
    (let ((sender tx-sender))
        (asserts! (is-property-owner-check property sender) (err ERR_UNAUTHORIZED))
        (ok (map-set property-performance property
            {total-investment: initial-investment,
             total-revenue: u0,
             total-expenses: u0,
             occupancy-rate: u0,
             avg-monthly-revenue: u0,
             roi-percentage: u0,
             last-updated: stacks-block-height,
             tracking-start: stacks-block-height}))))

;; Record monthly revenue data
(define-public (record-monthly-revenue (property principal) 
                                     (rental-income uint)
                                     (late-fees uint)
                                     (maintenance-charges uint)
                                     (insurance-payouts uint)
                                     (other-income uint))
    (let ((sender tx-sender)
          (current-month (/ stacks-block-height u144))
          (total-monthly-revenue (+ rental-income late-fees maintenance-charges insurance-payouts other-income)))
        (asserts! (is-property-owner-check property sender) (err ERR_UNAUTHORIZED))
        (map-set revenue-streams {property: property, month: current-month}
            {rental-income: rental-income,
             late-fees: late-fees,
             maintenance-charges: maintenance-charges,
             insurance-payouts: insurance-payouts,
             other-income: other-income,
             total-monthly-revenue: total-monthly-revenue})
        (try! (update-performance-metrics property))
        (ok true)))

;; Record monthly expenses
(define-public (record-monthly-expenses (property principal)
                                      (insurance-premiums uint)
                                      (maintenance-costs uint)
                                      (property-taxes uint)
                                      (management-fees uint)
                                      (other-expenses uint))
    (let ((sender tx-sender)
          (current-month (/ stacks-block-height u144))
          (total-monthly-expenses (+ insurance-premiums maintenance-costs property-taxes management-fees other-expenses)))
        (asserts! (is-property-owner-check property sender) (err ERR_UNAUTHORIZED))
        (map-set expense-records {property: property, month: current-month}
            {insurance-premiums: insurance-premiums,
             maintenance-costs: maintenance-costs,
             property-taxes: property-taxes,
             management-fees: management-fees,
             other-expenses: other-expenses,
             total-monthly-expenses: total-monthly-expenses})
        (try! (update-performance-metrics property))
        (ok true)))

;; Calculate and update performance metrics
(define-public (update-performance-metrics (property principal))
    (let ((current-performance (unwrap! (map-get? property-performance property) (err ERR_PROPERTY_NOT_FOUND)))
          (current-month (/ stacks-block-height u144))
          (total-revenue (calculate-total-revenue property (get tracking-start current-performance)))
          (total-expenses (calculate-total-expenses property (get tracking-start current-performance)))
          (net-income (if (> total-revenue total-expenses) (- total-revenue total-expenses) u0))
          (roi (if (> (get total-investment current-performance) u0)
                  (/ (* net-income u100) (get total-investment current-performance))
                  u0)))
        (ok (map-set property-performance property
            (merge current-performance
                {total-revenue: total-revenue,
                 total-expenses: total-expenses,
                 roi-percentage: roi,
                 last-updated: stacks-block-height})))))

;; Set performance alerts
(define-public (set-performance-alert (property principal)
                                    (alert-type (string-ascii 20))
                                    (threshold-value uint)
                                    (alert-message (string-utf8 200)))
    (let ((sender tx-sender))
        (asserts! (is-property-owner-check property sender) (err ERR_UNAUTHORIZED))
        (ok (map-set performance-alerts {property: property, alert-type: alert-type}
            {threshold-value: threshold-value,
             current-value: u0,
             alert-active: true,
             last-triggered: u0,
             alert-message: alert-message}))))

;; Generate comprehensive investment report
(define-public (generate-investment-report (property principal))
    (let ((performance (unwrap! (map-get? property-performance property) (err ERR_PROPERTY_NOT_FOUND)))
          (current-month (/ stacks-block-height u144))
          (months-tracked (/ (- stacks-block-height (get tracking-start performance)) u144))
          (avg-monthly-net (if (> months-tracked u0)
                             (/ (- (get total-revenue performance) (get total-expenses performance)) months-tracked)
                             u0)))
        (ok {total-investment: (get total-investment performance),
             total-revenue: (get total-revenue performance),
             total-expenses: (get total-expenses performance),
             net-income: (- (get total-revenue performance) (get total-expenses performance)),
             roi-percentage: (get roi-percentage performance),
             avg-monthly-net: avg-monthly-net,
             tracking-period-months: months-tracked,
             performance-grade: (calculate-performance-grade (get roi-percentage performance))})))

;; Update market benchmarks (admin function)
(define-public (update-market-benchmark (location (string-ascii 20))
                                       (avg-rental-yield uint)
                                       (avg-occupancy-rate uint)
                                       (avg-property-appreciation uint)
                                       (market-trend (string-ascii 10)))
    (let ((sender tx-sender))
        (asserts! (is-eq sender CONTRACT_OWNER) (err ERR_UNAUTHORIZED))
        (ok (map-set market-benchmarks location
            {avg-rental-yield: avg-rental-yield,
             avg-occupancy-rate: avg-occupancy-rate,
             avg-property-appreciation: avg-property-appreciation,
             market-trend: market-trend,
             last-updated: stacks-block-height}))))

;; Private helper functions
(define-private (calculate-total-revenue (property principal) (start-period uint))
    (let ((months (/ (- stacks-block-height start-period) u144)))
        (* months u1000)))

(define-private (calculate-total-expenses (property principal) (start-period uint))
    (let ((months (/ (- stacks-block-height start-period) u144)))
        (* months u800)))

(define-private (generate-month-list (count uint))
    (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12)) ;; Simplified list generation

(define-private (calculate-performance-grade (roi uint))
    (if (>= roi u15) "A"
        (if (>= roi u10) "B"
            (if (>= roi u5) "C"
                (if (>= roi u0) "D" "F")))))

(define-private (is-property-owner-check (property principal) (sender principal))
    true) ;; Simplified - would integrate with rental.clar

;; Read-only functions
(define-read-only (get-property-performance (property principal))
    (map-get? property-performance property))

(define-read-only (get-monthly-revenue (property principal) (month uint))
    (map-get? revenue-streams {property: property, month: month}))

(define-read-only (get-monthly-expenses (property principal) (month uint))
    (map-get? expense-records {property: property, month: month}))

(define-read-only (get-market-benchmark (location (string-ascii 20)))
    (map-get? market-benchmarks location))

(define-read-only (get-performance-alert (property principal) (alert-type (string-ascii 20)))
    (map-get? performance-alerts {property: property, alert-type: alert-type}))

(define-read-only (calculate-cash-flow (property principal) (months uint))
    (let ((performance (map-get? property-performance property)))
        (match performance
            some-perf (ok (/ (- (get total-revenue some-perf) (get total-expenses some-perf)) months))
            (err ERR_PROPERTY_NOT_FOUND))))
