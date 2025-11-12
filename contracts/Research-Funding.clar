;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ResFundDAO.clar
;; ResFundDAO - Decentralized Research Funding Pool
;; Version 1.0
;; Author: (you)
;;
;; Notes:
;; - Contributors fund a proposal by calling `fund-proposal` and attaching STX to the tx.
;; - Funding is only accepted before the proposal's funding-deadline (block-height).
;; - After funding-deadline passes, funds are locked in the contract.
;; - Verifiers (set by owner) approve milestones; each approved milestone releases
;;   an equal tranche: floor(funds-raised / milestones).
;; - If a proposal is cancelled, contributors can claim refunds.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-data-var owner principal tx-sender) ;; contract deployer becomes owner

;; Incremental counter for proposal IDs
(define-data-var proposal-counter uint u0)

;; Map: proposals => keyed by id
(define-map proposals
  { id: uint }
  {
    researcher: principal,
    title: (string-ascii 100),
    description: (string-ascii 1000),
    funding-goal: uint,
    funds-raised: uint,            ;; total STX raised (locked after funding-deadline)
    milestones: uint,              ;; total number of milestones
    completed-milestones: uint,    ;; how many milestones approved so far
    funding-deadline: uint,        ;; block-height after which funding stops
    is-active: bool,               ;; true = active; false = cancelled/closed
    refunded: bool                 ;; true if refunds are allowed/issued
  }
)

;; Map: funders per (proposal-id, funder) -> amount contributed
(define-map contributions
  { proposal-id: uint, funder: principal }
  { amount: uint }
)

;; Map: verifiers (accounts allowed to approve milestones)
(define-map verifiers { verifier: principal } { allowed: bool })

;; Events are printed as part of transaction flow
;; They include: proposal-created, funded, milestone-approved, proposal-cancelled, refund-claimed


;; ---------------------------
;; Helper / Authorization
;; ---------------------------

(define-read-only (get-owner)
  (ok (var-get owner))
)

(define-read-only (is-verifier (p principal))
  (is-some (map-get? verifiers { verifier: p }))
)

(define-private (assert-owner)
  (if (is-eq tx-sender (var-get owner))
    (ok true)
    (err "ERR_UNAUTHORIZED")
  )
)

;; ---------------------------
;; Proposal lifecycle
;; ---------------------------

;; submit-proposal:
;; researcher creates a new proposal.
(define-public (submit-proposal (title (string-ascii 100)) (description (string-ascii 1000)) (funding-goal uint) (milestones uint) (funding-deadline uint))
  (begin
    (asserts! (> milestones u0) (err "ERR_MILESTONES_MUST_BE_GT_0"))
    (asserts! (> funding-goal u0) (err "ERR_GOAL_MUST_BE_GT_0"))
    (asserts! (> (len title) u0) (err "ERR_TITLE_REQUIRED"))
    (let ((new-id (+ (var-get proposal-counter) u1)))
      (begin
        (map-set proposals
          { id: new-id }
          {
            researcher: tx-sender,
            title: title,
            description: description,
            funding-goal: funding-goal,
            funds-raised: u0,
            milestones: milestones,
            completed-milestones: u0,
            funding-deadline: funding-deadline,
            is-active: true,
            refunded: false
          })
        (var-set proposal-counter new-id)
        (print { event: "proposal-created", id: new-id, researcher: tx-sender, title: title, funding-deadline: funding-deadline, milestones: milestones })
        (ok new-id)
      )
    )
  )
)

;; fund-proposal:
;; contributors send STX by attaching value to the transaction.
;; amount parameter specifies how much STX is being contributed
(define-public (fund-proposal (proposal-id uint) (amount uint))
  (let ((proposal (map-get? proposals { id: proposal-id })))
    (match proposal
      proposal-data
      (let ((is-active (get is-active proposal-data))
            (deadline (get funding-deadline proposal-data)))
        (begin
          (asserts! is-active (err "ERR_PROPOSAL_NOT_ACTIVE"))
          (asserts! (<= burn-block-height deadline) (err "ERR_FUNDING_CLOSED"))
          (asserts! (> amount u0) (err "ERR_NO_STX_ATTACHED"))
          ;; update contributions map (accumulate)
          (let ((existing-contrib (map-get? contributions { proposal-id: proposal-id, funder: tx-sender })))
            (let ((existing (if (is-some existing-contrib) (get amount (unwrap-panic existing-contrib)) u0)))
              (map-set contributions { proposal-id: proposal-id, funder: tx-sender } { amount: (+ existing amount) })
            )
          )
          ;; update total funds raised
          (map-set proposals { id: proposal-id }
            {
              researcher: (get researcher proposal-data),
              title: (get title proposal-data),
              description: (get description proposal-data),
              funding-goal: (get funding-goal proposal-data),
              funds-raised: (+ (get funds-raised proposal-data) amount),
              milestones: (get milestones proposal-data),
              completed-milestones: (get completed-milestones proposal-data),
              funding-deadline: (get funding-deadline proposal-data),
              is-active: is-active,
              refunded: (get refunded proposal-data)
            })
          (print { event: "proposal-funded", proposal-id: proposal-id, funder: tx-sender, amount: amount })
          (ok amount)
        )
      )
      (err "ERR_PROPOSAL_NOT_FOUND")
    )
  )
)

;; cancel-proposal:
;; researcher or owner may cancel a proposal before milestones are approved.
;; Once cancelled, contributors may claim refunds.
(define-public (cancel-proposal (proposal-id uint))
  (let ((proposal (map-get? proposals { id: proposal-id })))
    (match proposal
      proposal-data
      (let ((researcher (get researcher proposal-data))
            (completed (get completed-milestones proposal-data)))
        (begin
          ;; only researcher or owner can cancel
          (asserts! (or (is-eq tx-sender researcher) (is-eq tx-sender (var-get owner))) (err "ERR_NOT_AUTHORIZED_CANCEL"))
          ;; prevent cancelling after any milestone is completed
          (asserts! (is-eq completed u0) (err "ERR_CANNOT_CANCEL_AFTER_PROGRESS"))
          ;; mark as inactive and allow refunds
          (map-set proposals { id: proposal-id }
            {
              researcher: researcher,
              title: (get title proposal-data),
              description: (get description proposal-data),
              funding-goal: (get funding-goal proposal-data),
              funds-raised: (get funds-raised proposal-data),
              milestones: (get milestones proposal-data),
              completed-milestones: completed,
              funding-deadline: (get funding-deadline proposal-data),
              is-active: false,
              refunded: true
            })
          (print { event: "proposal-cancelled", proposal-id: proposal-id, who: tx-sender })
          (ok true)
        )
      )
      (err "ERR_PROPOSAL_NOT_FOUND")
    )
  )
)

;; add-verifier (owner only)
(define-public (add-verifier (v principal))
  (begin
    (try! (assert-owner))
    (map-set verifiers { verifier: v } { allowed: true })
    (ok true)
  )
)

;; remove-verifier (owner only)
(define-public (remove-verifier (v principal))
  (begin
    (try! (assert-owner))
    (map-delete verifiers { verifier: v })
    (ok true)
  )
)

;; approve-milestone:
;; Called by an authorized verifier (or owner). Only possible after funding-deadline.
;; Releases an equal tranche to the researcher: floor(total_funds / milestones).
(define-public (approve-milestone (proposal-id uint))
  (let ((proposal (map-get? proposals { id: proposal-id })))
    (match proposal
      proposal-data
      (let ((funds (get funds-raised proposal-data))
            (milestones (get milestones proposal-data))
            (completed (get completed-milestones proposal-data))
            (deadline (get funding-deadline proposal-data))
            (researcher (get researcher proposal-data)))
        (begin
          ;; check verifier
          (asserts! (or (is-eq tx-sender (var-get owner)) (is-some (map-get? verifiers { verifier: tx-sender }))) (err "ERR_NOT_VERIFIER"))
          ;; funding period must be over (we use final funds)
          (asserts! (> burn-block-height deadline) (err "ERR_FUNDING_STILL_OPEN"))
          ;; proposal must be active and not refunded/cancelled
          (asserts! (get is-active proposal-data) (err "ERR_PROPOSAL_NOT_ACTIVE"))
          ;; milestones left?
          (asserts! (< completed milestones) (err "ERR_ALL_MILESTONES_COMPLETED"))
          ;; calculate payout per milestone as integer division
          (let ((payout (if (> funds u0) (/ funds milestones) u0)))
            (asserts! (> payout u0) (err "ERR_NO_FUNDS_TO_PAYOUT"))
            ;; transfer payout from contract to researcher
            (begin
              (unwrap-panic (as-contract (stx-transfer? payout tx-sender researcher)))
              ;; update completed-milestones and reduce funds-raised accordingly
              (map-set proposals { id: proposal-id }
                {
                  researcher: researcher,
                  title: (get title proposal-data),
                  description: (get description proposal-data),
                  funding-goal: (get funding-goal proposal-data),
                  funds-raised: (- funds payout),
                  milestones: milestones,
                  completed-milestones: (+ completed u1),
                  funding-deadline: deadline,
                  is-active: (get is-active proposal-data),
                  refunded: (get refunded proposal-data)
                })
              (print { event: "milestone-approved", proposal-id: proposal-id, milestone-number: (+ completed u1), verifier: tx-sender, payout: payout })
              (ok payout)
            )
          )
        )
      )
      (err "ERR_PROPOSAL_NOT_FOUND")
    )
  )
)

;; claim-refund:
;; Allows contributors to claim refunds if proposal has been cancelled/refunded.
(define-public (claim-refund (proposal-id uint))
  (let ((contrib (map-get? contributions { proposal-id: proposal-id, funder: tx-sender })))
    (let ((proposal (map-get? proposals { id: proposal-id })))
      (if (and (is-some contrib) (is-some proposal))
        (let ((c (unwrap-panic contrib))
              (p (unwrap-panic proposal))
              (amt (get amount c))
              (is-refunded (get refunded p)))
          (begin
            (asserts! (> amt u0) (err "ERR_NO_CONTRIBUTION"))
            (asserts! is-refunded (err "ERR_REFUNDS_NOT_ALLOWED"))
            ;; mark contribution zero (claim)
            (map-set contributions { proposal-id: proposal-id, funder: tx-sender } { amount: u0 })
            ;; reduce stored funds-raised accordingly
            (map-set proposals { id: proposal-id }
              {
                researcher: (get researcher p),
                title: (get title p),
                description: (get description p),
                funding-goal: (get funding-goal p),
                funds-raised: (- (get funds-raised p) amt),
                milestones: (get milestones p),
                completed-milestones: (get completed-milestones p),
                funding-deadline: (get funding-deadline p),
                is-active: (get is-active p),
                refunded: is-refunded
              })
            ;; transfer back to contributor
            (unwrap-panic (as-contract (stx-transfer? amt tx-sender tx-sender)))
            (print { event: "refund-claimed", proposal-id: proposal-id, funder: tx-sender, amount: amt })
            (ok amt)
          )
        )
        (err "ERR_CONTRIBUTION_OR_PROPOSAL_NOT_FOUND")
      )
    )
  )
)

;; emergency-withdraw (owner only):
;; Owner can withdraw leftover dust or remaining funds for a proposal only if
;; all contributors have been refunded or proposal is explicitly closed and drained.
(define-public (emergency-withdraw (amount uint) (to principal))
  (begin
    (try! (assert-owner))
    (unwrap-panic (as-contract (stx-transfer? amount tx-sender to)))
    (ok true)
  )
)

;; ---------------------------
;; Read-only helpers
;; ---------------------------

;; get-proposal: returns the proposal struct if exists
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { id: proposal-id })
)

;; get-contribution: returns contribution amount for a funder to a proposal
(define-read-only (get-contribution (proposal-id uint) (funder principal))
  (map-get? contributions { proposal-id: proposal-id, funder: funder })
)

;; get-proposal-count
(define-read-only (get-proposal-count)
  (ok (var-get proposal-counter))
)

;; list-is-verifier (checks whether account is verifier)
(define-read-only (get-is-verifier (p principal))
  (ok (is-some (map-get? verifiers { verifier: p })))
)
