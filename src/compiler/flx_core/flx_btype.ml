open Flx_ast
open Flx_types

exception Invalid_int_of_unitsum

type btpattern_t = {
  pattern: t;

  (* pattern type variables, including 'any' vars *)
  pattern_vars: BidSet.t;

  (* assignments for 'as' vars *)
  assignments : (bid_t * t) list
}

(** general typing *)
and t = 
  | BTYP_none
  | BTYP_sum of t list
  | BTYP_unitsum of int
  | BTYP_intersect of t list (** intersection type *)
  | BTYP_inst of bid_t * t list
  | BTYP_tuple of t list
  | BTYP_array of t * t
  | BTYP_record of string * (string * t) list
  | BTYP_variant of (string * t) list
  | BTYP_pointer of t
  | BTYP_function of t * t
  | BTYP_cfunction of t * t
  | BTYP_void
  | BTYP_fix of int * t (* meta type *)

  | BTYP_type of int
  | BTYP_type_tuple of t list
  | BTYP_type_function of (bid_t * t) list * t * t
  | BTYP_type_var of bid_t * t
  | BTYP_type_apply of t * t
  | BTYP_type_match of t * (btpattern_t * t) list

  | BTYP_tuple_cons of t * t 

  (* type sets *)
  | BTYP_type_set of t list (** open union *)
  | BTYP_type_set_union of t list (** open union *)
  | BTYP_type_set_intersection of t list (** open union *)

type entry_kind_t = {
  (* the function *)
  base_sym: bid_t;

  (* the type variables of the specialisation *)
  spec_vs: (string * bid_t) list;

  (* types to replace the old type variables expressed in terms of the new
   * ones *)
  sub_ts: t list
}

type entry_set_t =
  | FunctionEntry of entry_kind_t list
  | NonFunctionEntry of entry_kind_t

type name_map_t = (string, entry_set_t) Hashtbl.t

type biface_t =
  | BIFACE_export_fun of Flx_srcref.t * bid_t * string
  | BIFACE_export_cfun of Flx_srcref.t * bid_t * string
  | BIFACE_export_python_fun of Flx_srcref.t * bid_t * string
  | BIFACE_export_type of Flx_srcref.t * t * string

(* -------------------------------------------------------------------------- *)

(** The none type. Used when we don't know the type yet. *)
let btyp_none () =
  BTYP_none

(** The void type. *)
let btyp_void () =
  BTYP_void

(** Construct a BTYP_sum type. *)
let btyp_sum ts =
  match ts with 
  | [] -> BTYP_void
  (* | [t] -> t *)
  | _ -> 
   try 
     List.iter (fun t -> if t <> BTYP_tuple [] then raise Not_found) ts;
     BTYP_unitsum (List.length ts)
   with Not_found -> BTYP_sum ts

(** Construct a BTYP_unitsum type. *)
let btyp_unitsum n =
  match n with
  | 0 -> BTYP_void
  | 1 -> BTYP_tuple []
  | _ ->  BTYP_unitsum n

(** Construct a BTYP_intersect type. *)
let btyp_intersect ts =
  BTYP_intersect ts

let btyp_inst (bid, ts) =
  BTYP_inst (bid, ts)

(** Construct a BTYP_tuple type. *)
let btyp_tuple = function
  | [] -> BTYP_tuple []
  | [t] -> t
  | (head :: tail) as ts ->
      (* If all the types are the same, reduce the type to a BTYP_array. *)
      try
        List.iter (fun t -> if t <> head then raise Not_found) tail;
        BTYP_array (head, (BTYP_unitsum (List.length ts)))
      with Not_found ->
        BTYP_tuple ts

let btyp_tuple_cons t ts = BTYP_tuple_cons (t,ts)

(** Construct a BTYP_array type. *)
let btyp_array (t, n) =
  match n with
  | BTYP_void -> BTYP_tuple []
(*
  | BTYP_tuple [] -> t
*)
  | _ -> BTYP_array (t, n)

(** Construct a BTYP_record type. *)
let btyp_record name ts = 
      (* Make sure all the elements are sorted by name. *)
      let ts = List.sort compare ts in
      BTYP_record (name,ts)

(** Construct a BTYP_variant type. *)
let btyp_variant = function
  | [] -> BTYP_void
  | ts ->
      (* Make sure all the elements are sorted by name. *)
      let ts = List.sort compare ts in
      BTYP_variant ts

(** Construct a BTYP_pointer type. *)
let btyp_pointer ts =
  BTYP_pointer ts

(** Construct a BTYP_function type. *)
let btyp_function (args, ret) =
  BTYP_function (args, ret)

(** Construct a BTYP_cfunction type. *)
let btyp_cfunction (args, ret) =
  BTYP_cfunction (args, ret)

(** Construct a BTYP_fix type. *)
let btyp_fix i mt =
  BTYP_fix (i, mt)

(** Construct a BTYP_type type. *)
let btyp_type i =
  BTYP_type i

(** Construct a BTYP_type_tuple type. *)
let btyp_type_tuple ts =
  BTYP_type_tuple ts

(** Construct a BTYP_function type. *)
let btyp_type_function (args, ret, body) =
  BTYP_type_function (args, ret, body)

(** Construct a BTYP_type_var type. *)
let btyp_type_var (bid, t) =
  BTYP_type_var (bid, t)

(** Construct a BTYP_type_apply type. *)
let btyp_type_apply (f, a) =
  BTYP_type_apply (f, a)

(** Construct a BTYP_type_match type. *)
let btyp_type_match (t, ps) =
  BTYP_type_match (t, ps)

(** Construct a BTYP_type_set type. *)
let btyp_type_set ts =
  BTYP_type_set ts

(** Construct a BTYP_type_set_union type. *)
let btyp_type_set_union ts =
  BTYP_type_set_union ts

(** Construct a BTYP_type_set_intersection type. *)
let btyp_type_set_intersection ts =
  BTYP_type_set_intersection ts

(* -------------------------------------------------------------------------- *)

(** Returns if the bound type is void. *)
let is_void = function
  | BTYP_void -> true
  | _ -> false

(** Returns if the bound type is unit. *)
let is_unit = function
  | BTYP_tuple [] -> true
  | _ -> false

(** Returns if the bound type list is all void types. *)
let all_voids = List.for_all is_void

(** Returns if the bound type list is all unit types. *)
let all_units = List.for_all is_unit

(** Returns if the bound type is or is equivalent to a BTYP_unitsum. *)
let is_unitsum t = match t with
  | BTYP_void -> true
  | BTYP_tuple [] -> true
  | BTYP_unitsum _ -> true
  | BTYP_sum ts -> all_units ts
  | _ -> false

(** Returns the integer value of the unit sum type. *)
let rec int_of_linear_type bsym_table t = match t with
  | BTYP_void -> 0
  | BTYP_tuple [] -> 1
  | BTYP_unitsum k -> k
  | BTYP_sum [] ->  0
  | BTYP_sum ts ->
    List.fold_left (fun i t -> i + int_of_linear_type bsym_table t) 0 ts
  | BTYP_tuple ts ->
    List.fold_left (fun i t -> i * int_of_linear_type bsym_table t) 1 ts
  | BTYP_array (a,BTYP_unitsum n) -> 
    let sa = int_of_linear_type bsym_table a in
    let rec aux n out = if n = 0 then out else aux (n-1) (out * sa)
    in aux n 1
  | _ -> raise (Invalid_int_of_unitsum)

let islinear_type bsym_table t =
  try ignore( int_of_linear_type bsym_table t ); true 
  with Invalid_int_of_unitsum -> false

let sizeof_linear_type bsym_table t = 
  try int_of_linear_type bsym_table t 
  with Invalid_int_of_unitsum -> assert false

let ncases_of_sum bsym_table t = match t with
  | BTYP_unitsum n -> n
  | BTYP_sum ls -> List.length ls 
  | BTYP_void -> 0
  | _ -> 1


(* -------------------------------------------------------------------------- *)

(** Iterate over each bound type and call the function on it. *)
let flat_iter
  ?(f_bid=fun _ -> ())
  ?(f_btype=fun _ -> ())
  btype
=
  match btype with
  | BTYP_none -> ()
  | BTYP_sum ts -> List.iter f_btype ts
  | BTYP_unitsum k ->
      let unitrep = BTYP_tuple [] in
      for i = 1 to k do f_btype unitrep done
  | BTYP_intersect ts -> List.iter f_btype ts
  | BTYP_inst (i,ts) -> f_bid i; List.iter f_btype ts
  | BTYP_tuple ts -> List.iter f_btype ts
  | BTYP_array (t1,t2)->  f_btype t1; f_btype t2
  | BTYP_record (_,ts) -> List.iter (fun (s,t) -> f_btype t) ts
  | BTYP_variant ts -> List.iter (fun (s,t) -> f_btype t) ts
  | BTYP_pointer t -> f_btype t
  | BTYP_function (a,b) -> f_btype a; f_btype b
  | BTYP_cfunction (a,b) -> f_btype a; f_btype b
  | BTYP_void -> ()
  | BTYP_fix _ -> ()
  | BTYP_type _ -> ()
  | BTYP_tuple_cons (a,b) -> f_btype a; f_btype b
  | BTYP_type_tuple ts -> List.iter f_btype ts
  | BTYP_type_function (its, a, b) ->
      (* The first argument of [its] is an index, not a bid. *)
      List.iter (fun (_,t) -> f_btype t) its;
      f_btype a;
      f_btype b
  | BTYP_type_var (_,t) ->
      (* The first argument of [BTYP_type_var] is just a unique integer, not a
       * bid. *)
      f_btype t
  | BTYP_type_apply (a,b) -> f_btype a; f_btype b
  | BTYP_type_match (t,ps) ->
      f_btype t;
      List.iter begin fun (tp, t) ->
        f_btype tp.pattern;
        List.iter (fun (i, t) -> f_bid i; f_btype t) tp.assignments;
        f_btype t
      end ps
  | BTYP_type_set ts -> List.iter f_btype ts
  | BTYP_type_set_union ts -> List.iter f_btype ts
  | BTYP_type_set_intersection ts -> List.iter f_btype ts


(** Recursively iterate over each bound type and call the function on it. *)
let rec iter
  ?(f_bid=fun _ -> ())
  ?(f_btype=fun _ -> ())
  btype
=
  f_btype btype;
  let f_btype btype = iter ~f_bid ~f_btype btype in
  flat_iter ~f_bid ~f_btype btype


(** Recursively iterate over each bound type and transform it with the
 * function. *)
let map ?(f_bid=fun i -> i) ?(f_btype=fun t -> t) = function
  | BTYP_none as x -> x
  | BTYP_sum ts -> btyp_sum (List.map f_btype ts)
  | BTYP_unitsum k ->
    let mapped_unit = f_btype (BTYP_tuple []) in
    begin match mapped_unit with
    | BTYP_tuple [] -> BTYP_unitsum k
    | _ -> BTYP_sum (Flx_list.repeat mapped_unit k)
    end
  | BTYP_intersect ts -> btyp_intersect (List.map f_btype ts)
  | BTYP_inst (i,ts) -> btyp_inst (f_bid i, List.map f_btype ts)
  | BTYP_tuple ts -> btyp_tuple (List.map f_btype ts)
  | BTYP_array (t1,t2) -> btyp_array (f_btype t1, f_btype t2)
  | BTYP_record (n,ts) -> btyp_record n (List.map (fun (s,t) -> s, f_btype t) ts)
  | BTYP_variant ts -> btyp_variant (List.map (fun (s,t) -> s, f_btype t) ts)
  | BTYP_pointer t -> btyp_pointer (f_btype t)
  | BTYP_function (a,b) -> btyp_function (f_btype a, f_btype b)
  | BTYP_cfunction (a,b) -> btyp_cfunction (f_btype a, f_btype b)
  | BTYP_void as x -> x
  | BTYP_fix _ as x -> x
  | BTYP_tuple_cons (a,b) -> btyp_tuple_cons (f_btype a) (f_btype b)
  | BTYP_type _ as x -> x
  | BTYP_type_tuple ts -> btyp_type_tuple (List.map f_btype ts)
  | BTYP_type_function (its, a, b) ->
      btyp_type_function (List.map (fun (i,t) -> f_bid i, f_btype t) its, f_btype a, f_btype b)
  | BTYP_type_var (i,t) -> btyp_type_var (f_bid i, f_btype t)
  | BTYP_type_apply (a, b) -> btyp_type_apply (f_btype a, f_btype b)
  | BTYP_type_match (t,ps) ->
      let ps =
        List.map begin fun (tp, t) ->
          { tp with
            pattern = f_btype tp.pattern;
            assignments = List.map
              (fun (i, t) -> f_bid i, f_btype t)
              tp.assignments },
          f_btype t
        end ps
      in
      btyp_type_match (f_btype t, ps)
  | BTYP_type_set ts ->
      let g acc elt =
        (* SHOULD USE UNIFICATIION! *)
        let elt = f_btype elt in
        if List.mem elt acc then acc else elt::acc
      in
      let ts = List.rev (List.fold_left g [] ts) in
      if List.length ts = 1 then List.hd ts else
      btyp_type_set ts
  | BTYP_type_set_union ls -> btyp_type_set_union (List.map f_btype ls)
  | BTYP_type_set_intersection ls ->
      btyp_type_set_intersection (List.map f_btype ls)

