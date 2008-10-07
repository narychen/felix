open Flx_util
open Flx_ast
open Flx_types
open Flx_print
open Flx_set
open Flx_mtypes2
open Flx_typing
open Flx_mbind
open Flx_srcref
open List
open Flx_unify
open Flx_treg
open Flx_generic
open Flx_maps
open Flx_exceptions
open Flx_use
open Flx_child

(* Garbage collector usage. The gc is required for non-stacked
  procedure calls, applications, closure formations,
  and variant constructors
*)

let throw_on_gc syms bbdfns e : unit = match e with
  | `BEXPR_closure (i,_),_ ->
    (*
    print_endline ("Found closure of " ^ si i);
    *)
    raise Not_found

  | `BEXPR_method_closure (_,i,_),_ ->
    (*
    print_endline ("Found method closure of " ^ si i);
    *)
    raise Not_found


  | `BEXPR_apply_direct _,_ -> raise Not_found
  | `BEXPR_apply_method_direct _,_ -> raise Not_found
  | `BEXPR_apply( (`BEXPR_closure (_,_),_),_),_ -> raise Not_found
  | `BEXPR_apply_struct (i,_,_),_ ->
    let id,sr,parent,entry=Hashtbl.find bbdfns i in
    begin match entry with
    | `BBDCL_nonconst_ctor _ -> raise Not_found
    | _ -> ()
    end

  | `BEXPR_case (_,t),_ ->
    begin match t with
    | `BTYP_sum args when not (all_units args) -> raise Not_found
    | `BTYP_inst (i,ts) ->
      let id,parent,sr,entry = try Hashtbl.find bbdfns i with Not_found -> failwith "YIKES3" in
      begin match entry with
      | `BBDCL_union (vs,idts) when not (all_voids (map (fun (_,_,t)->t) idts)) -> raise Not_found
      | _ -> ()
      end
    | _ -> ()
    end
  | _ -> ()

let expr_uses_gc syms bbdfns e =
  (*
  print_endline ("Check for gc in expr " ^ sbe syms.dfns e);
  *)
  iter_tbexpr ignore (throw_on_gc syms bbdfns) ignore e

let exe_uses_gc syms bbdfns exe =
  (*
  print_endline ("[exe_uses_gc] Exe = " ^ string_of_bexe syms.dfns 0 exe);
  *)
  match exe with
  | `BEXE_jump_direct _
  | `BEXE_call_direct _
  | `BEXE_apply_ctor _

  (* Even if the constructor is applied as a stack call, the class object
     is ALSO built by this statement, and always on the heap ..
  *)
  | `BEXE_apply_ctor_stack _
    -> raise Not_found

  (* this test is used to trap use of gc by primitives *)
  | `BEXE_call_prim (sr,i,ts,a) ->
    let id,parent,sr,entry = Hashtbl.find bbdfns i in
    begin match entry with
    | `BBDCL_callback (props,vs,ps,_,_,`BTYP_void,rqs,_)
    | `BBDCL_proc (props,vs,ps,_,rqs) ->
      (*
      print_endline "Checking primitive for gc use[2]";
      *)
      if mem `Uses_gc props
      then begin (* print_endline "Flagged as using gc"; *) raise Not_found end
      else
      iter_bexe ignore (expr_uses_gc syms bbdfns) ignore ignore ignore exe
    | _ ->
      print_endline ("Call primitive to non-primitive " ^ id ^ "<"^ si i^ ">");
      assert false
    end

  | _ ->
    iter_bexe ignore (expr_uses_gc syms bbdfns) ignore ignore ignore exe

let exes_use_gc syms bbdfns exes =
  try
    iter (exe_uses_gc syms bbdfns) exes;
    false
  with
    Not_found ->
    (*
    print_endline "GC USED HERE";
    *)
    true

let exe_uses_yield exe =
  match exe with
  | `BEXE_yield _ -> raise Not_found
  | _ -> ()

let exes_use_yield exes =
  try
    iter exe_uses_yield exes;
    false
  with
    Not_found ->
    (*
    print_endline "YIELD USED HERE";
    *)
    true

(* ALSO calculates if a function uses a yield *)
let set_gc_use syms bbdfns =
  Hashtbl.iter
  (fun i (id,parent,sr,entry) -> match entry with
  | `BBDCL_function (props,vs,ps,rt,exes) ->
    let uses_gc = exes_use_gc syms bbdfns exes in
    let uses_yield = exes_use_yield exes in
    let props = if uses_gc then `Uses_gc :: props else props in
    let props = if uses_yield then `Heap_closure :: `Yields :: `Generator :: props else props in
    if uses_gc or uses_yield
    then
    Hashtbl.replace bbdfns i (id,parent,sr,
      `BBDCL_function (`Uses_gc :: props,vs,ps,rt,exes))

  | `BBDCL_procedure (props,vs,ps,exes) ->
    if exes_use_gc syms bbdfns exes then
    Hashtbl.replace bbdfns i (id,parent,sr,
      `BBDCL_procedure (`Uses_gc :: props,vs,ps,exes))

  | `BBDCL_glr (props,vs,t, (pr,exes)) ->
    if exes_use_gc syms bbdfns exes then
    Hashtbl.replace bbdfns i (id,parent,sr,
      `BBDCL_glr (`Uses_gc :: props,vs,t,(pr,exes)))

  | `BBDCL_regmatch (props,vs,ps,rt, (a,s,se,tr)) ->
    begin
      try
        Hashtbl.iter (fun _ e -> expr_uses_gc syms bbdfns e) se
      with Not_found ->
        Hashtbl.replace bbdfns i (id,parent,sr,
          `BBDCL_regmatch (`Uses_gc :: props,vs,ps,rt,(a,s,se,tr)))
    end

  | `BBDCL_reglex (props,vs, ps, j,rt, (a,s,se,tr)) ->
    begin
      try
        Hashtbl.iter (fun _ e -> expr_uses_gc syms bbdfns e) se
      with Not_found ->
        Hashtbl.replace bbdfns i (id,parent,sr,
          `BBDCL_reglex (`Uses_gc :: props,vs,ps,j,rt,(a,s,se,tr)))
    end

  | _ -> ()
  )
  bbdfns


let is_global_var bbdfns i =
  let id,parent,sr,entry = try Hashtbl.find bbdfns i with Not_found -> failwith "YIKES1" in
  match entry with
  | `BBDCL_var _
  | `BBDCL_val _ when (match parent with None -> true | _ -> false ) -> true
  | _ -> false

let throw_on_global bbdfns i =
  if is_global_var bbdfns i then raise Not_found

let expr_uses_global bbdfns e =
  iter_tbexpr (throw_on_global bbdfns) ignore ignore e

let exe_uses_global bbdfns exe =
  iter_bexe (throw_on_global bbdfns) (expr_uses_global bbdfns) ignore ignore ignore exe

let exes_use_global bbdfns exes =
  try
    iter (exe_uses_global bbdfns) exes;
    false
  with Not_found -> true

let set_local_globals bbdfns =
  Hashtbl.iter
  (fun i (id,parent,sr,entry) -> match entry with
  | `BBDCL_function (props,vs,ps,rt,exes) ->
    if exes_use_global bbdfns exes then
    Hashtbl.replace bbdfns i (id,parent,sr,
      `BBDCL_function (`Uses_global_var :: props,vs,ps,rt,exes))

  | `BBDCL_procedure (props,vs,ps,exes) ->
    if exes_use_global bbdfns exes then
    Hashtbl.replace bbdfns i (id,parent,sr,
      `BBDCL_procedure (`Uses_global_var :: props,vs,ps,exes))

  | `BBDCL_glr (props,vs,t, (pr,exes)) ->
    if exes_use_global bbdfns exes then
    Hashtbl.replace bbdfns i (id,parent,sr,
      `BBDCL_glr (`Uses_global_var :: props,vs,t,(pr,exes)))

  | `BBDCL_regmatch (props,vs,ps,rt, (a,s,se,tr)) ->
    begin
      try
        Hashtbl.iter (fun _ e -> expr_uses_global bbdfns e) se
      with Not_found ->
        Hashtbl.replace bbdfns i (id,parent,sr,
          `BBDCL_regmatch (`Uses_global_var :: props,vs,ps,rt,(a,s,se,tr)))
    end

  | `BBDCL_reglex (props,vs, ps, j,rt, (a,s,se,tr)) ->
    begin
      try
        Hashtbl.iter (fun _ e -> expr_uses_global bbdfns e) se
      with Not_found ->
        Hashtbl.replace bbdfns i (id,parent,sr,
          `BBDCL_reglex (`Uses_global_var :: props,vs,ps,j,rt,(a,s,se,tr)))
    end

   | _ -> ()
  )
  bbdfns

type ptf_required = | Required | Not_required | Unknown

let rec set_ptf_usage syms bbdfns usage excludes i =

  (* cal reqs for functions we call and fold together *)
  let cal_reqs calls i : ptf_required * property_t =
    let result1 =
      fold_left
      (fun u (j,_) ->
        let r = set_ptf_usage syms bbdfns usage (i::excludes) j in
          (*
          print_endline ("Call of " ^ si i^ " to " ^ si j ^ " PTF of j " ^ (
            match r with
            | Unknown -> "UNKNOWN"
            | Required -> "REQUIRED"
            | Not_required -> "NOT REQUIRED"
          ));
          *)

          begin match u,r with
          | Unknown, x | x, Unknown -> x
          | Required, _ | _, Required -> Required
          | Not_required, _ (* | _, Not_required *) -> Not_required
          end
        )
        Not_required
        calls
    in
    let result2 =
      match result1 with
      | Required -> `Requires_ptf
      | Not_required -> `Not_requires_ptf
      | _ -> assert false
    in
    result1, result2
  in

  if mem i excludes then Unknown else

  (* main routine *)
  let calls = try Hashtbl.find usage i with Not_found -> [] in

  let id,parent,sr,entry =  try Hashtbl.find bbdfns i with Not_found -> failwith ("YIKES2 -- " ^ si i) in
  match entry with
  | `BBDCL_function (props,vs,ps,rt,exes) ->
    (*
    print_endline ("Function " ^ id ^ "<"^si i^"> properties " ^ string_of_properties props);
    *)
    if mem `Requires_ptf props then Required
    else if mem `Not_requires_ptf props then Not_required
    else if mem `Uses_global_var props or mem `Uses_gc props or mem `Heap_closure props then begin
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_function (`Requires_ptf :: props,vs,ps,rt,exes));
        Required
    end else begin
      let result1, result2 = cal_reqs calls i in
      (*
      print_endline ("Function " ^ id ^ " ADDING properties " ^ string_of_properties [result2]);
      *)
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_function (result2 :: props,vs,ps,rt,exes));
      result1
   end

  | `BBDCL_procedure (props,vs,ps,exes) ->
    if mem `Requires_ptf props then Required
    else if mem `Not_requires_ptf props then Not_required
    else if mem `Uses_global_var props or mem `Uses_gc props or mem `Heap_closure props then begin
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_procedure (`Requires_ptf :: props,vs,ps,exes));
        Required
    end else begin
      let result1, result2 = cal_reqs calls i in
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_procedure (result2 :: props,vs,ps,exes));
      result1
   end

  | `BBDCL_proc (props,vs,ps,ct,reqs) ->
    if mem `Requires_ptf props then Required
    else if mem `Not_requires_ptf props then Not_required
    else if mem `Uses_global_var props or mem `Uses_gc props or mem `Heap_closure props then begin
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_proc (`Requires_ptf :: props,vs,ps,ct,reqs));
        Required
    end else Not_required

  | `BBDCL_fun (props,vs,ps,ret,ct,reqs,prec) ->
    (*
    print_endline ("Fun " ^ id ^ "<"^si i^"> properties " ^ string_of_properties props);
    *)
    if mem `Requires_ptf props then Required
    else if mem `Not_requires_ptf props then Not_required
    else if mem `Uses_global_var props or mem `Uses_gc props or mem `Heap_closure props then begin
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_fun (`Requires_ptf :: props,vs,ps,ret,ct,reqs,prec));
        Required
    end else Not_required

  | `BBDCL_glr (props,vs,t, (pr,exes)) ->
    if mem `Requires_ptf props then Required
    else if mem `Not_requires_ptf props then Not_required
    else if mem `Uses_global_var props or mem `Uses_gc props or mem `Heap_closure props then begin
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_glr (`Requires_ptf :: props,vs,t,(pr,exes)));
        Required
    end else begin
      let result1, result2 = cal_reqs calls i in
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_glr (result2 :: props,vs,t,(pr,exes)));
      result1
   end

  | `BBDCL_regmatch (props,vs,ps,rt,ra) ->
    if mem `Requires_ptf props then Required
    else if mem `Not_requires_ptf props then Not_required
    else if mem `Uses_global_var props or mem `Uses_gc props or mem `Heap_closure props then begin
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_regmatch(`Requires_ptf :: props,vs,ps,rt,ra));
        Required
    end else begin
      let result1, result2 = cal_reqs calls i in
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_regmatch (result2 :: props,vs,ps,rt,ra));
      result1
   end

  | `BBDCL_reglex (props,vs, ps,j,rt,ra) ->
    if mem `Requires_ptf props then Required
    else if mem `Not_requires_ptf props then Not_required
    else if mem `Uses_global_var props or mem `Uses_gc props or mem `Heap_closure props then begin
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_reglex (`Requires_ptf :: props,vs,ps,j,rt,ra));
        Required
    end else begin
      let result1, result2 = cal_reqs calls i in
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_reglex (result2 :: props,vs,ps,j,rt,ra));
      result1
   end

  | `BBDCL_class (props,vs) ->
    if mem `Requires_ptf props then Required
    else if mem `Not_requires_ptf props then Not_required
    else if mem `Uses_global_var props or mem `Uses_gc props or mem `Heap_closure props then begin
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_class (`Requires_ptf :: props,vs));
        Required
    end else begin
      let result1, result2 = cal_reqs calls i in
      Hashtbl.replace bbdfns i (id,parent,sr,
        `BBDCL_class (result2 :: props,vs));
      result1
   end

  | _ -> Not_required

let set_globals syms bbdfns =
  set_local_globals bbdfns;
  set_gc_use syms bbdfns;

  let usage = match Flx_call.call_data syms bbdfns with u,_ -> u in
  Hashtbl.iter
  (fun i _ -> ignore (set_ptf_usage syms bbdfns usage [] i))
  bbdfns

let find_global_vars syms bbdfns =
  let gvars = ref IntSet.empty in
  Hashtbl.iter
  (fun i _ -> if is_global_var bbdfns i then gvars := IntSet.add i !gvars)
  bbdfns
  ;
  !gvars

let check_used syms bbdfns used i =
  Hashtbl.mem used i

let check_all_used syms bbdfns used ii =
  let all_used = ref true in
  IntSet.iter (fun i-> if not (check_used syms bbdfns used i)
    then begin
      print_endline ("FOUND UNUSED VARIABLE " ^ si i);
      all_used := false
    end
  )
  ii
  ;
  if !all_used then
    print_endline "ALL GLOBAL VARS ARE USED"
  else
    print_endline "Som UNUSED vars!"

let check_global_vars_all_used syms bbdfns used =
  let ii = find_global_vars syms bbdfns in
  check_all_used syms bbdfns used ii