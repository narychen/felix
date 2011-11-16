open Flx_ast
open Flx_types

type t = private
  | BEXE_label of Flx_srcref.t * string
  | BEXE_comment of Flx_srcref.t * string (* for documenting generated code *)
  | BEXE_halt of Flx_srcref.t * string  (* for internal use only *)
  | BEXE_trace of Flx_srcref.t * string * string  (* for internal use only *)
  | BEXE_goto of Flx_srcref.t * string  (* for internal use only *)
  | BEXE_ifgoto of Flx_srcref.t * Flx_bexpr.t * string  (* for internal use only *)
  | BEXE_call of Flx_srcref.t * Flx_bexpr.t * Flx_bexpr.t
  | BEXE_call_direct of Flx_srcref.t * bid_t * Flx_btype.t list * Flx_bexpr.t
  | BEXE_call_stack of Flx_srcref.t * bid_t * Flx_btype.t list * Flx_bexpr.t
  | BEXE_call_prim of Flx_srcref.t * bid_t * Flx_btype.t list * Flx_bexpr.t
  | BEXE_jump of Flx_srcref.t * Flx_bexpr.t * Flx_bexpr.t
  | BEXE_jump_direct of Flx_srcref.t * bid_t * Flx_btype.t list * Flx_bexpr.t
  | BEXE_svc of Flx_srcref.t * bid_t
  | BEXE_fun_return of Flx_srcref.t * Flx_bexpr.t
  | BEXE_yield of Flx_srcref.t * Flx_bexpr.t
  | BEXE_proc_return of Flx_srcref.t
  | BEXE_nop of Flx_srcref.t * string
  | BEXE_code of Flx_srcref.t * Flx_code_spec.t
  | BEXE_nonreturn_code of Flx_srcref.t * Flx_code_spec.t
  | BEXE_assign of Flx_srcref.t * Flx_bexpr.t * Flx_bexpr.t
  | BEXE_init of Flx_srcref.t * bid_t * Flx_bexpr.t
  | BEXE_begin
  | BEXE_end
  | BEXE_assert of Flx_srcref.t * Flx_bexpr.t
  | BEXE_assert2 of Flx_srcref.t * Flx_srcref.t * Flx_bexpr.t option * Flx_bexpr.t
  | BEXE_axiom_check of Flx_srcref.t * Flx_bexpr.t
  | BEXE_axiom_check2 of Flx_srcref.t * Flx_srcref.t * Flx_bexpr.t option * Flx_bexpr.t

(* -------------------------------------------------------------------------- *)

val bexe_label : Flx_srcref.t * string -> t
val bexe_comment : Flx_srcref.t * string -> t
val bexe_halt : Flx_srcref.t * string -> t
val bexe_trace : Flx_srcref.t * string * string -> t
val bexe_goto : Flx_srcref.t * string -> t
val bexe_ifgoto : Flx_srcref.t * Flx_bexpr.t * string -> t
val bexe_call : Flx_srcref.t * Flx_bexpr.t * Flx_bexpr.t -> t
val bexe_call_direct : Flx_srcref.t * bid_t * Flx_btype.t list * Flx_bexpr.t -> t
val bexe_call_stack : Flx_srcref.t * bid_t * Flx_btype.t list * Flx_bexpr.t -> t
val bexe_call_prim : Flx_srcref.t * bid_t * Flx_btype.t list * Flx_bexpr.t -> t
val bexe_jump : Flx_srcref.t * Flx_bexpr.t * Flx_bexpr.t -> t
val bexe_jump_direct : Flx_srcref.t * bid_t * Flx_btype.t list * Flx_bexpr.t -> t
val bexe_svc : Flx_srcref.t * bid_t -> t
val bexe_fun_return : Flx_srcref.t * Flx_bexpr.t -> t
val bexe_yield : Flx_srcref.t * Flx_bexpr.t -> t
val bexe_proc_return : Flx_srcref.t -> t
val bexe_nop : Flx_srcref.t * string -> t
val bexe_code : Flx_srcref.t * Flx_code_spec.t -> t
val bexe_nonreturn_code : Flx_srcref.t * Flx_code_spec.t -> t
val bexe_assign : Flx_srcref.t * Flx_bexpr.t * Flx_bexpr.t -> t
val bexe_init : Flx_srcref.t * bid_t * Flx_bexpr.t -> t
val bexe_begin : unit -> t
val bexe_end : unit -> t
val bexe_assert : Flx_srcref.t * Flx_bexpr.t -> t
val bexe_assert2 : Flx_srcref.t * Flx_srcref.t * Flx_bexpr.t option * Flx_bexpr.t -> t
val bexe_axiom_check2 : Flx_srcref.t * Flx_srcref.t * Flx_bexpr.t option * Flx_bexpr.t -> t
val bexe_axiom_check : Flx_srcref.t * Flx_bexpr.t -> t

(* -------------------------------------------------------------------------- *)

(** Extract the source of the bound executable. *)
val get_srcref : t -> Flx_srcref.t

(* -------------------------------------------------------------------------- *)

(** Returns whether or not this executable is terminating. *)
val is_terminating : t -> bool

(* -------------------------------------------------------------------------- *)

(** Recursively iterate over each bound exe and call the function on it. *)
val iter :
  ?f_bid:(Flx_types.bid_t -> unit) ->
  ?f_btype:(Flx_btype.t -> unit) ->
  ?f_bexpr:(Flx_bexpr.t -> unit) ->
  t ->
  unit

(** Recursively iterate over each bound exe and transform it with the
 * function. *)
val map :
  ?f_bid:(Flx_types.bid_t -> Flx_types.bid_t) ->
  ?f_btype:(Flx_btype.t -> Flx_btype.t) ->
  ?f_bexpr:(Flx_bexpr.t -> Flx_bexpr.t) ->
  t ->
  t

(* -------------------------------------------------------------------------- *)

(** Simplify the bound exe. *)
val reduce : t -> t

(* -------------------------------------------------------------------------- *)

(** Prints a bexe to a formatter. *)
val print : Format.formatter -> t -> unit
