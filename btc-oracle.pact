(module btc_oracle_mod GOV
  (use free.util-time)
  (use free.util-math)
  (use free.util-lists)

  (defcap GOV ()
    (enforce false "Module not upgradable"))

  (defschema btc-block
    header:string
    ts:time
    header-hash:integer
    target:integer
    height:integer
  )

  (defschema tip
    header-hash:integer
    height:integer
  )

  (deftable btc-block-table:{btc-block})

  (deftable tip-table:{tip})

  (defconst BYTE-MASKS (map (shift 255) (enumerate 0 248 8)))
  (defconst BYTE-MASK-0 255)
  (defconst BYTE-MASK-1 (shift 255 8))
  (defconst BYTE-MASK-2 (shift 255 16))
  (defconst BYTE-MASK-3 (shift 255 24))

  (defconst BLOCK-TIME 600.0)
  (defconst BLOCK-RATE (/ 1.0 BLOCK-TIME))

  (defconst MAX-FORK-DEPTH 2)

  (defconst NULL-BLOCK {'header:"", 'ts:(epoch), 'header-hash:0, 'target:0, 'height:-1})


  (defun from-hex:integer (x:string)
    (str-to-int 16 x))

  (defun to-hex:string (x:integer)
    (int-to-str 16 x))

  (defun swap-end-256:integer (x:integer)
    @doc "Swap endianess for a 256 bits integer"
    (fold (|) 0 (zip (shift) (map (& x) BYTE-MASKS)
                             (enumerate 248 -248 -16))))

  (defun swap-end-32:integer (x:integer)
    @doc "Swap endianess for a 32 bits integer"
    (| (| (shift x -24)
          (& (shift x -8) BYTE-MASK-1))
       (| (& (shift x  8) BYTE-MASK-2)
          (& (shift x 24) BYTE-MASK-3)))
  )

  (defun i-div:decimal (x:integer y:integer)
    @doc "Divide 2 integers"
    (round (/ (dec x) (dec y)) 8))

  (defun key:string (x-hash:integer)
    (int-to-str 64 x-hash))

  (defun i32-field:integer (hex-string:string position:integer)
    @doc "Take a 32 bit integer from a hex string"
    (swap-end-32 (from-hex (take 8 (drop position hex-string)))))

  (defun get-previous-hash:integer (header:string)
    @doc "Returns the field parent-hash from a BTC Header"
    (from-hex (take 64 (drop 8 header))))

  (defun unpack-target:integer (x:integer)
    @doc "Unpack a target field from a BTC header following BTC specification"
    (shift (& 16777215 x)
           (shift (- (shift (& BYTE-MASK-3 x) -24) 3) 3)))

  (defun get-timestamp:time (header:string)
    @doc "Returns the timestamp from a BTC header"
    (from-timestamp (dec (i32-field header 136))))

  (defun get-target:integer (header:string)
    @doc "Returns the targer from a BTC header"
    (unpack-target (i32-field header 144)))

  (defun compute-hash:integer (header:string)
    (enforce (= 160 (length header)) "Header must have a size of 80 bytes")
    (sha256_mod.digest-btc-header header))

  (defun enforce-pow (computed-hash:integer target:integer)
    @doc "Verify that the hash of the block meet a target specification"
    (enforce (<= (swap-end-256 computed-hash) target) "Proof of work error"))

  (defun enforce-target (old-target:integer target:integer new-height:integer)
    @doc "Verify that the target is consistent between 2 BTC blocks"
    (enforce (if (= 0 (mod new-height 2016))
                 ; Changing the target is only allowed each 2016 blocks in BTC
                 (between 0.25 4.0 (i-div target old-target))
                 (= old-target target))
             "Target error in block")
  )

  (defun enforce-fork-limit(height:integer tip-height:integer)
    (enforce (<= (- height tip-height) MAX-FORK-DEPTH) (format "Fork too deep {} / {}" [height tip-height])))

  (defun get-parent:object{btc-block} (block:object{btc-block})
    (get-block-by-hash (get-previous-hash (at 'header block))))

  (defun get-parent*:object{btc-block} (block:object{btc-block} _:integer)
    (get-block-by-hash (get-previous-hash (at 'header block))))

  ;-----------------------------------
  ; Public Reports functions
  ;-----------------------------------
  (defun init-block:string (header:string block-height:integer)
    @doc "Initialize the database with an header and a corresponding block height. \
        \ Can only be used once"
    (let ((computed-hash (compute-hash header))
          (target (get-target header))
          (ts (get-timestamp header)))

      (enforce-pow computed-hash target)
      (with-default-read tip-table "tip" {'height:-1} {'height:=tip-height}
        (enforce (= tip-height -1) "Only usable for an empty chain"))
      (insert tip-table "tip" {'height:block-height, 'header-hash:computed-hash})
      (insert btc-block-table (key computed-hash) {'header:header,
                                                   'ts:ts,
                                                   'header-hash:computed-hash,
                                                   'target:target,
                                                   'height:block-height}))
  )

  (defun report-block:string (header:string)
    @doc "Report a new block header"
    (let ((computed-hash (compute-hash header))
          (previous-hash (get-previous-hash header))
          (target (get-target header))
          (ts (get-timestamp header)))
      ; Look for the parent
      (with-read btc-block-table (key previous-hash) {'height:=parent-height, 'target:=parent-target}
        (let ((new-height (++ parent-height)))
          ; Check the target value
          (enforce-target parent-target target new-height)

          ; Check the hash of the header
          (enforce-pow computed-hash target)

          ; Look for the tip
          (with-read tip-table "tip" {'height:=tip-height}
            ; Check the fork depth
            (enforce-fork-limit new-height tip-height)
            ;Update the tip if necessary
            (if (>= new-height tip-height) (update tip-table "tip" {'height:new-height, 'header-hash:computed-hash}) ""))

          ; Write the block
          (insert btc-block-table (key computed-hash) {'header:header,'ts:ts,
                                                      'header-hash:computed-hash,
                                                      'target:target,
                                                      'height:new-height}))))
  )

  ;-----------------------------------
  ; Public Consumer functions
  ;-----------------------------------
  ; The iteration object is a 2 elements list:
  ;   - #0 : Current block = Incremented at each iteration
  ;   - #1 : Best block found = Changed when a better block is found: lower in height is better
  (defun --iter-and-select:[object{btc-block}] (after-time:time it:[object{btc-block}] _:integer)
    (let ((current (at 0 it))
          (best (at 1 it)))
      [(get-parent current) (if (> (at "ts" current) after-time) current best)])
  )

  (defun select-block:object{btc-block} (after-height:integer after-time:time confirmations:integer)
    (let* ((tip (get-tip))
           (tip-height (at 'height tip))
           (blocks-to-rewind (- tip-height after-height)))
      (enforce (>= blocks-to-rewind 0) "Height not reached")

      (let ((candidate (at 1 (fold (--iter-and-select after-time) [tip NULL-BLOCK] (enumerate 0 blocks-to-rewind)))))
        (enforce (!= candidate NULL-BLOCK) "Block not found")
        (enforce (>= (- tip-height (at 'height candidate)) confirmations) "Block has not enough confirmations")
        candidate)
    )
  )

  (defun select-hash:integer (after-height:integer after-time:time confirmations:integer)
    (at 'header-hash (select-block after-height after-time confirmations)))


  ;-----------------------------------
  ; Public Util funvtions
  ;-----------------------------------
  (defun get-block-by-hash:object{btc-block} (_hash:integer)
    @doc "Return a block from an integer hash"
    (read btc-block-table (key _hash)))

  (defun get-block-by-hex-hash:object{btc-block} (hex-hash:string)
    @doc "Return a block from an Hex hash"
    (get-block-by-hash (swap-end-256 (from-hex hex-hash))))

  (defun get-block-by-height:object{btc-block} (height:integer)
    @doc "Return the block at a given height"
    (with-read tip-table "tip" {'height:=tip-height, 'header-hash:=tip-hash}
      (fold (get-parent*) (get-block-by-hash tip-hash) (enumerate 1 (- tip-height height)))))

  (defun get-tip:object{btc-block} ()
    @doc "Return the tip"
    (with-read tip-table "tip" {'header-hash:=tip-hash}
      (get-block-by-hash tip-hash)))

  (defun get-last-blocks:[object{btc-block}] (count:integer)
    @doc "Return the last N blocks"
    (fold (lambda (x _) (append-last x (get-parent (last x)))) [(get-tip)]
          (enumerate 2 count))
  )

  (defun est-btc-height-at-time (target:time)
    @doc "Estimate a BTC height at a given time"
    (bind (get-tip) {'ts:=tip-ts, 'height:=tip-height}
      ; Tip must be recent
      (enforce (> tip-ts (from-now (hours -2))) "Tip outdated")
      (+ tip-height (round (* (diff-time target tip-ts) BLOCK-RATE))))
  )
)
