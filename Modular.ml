(* Note: We must take care of avoiding overflows in the underlying integer
 * operations. For instance, the modular multiplication is not as simple as
 * [(a * b) mod m] (it is when [m]² < [max_int]).
 *     https://www.quora.com/How-can-I-execute-A-*-B-mod-C-without-overflow-if-A-and-B-are-lesser-than-C/answer/Dana-Jacobsen
 *     https://en.wikipedia.org/wiki/Modular_arithmetic#Example_implementations
 *)

let sqrt_max_int = 1 lsl ((Sys.int_size - 1) / 2)

(* User-facing functions perform domain checks before calling internal
 * functions. Internal functions are prefixed with an underscore. *)

let _add ~modulo:m a b =
  let m_b = m - b in
  if a < m_b then
    a + b
  else
    a - m_b
let[@inline] add ~modulo:m a b =
  assert (0 <= a && a < m) ;
  assert (0 <= b && b < m) ;
  _add ~modulo:m a b

let _opp ~modulo:m a =
  if a = 0 then
    0
  else
    m - a
let[@inline] opp ~modulo:m a =
  assert (0 <= a && a < m) ;
  _opp ~modulo:m a

let _sub ~modulo:m a b =
  if a >= b then
    a - b
  else
    a + (m - b)
let[@inline] sub ~modulo:m a b =
  assert (0 <= a && a < m) ;
  assert (0 <= b && b < m) ;
  _sub ~modulo:m a b

let _mul ~modulo:m a b =
  if (a lor b) < sqrt_max_int then
    (a * b) mod m
  else begin
    let ra = ref a in
    let rb = ref b in
    if a < b then begin
      ra := b ;
      rb := a ;
    end ;
    let res = ref 0 in
    while !rb > 0 do
      (*
      if !rb mod 2 = 1 then
        res := _add ~modulo:m !res !ra ;
      ra := _add ~modulo:m !ra !ra ;
      rb := !rb / 2 ;
      *)
      (* Inlining this code manually gives considerable speedup: *)
      let a = !ra in
      let b = !rb in
      let m_a = m - a in
      if b land 1 <> 0 then
        res := (let r = !res in if r < m_a then r + a else r - m_a) ;
      ra := (if a < m_a then a + a else a - m_a) ;
      rb := b lsr 1 ;
    done ;
    !res
  end
let[@inline] mul ~modulo:m a b =
  assert (0 <= a && a < m) ;
  assert (0 <= b && b < m) ;
  _mul ~modulo:m a b

(* We compute the modular inverse using an extended Euclidean algorithm. We
 * reimplement the algorithm instead of using [Arith.gcdext] directly because
 * in the latter function Bézout’s coefficients can overflow, whereas we are
 * only interested in their class modulo [m].
 * [gcdext ~modulo:m b] returns a pair [(d, v)] where [1 ≤ d ≤ m] is the GCD of
 * [m] and [b], and [0 ≤ v < m] is such that [d = v·b  (mod m)]. It never fails;
 * when [b = 0], it returns [d = m].
 * Such a [v] is defined modulo [m/d].
 * TODO: always return minimal [v]?
 * TODO: Can we always return a [v] that is invertible modulo [m]? I’m under the
 * impression that we can, and that either the smallest or the largest non-null
 * representative (whichever is closest to a multiple of [m]) is invertible, but
 * I’m not sure how to prove it at the moment.
 *)
let gcdext ~modulo:m b0 =
  (* By contrast with [Arith.gcdext], we are not interested in returning [u], so
   * we need neither [u] nor [x] parameters.
   * Invariants:
   *   0 ≤ b < a ≤ m
   *   a = v·b0  (mod m)
   *   b = y·b0  (mod m)
   *   0 ≤ v < m
   *   0 ≤ y < m  unless m = 1
   *)
  let rec gcdext a b v y =
    if b >= 2 then
      (* Here [a/b < m] since [b ≥ 2], so we can avoid computing [a/b mod m]: *)
      gcdext b (a mod b) y (_sub ~modulo:m v (_mul ~modulo:m (a/b) y))
    else if b = 1 then
      (1, y)
    else (* b = 0 *)
      (a, v)
  in
  gcdext m b0 0 1

let _inv ~modulo:m b =
  let (d, v) = gcdext ~modulo:m b in
  if d = 1 then
    v
  else
    raise Division_by_zero
let[@inline] inv ~modulo:m b =
  assert (0 <= b && b < m) ;
  _inv ~modulo:m b

let _div ~modulo:m a b =
  _mul ~modulo:m a (_inv ~modulo:m b)
let[@inline] div ~modulo:m a b =
  assert (0 <= a && a < m) ;
  assert (0 <= b && b < m) ;
  _div ~modulo:m a b

let _div_nonunique ~modulo:m a b =
  let (d, v) = gcdext ~modulo:m b in
  if a mod d = 0 then
    _mul ~modulo:m (a / d) v
  else
    raise Division_by_zero
let[@inline] div_nonunique ~modulo:m a b =
  assert (0 <= a && a < m) ;
  assert (0 <= b && b < m) ;
  _div_nonunique ~modulo:m a b

exception Factor_found of int

(*
let inv_factorize ~modulo:m b =
  begin try
    inv ~modulo:m b
  with Division_by_zero when b <> 0 ->
    let d = Arith.gcd m b in
    raise (Factor_found d)
  end
*)
let _inv_factorize ~modulo:m b =
  let (d, v) = gcdext ~modulo:m b in
  if d = 1 then
    v
  else if d = m then
    raise Division_by_zero
  else
    raise (Factor_found d)
let[@inline] inv_factorize ~modulo:m b =
  assert (0 <= b && b < m) ;
  _inv_factorize ~modulo:m b

let _pow ~modulo:m =
  (* For [m] = 1, [Common.pow] would not produce canonical values: *)
  if m = 1 then
    fun _a _n -> 0
  else
    fun a n ->
      if 0 <= n then
        Common.pow ~mult:(_mul ~modulo:m) ~unit:1 a n
      else
        Common.pow ~mult:(_mul ~modulo:m) ~unit:1 (_inv ~modulo:m a) ~-n
let[@inline] pow ~modulo:m a n =
  assert (0 <= a && a < m) ;
  assert (n <> Stdlib.min_int) ;
  _pow ~modulo:m a n

let _rand ~modulo:m () =
  Arith.rand ~max:(m-1) ()
let[@inline] rand ~modulo:m () =
  assert (0 < m) ;
  _rand ~modulo:m ()

(******************************************************************************)

module Make (M : sig val modulo : int end) = struct

  let () =
    assert (M.modulo <> 0) ;
    assert (M.modulo <> Stdlib.min_int)

  let modulo = abs M.modulo

  type t = int

  let of_int a =
    Arith.erem a modulo
  let ( !: ) = of_int

  let to_int a =
    a

  let opp = _opp ~modulo
  let ( ~-: ) = opp

  let inv = _inv ~modulo
  let ( ~/: ) = inv

  let ( +: ) = _add ~modulo

  let ( -: ) = _sub ~modulo

  let ( *: ) = _mul ~modulo

  let ( /: ) = _div ~modulo

  let ( //: ) = _div_nonunique ~modulo

  let inv_factorize = _inv_factorize ~modulo

  let pow = _pow ~modulo
  let ( **: ) = pow

  let rand = _rand ~modulo

  let ( ~-:. ) a = ~-: !:a
  let ( ~/:. ) a = ~/: !:a
  let ( +:. ) a b = a +: !:b
  let ( +.: ) a b = !:a +: b
  let ( +.. ) a b = !:a +: !:b
  let ( -:. ) a b = a -: !:b
  let ( -.: ) a b = !:a -: b
  let ( -.. ) a b = !:a -: !:b
  let ( *.: ) a b = !:a *: b
  let ( *:. ) a b = a *: !:b
  let ( *.. ) a b = !:a *: !:b
  let ( /.: ) a b = !:a /: b
  let ( /:. ) a b = a /: !:b
  let ( /.. ) a b = !:a /: !:b
  let ( //.: ) a b = !:a //: b
  let ( //:. ) a b = a //: !:b
  let ( //.. ) a b = !:a //: !:b
  let ( **.: ) a b = !:a **: b

end



(* tests *)
(* FIXME: Use an actual tool for unit tests. *)
let () =
  assert (mul ~modulo:max_int (max_int - 7) 2 = (max_int - 14)) ;
  assert (inv ~modulo:max_int (max_int-1) = (max_int-1)) ;
  assert (mul ~modulo:(max_int - 1) (max_int - 3) (max_int - 7) = 12) ;
  assert (inv ~modulo:42 37 = 25) ;
  ()
